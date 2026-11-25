import 'dart:async';
import 'dart:io';

import 'package:popoling_core/contracts.dart';

import '../git/git_adapter.dart';
import '../log/log_store.dart';
import '../process/process_launcher.dart';
import '../ready/readiness.dart';
import '../runtime/runtime_store.dart';
import 'env_file.dart';
import 'start_order.dart';

/// 떠 있는 프로세스 항목 하나.
typedef LiveProcess = ({ItemRef item, ProcessService service, RunningProcess process});

/// [Orchestrator] 의 진짜 구현. 정책은 기획서 §6.
///
/// - 프로세스 항목은 [processes] 로 직접 띄우고, Compose·원격 항목은 C 의 [ItemLauncher] 에 맡긴다.
/// - 멈추는 건 이 객체가 띄운 프로세스와 `popoling-<프로젝트ID>` Compose 항목뿐이다. 포트·PID 만으로 멈추지 않는다.
/// - 다른 기능의 구현은 함수로 받아 처음 쓸 때 꺼낸다(`AppRegistry` 약속: 등록이 다 끝난 뒤 꺼낸다).
/// - 항목마다 시작은 한 번에 하나만 돈다. 시작하는 중에 멈추면 그 시작은 상태를 바꾸지 않고 끝난다.
/// - 마지막 전체 실행 결과와 띄운 프로세스는 [store] 에 남긴다. 앱을 다시 켰을 때 되살리는 건 복구(FR-11)가 한다.
class RunnerOrchestrator implements Orchestrator {
  RunnerOrchestrator({
    required this.projects,
    required this.launcher,
    required this.ports,
    required this.http,
    required this.runtime,
    required this.processes,
    required this.logs,
    required this.store,
    this.git,
  });

  final ProjectRepository Function() projects;
  final ItemLauncher Function() launcher;
  final PortProbe Function() ports;
  final HttpProbe Function() http;
  final RuntimeQuery Function() runtime;
  final ProcessLauncher processes;
  final LogStore logs;
  final RuntimeStore store;

  /// 전체 실행 전에 최신 코드를 받는다. 없으면 받지 않는다.
  final GitAdapter? git;

  final _events = StreamController<RunEvent>.broadcast();
  final _states = <ItemRef, ItemState>{};
  final _running = <ItemRef, RunningProcess>{};
  final _exitCodes = <ItemRef, int>{};

  /// 진행 중인 시작. 멈추면 완료해서 그 시작을 끊는다.
  final _starting = <ItemRef, Completer<void>>{};

  /// 진행 중인 시작의 결과. 같은 항목을 또 시작하면(전체 실행과 단일 시작이 겹칠 때 등) 이걸 같이 기다린다.
  final _ups = <ItemRef, Future<ItemResult>>{};
  final _stopping = <ItemRef>{};

  /// 앱을 다시 켠 뒤 되살린 항목. 준비 완료가 아니어도 끝나면 상태를 바꾼다.
  final _recovered = <ItemRef>{};

  /// 띄울 때 쓴 설정. 설정 파일이 깨지거나 항목이 빠져도 띄운 것은 멈출 수 있어야 한다.
  final _launched = <ItemRef, ServiceConfig>{};
  final _runAlls = <String, Future<RunSummary>>{};

  Future<void>? _recovery;

  /// 아직 정리가 끝나지 않은 시작. 멈춰서 [_ups] 에서 빠진 것도 들어 있다.
  final _inFlight = <Future<void>>{};

  /// 프로젝트별 전체 종료 횟수. 전체 실행은 시작 때 값과 달라지면 남은 항목을 띄우지 않는다.
  final _stopAlls = <String, int>{};

  Readiness get _readiness => Readiness(ports: ports(), http: http());

  @override
  Stream<RunEvent> get events => _events.stream;

  @override
  ItemState stateOf(ItemRef item) => _states[item] ?? ItemState.stopped;

  /// 지금 떠 있는, 이 객체가 띄운 프로세스 항목. `RuntimeQuery` 가 포트 주인을 판단할 때 쓴다.
  Iterable<LiveProcess> get liveProcesses => [
        for (final MapEntry(key: item, value: process) in _running.entries)
          if (_launched[item] case final ProcessService service) (item: item, service: service, process: process),
      ];

  /// 앱을 다시 켜기 전에 띄운 프로세스·Compose 항목의 상태를 되살린다(FR-11). 앱 시작 때 한 번 부른다.
  ///
  /// 내가 띄운 중계라고 증명된 프로세스만 되살린다. 살아 있지만 증명할 수 없으면 확인 불가로 두고 멈추지 않는다.
  /// 예외를 던지지 않는다.
  Future<void> recover() => _recovery ??= _recover();

  Future<void> _recover() async {
    for (final r in await store.processes()) {
      if (r.appRunId == store.appRunId) continue;
      switch (await processes.attach(pid: r.pid, startedAt: r.startedAt, jobName: r.jobName)) {
        case Gone():
          unawaited(store.removeProcess(r.item));
        case Unverified():
          _set(r.item, ItemState.unknown, reason: '앱을 다시 켜기 전에 띄운 프로세스인지 확인할 수 없어요.');
        case Attached(:final process):
          await _adopt(r, process);
      }
    }
    await _recoverCompose();
  }

  Future<void> _adopt(ProcessRecord r, RunningProcess process) async {
    final item = r.item;
    final ProcessService service;
    try {
      service = _service(await _project(item.projectId, checkConfig: false), item.serviceId) as ProcessService;
    } on Object {
      // 설정 없이 멈추는 길은 만들지 않는다. 기록은 남겨 두고 확인 불가로만 알린다.
      _set(item, ItemState.unknown, reason: '설정에서 이 항목을 찾을 수 없어 확인할 수 없어요.');
      return;
    }
    _running[item] = process;
    _launched[item] = service;
    _recovered.add(item);
    unawaited(store.putProcess(ProcessRecord(
        item: item,
        pid: r.pid,
        pgid: r.pgid,
        command: r.command,
        startedAt: r.startedAt,
        appRunId: store.appRunId,
        jobName: r.jobName)));
    // 내 자식이 아니라 종료 코드를 받을 수 없으니, 중계가 로그 끝에 남긴 코드를 읽는다.
    unawaited(_allExited(process).then((code) async => _onExit(item, process, code < 0 ? await logs.lastExitCode(item) ?? -1 : code)));
    _set(item, ItemState.running);
    try {
      final ready = switch (service.ready) {
        LogReady() || NoneReady() => const ReadyResult.ready(), // 지난 출력은 다시 볼 수 없다. 떠 있으면 준비됐다고 본다
        final condition => await _readiness.wait(condition, exited: process.exitCode),
      };
      if (ready.ok && identical(_running[item], process) && stateOf(item) == ItemState.running) _set(item, ItemState.ready);
    } on Object {
      // 준비 확인 부품이 아직 없으면 실행 중으로 둔다
    }
  }

  /// `popoling-<프로젝트ID>` 컨테이너가 떠 있는 Compose 항목을 실행 중으로 둔다. Docker 가 꺼져 있으면 건너뛴다.
  Future<void> _recoverCompose() async {
    try {
      for (final project in await projects().listProjects()) {
        for (final s in _services(project).whereType<ComposeService>()) {
          final item = _ref(project, s);
          if (stateOf(item) == ItemState.stopped && await _composeLeftUp(project.id, s)) {
            _launched[item] = s;
            _set(item, ItemState.running);
          }
        }
      }
    } on Object {
      // 앱 시작 때 뒤에서 도니 어떤 이유로든 앱을 멈추면 안 된다. 목록을 못 읽으면 되살리지 않는다
    }
  }

  /// 같은 프로젝트를 실행하는 중에 또 누르면 진행 중인 실행의 결과를 같이 기다린다.
  @override
  Future<RunSummary> runAll(String projectId) {
    if (_runAlls[projectId] case final running?) return running;
    late final Future<RunSummary> run;
    run = _runAll(projectId).whenComplete(() {
      // 전체 종료 뒤 새로 누른 실행이 자리를 차지했으면 그건 지우지 않는다
      if (identical(_runAlls[projectId], run)) _runAlls.remove(projectId);
    });
    return _runAlls[projectId] = run;
  }

  Future<RunSummary> _runAll(String projectId) async {
    final stopAlls = _stopAlls[projectId] ?? 0; // 첫 await 전에 읽어야 그 사이 누른 전체 종료를 놓치지 않는다
    final project = await _project(projectId);
    final startedAt = DateTime.now();
    final pull = project.config?.git.pullBeforeRun ?? false ? await git?.pull(project.folderPath, veto: () => _noPull(projectId, stopAlls)) : null;
    final results = <String, ItemResult>{};
    // shortcut: 의존이 없는 항목도 차례로 띄운다(§6: MVP 는 순차 허용). 느리면 병렬로 바꾼다.
    for (final s in inStartOrder(_services(project))) {
      final failedDep = s.dependsOn.where((d) => results[d] != null && results[d]!.outcome != ItemOutcome.ok);
      results[s.id] = (_stopAlls[projectId] ?? 0) != stopAlls
          ? ItemResult(item: _ref(project, s), outcome: ItemOutcome.skipped, reason: '전체 종료를 눌러서 시작하지 않았어요.')
          : failedDep.isNotEmpty
              ? ItemResult(
                  item: _ref(project, s), outcome: ItemOutcome.skipped, reason: '${failedDep.first} 항목이 실패해서 시작하지 않았어요.')
              : await _up(project, s);
    }
    final summary = RunSummary(
        projectId: projectId, startedAt: startedAt, finishedAt: DateTime.now(), items: [...results.values], pull: pull);
    await store.saveRun(summary);
    if (summary.succeeded) _events.add(RunSucceeded(summary));
    return summary;
  }

  /// 지금 코드를 바꾸면 안 되는 이유. [stopAlls] 는 전체 실행을 시작할 때의 전체 종료 횟수.
  String? _noPull(String projectId, int stopAlls) {
    if ((_stopAlls[projectId] ?? 0) != stopAlls) return '전체 종료를 눌러서 최신 코드를 받지 않았어요.';
    const up = {ItemState.starting, ItemState.running, ItemState.ready, ItemState.stopping};
    final busy = _running.keys.any((i) => i.projectId == projectId) ||
        _starting.keys.any((i) => i.projectId == projectId) ||
        _launched.keys.any((i) => i.projectId == projectId && up.contains(stateOf(i)));
    return busy ? '실행 중인 항목이 있어 최신 코드를 받지 않았어요. 전체 종료 뒤 다시 실행하면 받아요.' : null;
  }

  @override
  Future<RunSummary> stopAll(String projectId) async {
    _stopAlls.update(projectId, (n) => n + 1, ifAbsent: () => 1);
    _runAlls.remove(projectId); // 진행 중인 실행은 남은 항목을 건너뛰고 끝난다. 다음 [전체 실행]은 새로 시작한다
    final startedAt = DateTime.now();
    List<ServiceConfig> current;
    try {
      final project = await _project(projectId, checkConfig: false);
      current = inStartOrder(_services(project)).reversed.where((s) => s is! RemoteService).toList();
    } on ProjectNotFoundException {
      // 실행 중에 목록에서 뺐어도 띄운 것은 멈춰야 고아 프로세스가 남지 않는다
      if (!_launched.keys.any((k) => k.projectId == projectId)) rethrow;
      current = const [];
    }
    final ids = {for (final s in current) s.id};
    // 설정에서 빠졌지만 띄워 둔 항목을 먼저 멈춘다
    final removed = [
      for (final MapEntry(:key, :value) in _launched.entries)
        if (key.projectId == projectId && !ids.contains(key.serviceId)) value,
    ];
    final items = [for (final s in [...removed.reversed, ...current]) await _down(projectId, s)];
    return RunSummary(projectId: projectId, startedAt: startedAt, finishedAt: DateTime.now(), items: items);
  }

  @override
  Future<ItemResult> start(ItemRef item) async {
    final project = await _project(item.projectId);
    return _up(project, _service(project, item.serviceId));
  }

  @override
  Future<ItemResult> stop(ItemRef item) async {
    // 띄운 항목은 프로젝트를 목록에서 뺐어도 멈출 수 있게 프로젝트를 찾지 않는다
    final service = _launched[item] ?? _service(await _project(item.projectId, checkConfig: false), item.serviceId);
    if (service is RemoteService) return ItemResult(item: item, outcome: ItemOutcome.ok);
    return _down(item.projectId, service);
  }

  @override
  Future<RunSummary?> lastRun(String projectId) async {
    await projects().getProject(projectId); // 없으면 ProjectNotFoundException
    return store.lastRun(projectId);
  }

  // ---- 띄우기 ----

  Future<ItemResult> _up(Project project, ServiceConfig service) {
    final item = _ref(project, service);
    if (_ups[item] case final up?) return up;
    late final Future<ItemResult> up;
    up = _upOnce(project, service, item).whenComplete(() {
      if (identical(_ups[item], up)) _ups.remove(item);
    });
    if (service is! RemoteService) {
      _inFlight.add(up);
      unawaited(up.whenComplete(() => _inFlight.remove(up)));
    }
    return _ups[item] = up;
  }

  Future<ItemResult> _upOnce(Project project, ServiceConfig service, ItemRef item) async {
    final state = stateOf(item);
    // 원격 항목(connected)은 그사이 끊겼을 수 있으니 매번 다시 확인한다.
    if (state == ItemState.ready) return ItemResult(item: item, outcome: ItemOutcome.ok);
    if (_stopping.contains(item)) {
      return ItemResult(item: item, outcome: ItemOutcome.failed, reason: '멈추는 중이에요. 다 멈춘 뒤 다시 시작해 주세요.');
    }
    // 띄운 뒤에 알면 부작용(DB 마이그레이션 등)만 남기고 멈추게 되니 먼저 확인한다.
    if (service.ready case LogReady(:final pattern)) {
      try {
        RegExp(pattern);
      } on FormatException {
        return _fail(item, '준비 조건의 정규식이 잘못됐어요: $pattern');
      }
    }
    if (service is! RemoteService) _launched[item] = service;

    final cancel = Completer<void>();
    _starting[item] = cancel; // 첫 await 전에 걸어야 동시에 두 번 들어온 시작을 막는다
    try {
      return await switch (service) {
        RemoteService() => _upRemote(project, service, item),
        ComposeService() => _upCompose(project, service, item, cancel),
        ProcessService() => _upProcess(project, service, item, cancel),
      };
    } catch (e) {
      if (cancel.isCompleted) return _cancelled(item);
      return _fail(item, switch (e) {
        PopolingException(:final message) => message,
        ProcessException(:final message) => '시작하지 못했어요: $message',
        _ => '시작하지 못했어요: $e',
      });
    } finally {
      if (identical(_starting[item], cancel)) _starting.remove(item);
    }
  }

  Future<ItemResult> _upRemote(Project project, RemoteService service, ItemRef item) async {
    String? reason;
    try {
      final status = await launcher().start(project.id, service);
      if (status is RemoteStatus && status.connected) {
        _set(item, ItemState.connected);
        return ItemResult(item: item, outcome: ItemOutcome.ok);
      }
      reason = status is RemoteStatus ? status.probe.failureReason : null;
    } on PopolingException catch (e) {
      reason = e.message;
    }
    reason = '연결할 수 없어요${reason == null ? '' : ': $reason'}.';
    _set(item, ItemState.disconnected, reason: reason);
    return ItemResult(item: item, outcome: ItemOutcome.failed, reason: reason);
  }

  Future<ItemResult> _upCompose(Project project, ComposeService service, ItemRef item, Completer<void> cancel) async {
    final readiness = _readiness; // 띄우기 전에 꺼내야 구현이 없을 때 컨테이너를 남기지 않는다
    _set(item, ItemState.starting);
    await launcher().start(project.id, service);
    if (cancel.isCompleted) {
      // up 이 멈추기보다 늦게 끝났으면 컨테이너가 떠 있다. 그사이 새로 시작했으면 그 시작의 컨테이너라 두고 간다.
      final halted = stateOf(item) == ItemState.stopped || stateOf(item) == ItemState.stopping;
      if (halted && !_starting.containsKey(item)) await launcher().stop(project.id, service);
      return _cancelled(item);
    }

    _set(item, ItemState.running);
    final r = await readiness.wait(
      service.ready,
      lines: service.ready is LogReady ? launcher().logs(project.id, service) : null,
      composeHealthy: () async {
        final status = await launcher().status(project.id, service);
        return status is ComposeStatus && status.healthy;
      },
      cancelled: cancel.future,
    );
    if (cancel.isCompleted) return _cancelled(item);
    if (!r.ok) return _fail(item, r.reason!);
    _set(item, ItemState.ready);
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  Future<ItemResult> _upProcess(Project project, ProcessService service, ItemRef item, Completer<void> cancel) async {
    // 준비 시간을 넘겨 실패했지만 아직 살아 있는 이전 실행은 내가 띄운 것이니 먼저 멈춘다.
    // 포트 확인보다 먼저 해야 내 프로세스가 잡은 포트를 "다른 프로그램"으로 잘못 알리지 않는다.
    if (_running.containsKey(item)) {
      final halted = await _halt(project.id, service, item);
      if (halted.outcome != ItemOutcome.ok) return halted;
      if (cancel.isCompleted) return _cancelled(item);
    }

    final busy = await _busyPort(service);
    if (cancel.isCompleted) return _cancelled(item);
    if (busy != null) {
      _set(item, ItemState.portBusy, reason: busy);
      return ItemResult(item: item, outcome: ItemOutcome.failed, reason: busy);
    }

    final cwd = _inside(project.folderPath, service.cwd);
    if (cwd == null) return _fail(item, '작업 폴더를 찾을 수 없거나 프로젝트 폴더 밖이에요: ${service.cwd}');

    final env = <String, String>{};
    final secrets = <String>[]; // 로그에서 가릴 값은 .env 에서 읽은 것만(env 는 설정 파일 값이라 비밀이 아니다)
    if (service.envFile case final envFile?) {
      final path = _inside(project.folderPath, envFile);
      try {
        if (path == null) throw const FileSystemException();
        final fromFile = readEnvFile(path);
        env.addAll(fromFile);
        secrets.addAll(fromFile.values);
      } on FileSystemException {
        return _fail(item, '.env 파일을 읽을 수 없거나 프로젝트 폴더 밖이에요: $envFile');
      }
    }
    env.addAll(service.env);

    final readiness = _readiness; // 띄우기 전에 꺼내야 구현이 없을 때 프로세스를 남기지 않는다
    _set(item, ItemState.starting);
    final log = LogTarget(await logs.fileOf(item), secrets: secrets, maxBytes: logs.maxBytes, keep: logs.keep);
    final process = await processes.start(service.command, workingDirectory: cwd, environment: env, log: log);
    if (cancel.isCompleted) {
      await process.stop(service.stopTimeout); // 띄우는 사이에 멈추라고 했다
      return _cancelled(item);
    }
    _running[item] = process;
    unawaited(store.putProcess(ProcessRecord(
        item: item,
        pid: process.pid,
        pgid: process.pgid,
        command: service.command,
        startedAt: process.startedAt,
        appRunId: store.appRunId,
        jobName: process.jobName)));
    _exitCodes.remove(item);
    final exited = _allExited(process);
    unawaited(exited.then((code) => _onExit(item, process, code))); // 준비 확인보다 먼저 걸어야 실패에 종료 코드가 붙는다

    // 준비 확인이 첫 줄부터 보도록, 출력을 받기 시작하는 지금 바로 구독한다(사이에 await 를 두지 않는다).
    final lines = StreamController<String>.broadcast();
    process.output.listen((l) => lines.add(l.text), onDone: lines.close);
    final Future<ReadyResult> ready;
    try {
      ready = readiness.wait(service.ready, lines: lines.stream, exited: exited, cancelled: cancel.future);
    } catch (_) {
      // 준비 조건이 잘못됐으면(정규식 오류 등) 띄운 프로세스를 남기지 않는다.
      _running.remove(item);
      await process.stop(service.stopTimeout);
      unawaited(store.removeProcess(item));
      rethrow;
    }
    _set(item, ItemState.running);

    final r = await ready;
    if (cancel.isCompleted) return _cancelled(item);
    if (!r.ok) return _fail(item, r.reason!, exitCode: _exitCodes[item]); // 준비 시간 초과여도 자동 종료하지 않는다(§6)
    _set(item, ItemState.ready);
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  /// 띄운 명령과 그 자식이 모두 끝났다. 값은 띄운 명령의 종료 코드.
  /// 서버를 띄우고 먼저 끝나는 스크립트도 자식이 남아 있는 동안은 끝난 게 아니다.
  // shortcut: 리더가 끝난 뒤 1초마다 그룹을 확인한다. 그룹이 빈 뒤 1초 안에 같은 번호가 재사용되면 놓친다(PID 한 바퀴가 1초 안에 돌 때만).
  static Future<int> _allExited(RunningProcess process) async {
    final code = await process.exitCode;
    while (await process.groupAlive) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return code;
  }

  /// 띄운 프로세스가 자식까지 스스로 끝났다. 준비 전 종료는 [_upProcess] 가, 멈추기는 [_halt] 가 상태를 바꾼다.
  void _onExit(ItemRef item, RunningProcess process, int code) {
    if (!identical(_running[item], process)) return;
    _exitCodes[item] = code;
    _running.remove(item);
    unawaited(store.removeProcess(item));
    final recovered = _recovered.remove(item);
    if (_stopping.contains(item) || (stateOf(item) != ItemState.ready && !recovered)) return;
    _set(item, code == 0 ? ItemState.stopped : ItemState.failed,
        reason: switch (code) {
          0 => null,
          -1 => '앱을 다시 켠 뒤 종료됐어요.',
          _ => '실행 중에 종료됐어요 (종료 코드 $code).',
        },
        exitCode: code == -1 ? null : code);
  }

  /// 항목이 쓸 포트를 다른 프로그램이 쓰고 있으면 그 이유. 확인할 수 없으면 null(시작은 막지 않는다).
  /// 내가 띄운 다른 항목이 쓰고 있으면 그 항목을 알려 준다(AT-17).
  Future<String?> _busyPort(ProcessService service) async {
    for (final port in service.ports) {
      try {
        if (await ports().whoUses(port) case final PortInUse usage) {
          if (await runtime().ownerOf(usage) case final owner?) return '포트 $port 를 $owner 항목이 쓰고 있어요.';
          final PortInUse(:processName, :pid) = usage;
          final who = processName == null ? '' : '($processName${pid == null ? '' : ', PID $pid'})';
          return '포트 $port 를 다른 프로그램$who이 쓰고 있어요.';
        }
      } on Object catch (e) {
        if (e is! Exception && e is! UnimplementedError) rethrow;
        continue; // shortcut: whoUses 가 아직 없는 OS 에서는 건너뛴다. C 의 진짜 구현이 들어오면 지운다.
      }
    }
    return null;
  }

  // ---- 멈추기 ----

  /// 사용자가 멈췄다. 진행 중인 시작이 있으면 끊고 멈춘다.
  Future<ItemResult> _down(String projectId, ServiceConfig service) async {
    final item = ItemRef(projectId: projectId, serviceId: service.id);
    _ups.remove(item); // 끊긴 시작을 다음 시작이 같이 기다리지 않게
    _starting.remove(item)?.complete();
    if (_stopping.contains(item)) {
      return ItemResult(item: item, outcome: ItemOutcome.failed, reason: '이미 멈추는 중이에요.');
    }
    final r = await _halt(projectId, service, item);
    if (r.outcome == ItemOutcome.ok) _launched.remove(item); // 다 멈췄으니 더 멈출 게 없다
    return r;
  }

  Future<ItemResult> _halt(String projectId, ServiceConfig service, ItemRef item) async {
    if (stateOf(item) == ItemState.unknown) {
      return ItemResult(item: item, outcome: ItemOutcome.failed, reason: '포폴링이 띄운 것인지 확인할 수 없어 멈추지 않았어요.');
    }
    if (stateOf(item) == ItemState.stopped && !_running.containsKey(item) && !await _composeLeftUp(projectId, service)) {
      return ItemResult(item: item, outcome: ItemOutcome.ok);
    }
    _stopping.add(item);
    _set(item, ItemState.stopping);
    final process = _running.remove(item);
    _recovered.remove(item);
    try {
      var forced = false;
      if (service is ComposeService) {
        await launcher().stop(projectId, service);
      } else if (process != null) {
        forced = (await process.stop((service as ProcessService).stopTimeout)).forced;
        unawaited(store.removeProcess(item));
      }
      _set(item, ItemState.stopped);
      return ItemResult(item: item, outcome: ItemOutcome.ok, forced: forced);
    } catch (e) {
      if (process != null) _running[item] ??= process; // 다시 멈출 수 있게 핸들을 되돌린다
      return _fail(item, e is PopolingException ? e.message : '멈추지 못했어요: $e');
    } finally {
      _stopping.remove(item);
    }
  }

  /// 상태는 멈춤인데 `popoling-<프로젝트ID>` 컨테이너가 남아 있다(앱을 다시 켜기 전에 띄운 것).
  /// 확인할 수 없으면(Docker 꺼짐 등) 남은 게 없다고 본다.
  Future<bool> _composeLeftUp(String projectId, ServiceConfig service) async {
    if (service is! ComposeService) return false;
    try {
      final status = await launcher().status(projectId, service);
      return status is ComposeStatus && status.containers.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  // ---- 앱 종료 (FR-12) ----

  /// 지금 떠 있거나 시작하는 중인, 내가 멈출 수 있는 항목. 실패했지만 살아 있는 것도 들어 있다.
  Future<List<ItemRef>> stillUp() async {
    await _recovery?.timeout(const Duration(seconds: 3), onTimeout: () {}); // 앱을 켜자마자 닫을 때
    final up = <ItemRef>[];
    for (final MapEntry(key: item, value: service) in [..._launched.entries]) {
      final alive = switch (stateOf(item)) {
        ItemState.starting || ItemState.running || ItemState.ready || ItemState.stopping => true,
        ItemState.failed when service is ComposeService =>
          await _composeLeftUp(item.projectId, service).timeout(const Duration(seconds: 3), onTimeout: () => true),
        _ => false,
      };
      if (alive || _running.containsKey(item) || _starting.containsKey(item)) up.add(item);
    }
    return up;
  }

  /// 떠 있는 항목이 있는 프로젝트를 모두 전체 종료하고, 멈추지 못한 항목만 돌려준다.
  /// 시작하다 끊긴 것이 뒤늦게 뜨면 그 정리까지 기다린다. 먼저 앱이 꺼지면 기록 없는 프로세스가 남는다.
  Future<List<ItemResult>> stopEverything() async {
    while (_stopping.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final failed = <ItemResult>[];
    final up = await stillUp();
    await Future.wait([
      for (final id in {for (final i in up) i.projectId})
        stopAll(id).then(
          (s) => failed.addAll(s.items.where((r) => r.outcome == ItemOutcome.failed && stateOf(r.item) != ItemState.unknown)),
          onError: (Object e) => failed.addAll([
            for (final i in up)
              if (i.projectId == id)
                ItemResult(
                    item: i, outcome: ItemOutcome.failed, reason: e is PopolingException ? e.message : '멈추지 못했어요: $e'),
          ]),
        ),
    ]);
    await Future.wait([..._inFlight]);
    await store.flush(); // 지운 기록이 남으면 다음에 '확인 불가'로 보일 수 있다
    return failed;
  }

  // ---- 도우미 ----

  /// 시작하는 중에 멈췄다. 상태는 멈추기가 정했으니 건드리지 않는다.
  static ItemResult _cancelled(ItemRef item) =>
      ItemResult(item: item, outcome: ItemOutcome.failed, reason: '시작하는 중에 멈췄어요.');

  ItemResult _fail(ItemRef item, String reason, {int? exitCode}) {
    _set(item, ItemState.failed, reason: reason, exitCode: exitCode);
    return ItemResult(item: item, outcome: ItemOutcome.failed, reason: reason, exitCode: exitCode);
  }

  void _set(ItemRef item, ItemState state, {String? reason, int? exitCode}) {
    _states[item] = state;
    _events.add(ItemStateChanged(item, state, reason: reason, exitCode: exitCode));
  }

  /// 멈출 때는 설정이 깨져 있어도 띄운 것을 멈출 수 있게 [checkConfig] 를 끈다.
  Future<Project> _project(String projectId, {bool checkConfig = true}) async {
    final project = await projects().getProject(projectId); // 없으면 ProjectNotFoundException
    if (checkConfig && project.configIssues.isNotEmpty) throw ConfigFormatException(project.configIssues);
    return project;
  }

  static List<ServiceConfig> _services(Project project) => project.config?.services ?? const [];

  static ServiceConfig _service(Project project, String serviceId) => _services(project).firstWhere(
        (s) => s.id == serviceId,
        orElse: () => throw ArgumentError.value(serviceId, 'serviceId', '프로젝트에 없는 항목'),
      );

  static ItemRef _ref(Project project, ServiceConfig service) =>
      ItemRef(projectId: project.id, serviceId: service.id);

  /// 프로젝트 폴더 안의 [relative] 실제 경로. 없거나 폴더 밖(`..`·링크로 빠져나감)이면 null.
  static String? _inside(String folder, String relative) {
    try {
      final root = Directory(folder).resolveSymbolicLinksSync();
      final path = File('$root${Platform.pathSeparator}$relative').resolveSymbolicLinksSync();
      return path == root || path.startsWith('$root${Platform.pathSeparator}') ? path : null;
    } on FileSystemException {
      return null;
    }
  }
}

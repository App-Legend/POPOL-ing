@TestOn('!windows')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/testing.dart';
import 'package:ppoling_relay/log_file.dart';
import 'package:ppoling_runner/src/log/log_store.dart';
import 'package:ppoling_runner/src/orchestrator/runner_orchestrator.dart';
import 'package:ppoling_runner/src/process/posix_process_launcher.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';
import 'package:ppoling_runner/src/runtime/runtime_store.dart';

import 'support/relay_binary.dart';

const _s5 = Duration(seconds: 5);
const _ms300 = Duration(milliseconds: 300);

/// 명령줄이 정확히 [command] 인 프로세스 수.
Future<int> count(String command) async {
  final r = await Process.run('ps', ['-A', '-o', 'command=']);
  return (r.stdout as String).split('\n').where((l) => l.trim() == command).length;
}

/// whoUses 가 불릴 때의 항목 상태를 적어 둔다.
class _RecordingPortProbe extends FakePortProbe {
  _RecordingPortProbe(this.state);

  final ItemState Function() state;
  final seen = <ItemState>[];

  @override
  Future<PortUsage> whoUses(int port) async {
    seen.add(state());
    return super.whoUses(port);
  }
}

/// [whoUses] 가 아직 없는 OS(checks 의 SystemPortProbe 와 같다).
class _NoWhoUsesPortProbe extends FakePortProbe {
  @override
  Future<PortUsage> whoUses(int port) async => throw UnimplementedError();
}

/// 멈추기가 예상 못 한 예외를 던진다.
class _BrokenStopLauncher extends FakeItemLauncher {
  _BrokenStopLauncher(super.projects);

  @override
  Future<void> stop(String projectId, ServiceConfig service) async => throw StateError('docker 응답 없음');
}

/// `up -d` 가 늦게 끝난다. 시작·멈춤이 끝난 순서를 적어 둔다.
class _SlowStartLauncher extends FakeItemLauncher {
  _SlowStartLauncher(super.projects);

  final calls = <String>[];

  @override
  Future<LaunchStatus> start(String projectId, ServiceConfig service) async {
    await Future<void>.delayed(_ms300);
    calls.add('start');
    return super.start(projectId, service);
  }

  @override
  Future<void> stop(String projectId, ServiceConfig service) async {
    calls.add('stop');
    return super.stop(projectId, service);
  }
}

/// 테스트마다 새 프로젝트 폴더. 테스트가 끝나면 지운다.
String tempProject() {
  final dir = Directory.systemTemp.createTempSync('ppoling_project_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.resolveSymbolicLinksSync();
}

/// db(Compose) → api(프로세스) → web(프로세스), 그리고 원격 storage.
Project demo(String folder, {String api = 'echo "Started api"; exec sleep 30', List<ProcessService> extra = const []}) =>
    Project(
      id: 'demo',
      name: 'demo',
      folderPath: folder,
      registeredAt: DateTime(2026, 11, 17),
      config: ProjectConfig(services: [
        const ComposeService(id: 'db', file: './docker-compose.yml', ready: ComposeHealthyReady(timeout: _s5)),
        ProcessService(id: 'api', command: ['sh', '-c', api], dependsOn: const ['db'], ready: const LogReady(pattern: 'Started', timeout: _s5)),
        const ProcessService(
            id: 'web', command: ['sh', '-c', 'echo ready; exec sleep 30'], dependsOn: ['api'], ready: LogReady(pattern: 'ready', timeout: _s5)),
        const RemoteService(id: 'storage', ready: HttpReady(url: 'https://storage.example/health')),
        ...extra,
      ]),
    );

/// 테스트마다 새 로그 폴더. 테스트가 끝나면 지운다.
LogStore tempLogs() {
  final dir = Directory.systemTemp.createTempSync('ppoling_logs_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return LogStore(() async => dir);
}

/// 테스트마다 새 실행 기록 파일. 테스트가 끝나면 지운다.
RuntimeStore tempStore() {
  final dir = Directory.systemTemp.createTempSync('ppoling_runtime_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return RuntimeStore(() async => File('${dir.path}/runtime.json'));
}

RunnerOrchestrator orchestrator(Project project,
    {PortProbe? ports,
    ItemLauncher Function(ProjectRepository)? launcher,
    LogStore? logs,
    RuntimeStore? store,
    RuntimeQuery? runtime,
    ProcessLauncher? processes}) {
  final repo = FakeProjectRepository(projects: [project]);
  final launcher0 = launcher?.call(repo) ?? FakeItemLauncher(repo, reachable: {'storage'});
  final ports0 = ports ?? FakePortProbe();
  final http = FakeHttpProbe();
  final runtime0 = runtime ?? FakeRuntimeQuery();
  return RunnerOrchestrator(
    projects: () => repo,
    launcher: () => launcher0,
    ports: () => ports0,
    http: () => http,
    runtime: () => runtime0,
    processes: processes ?? PosixProcessLauncher(relay: relay, searchPath: () async => '/usr/bin:/bin'),
    logs: logs ?? tempLogs(),
    store: store ?? tempStore(),
  );
}

/// 테스트용 중계 실행 파일. [main] 의 setUpAll 에서 채운다.
late String relay;

void main() {
  setUpAll(() async => relay = await relayBinary());
  group('약속 테스트', () {
    orchestratorContract(() async {
      final folder = tempProject();
      final project = demo(folder);
      return OrchestratorFixture(
        orchestrator: orchestrator(project),
        failingOrchestrator: orchestrator(demo(folder, api: 'echo boom >&2; exit 1')),
        projectId: project.id,
        services: project.config!.services,
        failingServiceId: 'api',
      );
    });
  });

  test('실행 중에 전체 실행을 또 누르면 같은 실행의 결과를 함께 기다린다', () async {
    final o = orchestrator(demo(tempProject()));
    addTearDown(() => o.stopAll('demo'));
    final first = o.runAll('demo');
    final second = o.runAll('demo');
    expect(await second, same(await first));
    expect(await o.runAll('demo'), isNot(same(await first)), reason: '끝난 뒤에는 새로 실행한다');
  });

  test('전체 실행 중에 전체 종료하면 아직 띄우지 않은 항목은 띄우지 않는다', () async {
    final o = orchestrator(Project(
      id: 'demo',
      name: 'demo',
      folderPath: tempProject(),
      registeredAt: DateTime(2026, 11, 17),
      config: const ProjectConfig(services: [
        ProcessService(id: 'a', command: ['sleep', '37'], ready: LogReady(pattern: 'never', timeout: _s5)),
        ProcessService(id: 'b', command: ['sleep', '38']),
      ]),
    ));
    addTearDown(() => o.stopAll('demo'));
    final running = o.runAll('demo');
    await Future<void>.delayed(_ms300);
    await o.stopAll('demo');
    final summary = await running;

    expect(summary.items.firstWhere((r) => r.item.serviceId == 'b').outcome, ItemOutcome.skipped);
    expect(await count('sleep 37'), 0);
    expect(await count('sleep 38'), 0);
  });

  test('Compose 를 띄우는 중에 멈추면 up 이 늦게 끝나도 다시 내린다', () async {
    late _SlowStartLauncher launcher;
    final o = orchestrator(demo(tempProject()), launcher: (repo) => launcher = _SlowStartLauncher(repo));
    const db = ItemRef(projectId: 'demo', serviceId: 'db');
    final starting = o.start(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await o.stop(db);
    expect((await starting).reason, contains('멈췄어요'));
    expect(launcher.calls.last, 'stop');
  });

  test('전체 종료 직후 다시 전체 실행하면 이전 실행을 돌려주지 않고 새로 띄운다', () async {
    final o = orchestrator(Project(
      id: 'demo',
      name: 'demo',
      folderPath: tempProject(),
      registeredAt: DateTime(2026, 11, 17),
      config: const ProjectConfig(services: [
        ProcessService(
            id: 'a', command: ['sh', '-c', 'sleep 0.5; echo ok; exec sleep 41'], ready: LogReady(pattern: 'ok', timeout: _s5)),
      ]),
    ));
    addTearDown(() => o.stopAll('demo'));
    final first = o.runAll('demo');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await o.stopAll('demo');
    final second = o.runAll('demo');
    expect(second, isNot(same(first)));
    expect((await second).succeeded, isTrue);
    await first;
  });

  test('Compose 를 시작·멈춤·시작으로 빠르게 누르면 늦게 끝난 첫 시작이 새 컨테이너를 내리지 않는다', () async {
    late _SlowStartLauncher launcher;
    final o = orchestrator(demo(tempProject()), launcher: (repo) => launcher = _SlowStartLauncher(repo));
    const db = ItemRef(projectId: 'demo', serviceId: 'db');
    addTearDown(() => o.stop(db));
    final first = o.start(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await o.stop(db);
    final second = o.start(db);
    await first;
    expect((await second).outcome, ItemOutcome.ok);
    expect(launcher.calls, ['stop', 'start', 'start']);
  });

  test('앱을 다시 켠 뒤에도 전에 띄운 Compose 항목을 멈춘다', () async {
    final project = demo(tempProject());
    FakeItemLauncher? shared;
    ItemLauncher launcher(ProjectRepository repo) => shared ??= FakeItemLauncher(repo, reachable: {'storage'});
    const db = ItemRef(projectId: 'demo', serviceId: 'db');
    expect((await orchestrator(project, launcher: launcher).start(db)).outcome, ItemOutcome.ok);

    await orchestrator(project, launcher: launcher).stopAll('demo'); // 새로 켠 앱: 상태를 모른다
    final status = await shared!.status('demo', project.config!.services.first) as ComposeStatus;
    expect(status.containers, isEmpty);
  });

  test('연결됐던 원격 항목도 다시 시작하면 연결을 다시 확인한다', () async {
    late FakeItemLauncher launcher;
    final o = orchestrator(demo(tempProject()),
        launcher: (repo) => launcher = FakeItemLauncher(repo, reachable: {'storage'}));
    const storage = ItemRef(projectId: 'demo', serviceId: 'storage');
    expect((await o.start(storage)).outcome, ItemOutcome.ok);
    launcher.reachable.remove('storage');
    expect((await o.start(storage)).outcome, ItemOutcome.failed);
    expect(o.stateOf(storage), ItemState.disconnected);
  });

  test('띄운 뒤 설정에서 항목이 빠져도 멈출 수 있다', () async {
    late ProjectRepository repo;
    final project = demo(tempProject(), extra: [const ProcessService(id: 'x', command: ['sleep', '42'])]);
    final o = orchestrator(project, launcher: (r) => FakeItemLauncher(repo = r, reachable: {'storage'}));
    const x = ItemRef(projectId: 'demo', serviceId: 'x');
    expect((await o.start(x)).outcome, ItemOutcome.ok);

    await repo.updateProject(project.copyWith(config: const ProjectConfig(services: [])));
    expect((await o.stop(x)).outcome, ItemOutcome.ok);
    expect(await count('sleep 42'), 0);
  });

  group('프로세스 항목', () {
    Future<(RunnerOrchestrator, ItemRef)> setUpItem(ProcessService service, {PortProbe? ports, RuntimeQuery? runtime}) async {
      final o = orchestrator(demo(tempProject(), extra: [service]), ports: ports, runtime: runtime);
      final item = ItemRef(projectId: 'demo', serviceId: service.id);
      addTearDown(() => o.stop(item));
      return (o, item);
    }

    test('쓸 포트를 다른 프로그램이 쓰고 있으면 시작하지 않고 포트 사용 중', () async {
      final (o, item) = await setUpItem(
        const ProcessService(id: 'x', command: ['sleep', '30'], ports: [8080]),
        ports: FakePortProbe(inUse: [const PortInUse(8080, pid: 99, processName: 'java')]),
      );
      final r = await o.start(item);
      expect(r.outcome, ItemOutcome.failed);
      expect(r.reason, allOf(contains('8080'), contains('java')));
      expect(o.stateOf(item), ItemState.portBusy);
    });

    test('쓸 포트를 내가 띄운 다른 프로젝트 항목이 쓰고 있으면 그 항목을 알린다 (AT-17)', () async {
      const owner = ItemRef(projectId: 'shop-clone', serviceId: 'web');
      final (o, item) = await setUpItem(
        const ProcessService(id: 'x', command: ['sleep', '30'], ports: [5173]),
        ports: FakePortProbe(inUse: [const PortInUse(5173, pid: 4321, processName: 'node')]),
        runtime: FakeRuntimeQuery(owned: [(port: 5173, pid: 4321, item: owner)]),
      );
      final r = await o.start(item);
      expect(r.outcome, ItemOutcome.failed);
      expect(r.reason, '포트 5173 를 shop-clone / web 항목이 쓰고 있어요.');
      expect(o.stateOf(item), ItemState.portBusy);
    });

    test('포트를 쓰는 프로그램을 아직 찾을 수 없는 OS 면 포트 확인을 건너뛰고 시작한다', () async {
      final (o, item) = await setUpItem(
        const ProcessService(id: 'x', command: ['sleep', '34'], ports: [8080]),
        ports: _NoWhoUsesPortProbe(),
      );
      expect((await o.start(item)).outcome, ItemOutcome.ok);
    });

    test('실행 중에 프로젝트를 목록에서 빼도 띄운 프로세스를 멈출 수 있다', () async {
      final o = orchestrator(demo(tempProject(), extra: [const ProcessService(id: 'x', command: ['sleep', '35'])]));
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      addTearDown(() => o.stop(item).catchError((_) => ItemResult(item: item, outcome: ItemOutcome.ok)));
      expect((await o.start(item)).outcome, ItemOutcome.ok);
      await (o.projects() as FakeProjectRepository).removeProject('demo');

      final summary = await o.stopAll('demo');
      expect(summary.items.single.outcome, ItemOutcome.ok);
      expect(await count('sleep 35'), 0);
      await expectLater(o.stopAll('demo'), throwsA(isA<ProjectNotFoundException>()), reason: '띄운 게 없으면 약속대로 예외');
    });

    test('작업 폴더가 프로젝트 폴더 밖이면 시작하지 않는다', () async {
      final (o, item) = await setUpItem(const ProcessService(id: 'x', command: ['sleep', '30'], cwd: '..'));
      final r = await o.start(item);
      expect(r.outcome, ItemOutcome.failed);
      expect(r.reason, contains('프로젝트 폴더 밖'));
    });

    test('.env 값과 env 를 넘기고, env 가 .env 를 덮어쓴다', () async {
      final folder = tempProject();
      File('$folder/.env').writeAsStringSync('# 주석\nSECRET="from-file"\nMODE=file\n');
      final o = orchestrator(demo(folder, extra: [
        const ProcessService(
          id: 'x',
          command: ['sh', '-c', r'echo "$SECRET $MODE"; exec sleep 30'],
          envFile: '.env',
          env: {'MODE': 'yaml'},
          // 앱은 중계가 가린 줄을 받는다. SECRET 이 .env 값(from-file)이라 가려지고, MODE 는 env 가 덮어썼다.
          ready: LogReady(pattern: r'^\*\*\*\* yaml$', timeout: _s5),
        ),
      ]));
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      addTearDown(() => o.stop(item));
      expect((await o.start(item)).outcome, ItemOutcome.ok);
    });

    test('실행한 항목의 출력을 .env 값을 가려 로그 파일에 남긴다', () async {
      final folder = tempProject();
      File('$folder/.env').writeAsStringSync('SECRET=hunter2\n');
      final logs = tempLogs();
      final o = orchestrator(
          demo(folder, extra: [
            const ProcessService(
              id: 'x',
              command: ['sh', '-c', r'echo "pw=$SECRET"; echo oops >&2; echo Started; exec sleep 30'],
              envFile: '.env',
              ready: LogReady(pattern: 'Started', timeout: _s5),
            ),
          ]),
          logs: logs);
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      expect((await o.start(item)).outcome, ItemOutcome.ok);
      await o.stop(item);
      final file = await logs.fileOf(item);
      var text = '';
      for (var i = 0; i < 50 && !text.contains('out | Started'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        text = file.existsSync() ? file.readAsStringSync() : '';
      }
      expect(text, contains('out | pw=****'));
      expect(text, contains('err | oops'));
      expect(text, contains('out | Started'));
      expect(text, isNot(contains('hunter2')));
    });

    test('로그 폴더를 쓸 수 없어도 항목은 시작된다', () async {
      final blocker = File('${tempProject()}/not_a_dir')..writeAsStringSync('x');
      final o = orchestrator(
          demo(tempProject(), extra: [const ProcessService(id: 'x', command: ['sleep', '36'])]),
          logs: LogStore(() async => Directory(blocker.path)));
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      addTearDown(() => o.stop(item));
      expect((await o.start(item)).outcome, ItemOutcome.ok);
    });

    test('준비 완료 뒤 스스로 비정상 종료하면 실패와 종료 코드를 알린다', () async {
      final (o, item) = await setUpItem(
          const ProcessService(id: 'x', command: ['sh', '-c', 'echo ready; sleep 0.3; exit 2'], ready: LogReady(pattern: 'ready')));
      final failed = o.events.firstWhere((e) => e is ItemStateChanged && e.item == item && e.state == ItemState.failed);
      expect((await o.start(item)).outcome, ItemOutcome.ok);
      expect(((await failed) as ItemStateChanged).exitCode, 2);
    });

    test('준비 시간을 넘기면 실패지만 프로세스는 남겨 두고, 멈추면 그룹째 멈춘다', () async {
      final (o, item) = await setUpItem(const ProcessService(
          id: 'x', command: ['sh', '-c', 'sleep 30'], ready: LogReady(pattern: 'never', timeout: Duration(milliseconds: 300))));
      final r = await o.start(item);
      expect(r.outcome, ItemOutcome.failed);
      expect(r.reason, contains('준비 시간'));

      final stopped = await o.stop(item);
      expect(stopped.outcome, ItemOutcome.ok);
      expect(o.stateOf(item), ItemState.stopped);
    });

    test('같은 항목을 동시에 두 번 시작해도 프로세스는 하나만 띄운다', () async {
      final (o, item) = await setUpItem(const ProcessService(
          id: 'x', command: ['sh', '-c', 'echo ready; exec sleep 31'], ports: [4321], ready: LogReady(pattern: 'ready', timeout: _s5)));
      final results = await Future.wait([o.start(item), o.start(item)]);
      expect(results.map((r) => r.outcome), [ItemOutcome.ok, ItemOutcome.ok], reason: '두 번째는 진행 중인 시작을 같이 기다린다');
      expect(await count('sleep 31'), 1);
      await o.stop(item);
      expect(await count('sleep 31'), 0);
    });

    test('준비 시간을 넘긴 실행을 다시 시작하면 이전 실행을 먼저 멈춘 뒤 포트를 확인한다', () async {
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      late RunnerOrchestrator o;
      final probe = _RecordingPortProbe(() => o.stateOf(item));
      o = orchestrator(
          demo(tempProject(), extra: [
            const ProcessService(id: 'x', command: ['sleep', '33'], ports: [3000], ready: LogReady(pattern: 'never', timeout: _ms300)),
          ]),
          ports: probe);
      addTearDown(() => o.stop(item));

      expect((await o.start(item)).outcome, ItemOutcome.failed);
      expect(await count('sleep 33'), 1, reason: '준비 시간을 넘겨도 자동으로 멈추지 않는다');
      expect((await o.start(item)).reason, contains('준비 시간'), reason: '포트 사용 중으로 막히지 않는다');
      expect(probe.seen, [ItemState.stopped, ItemState.stopped]);
      expect(await count('sleep 33'), 1, reason: '이전 실행은 멈추고 새로 하나만 남는다');
    });

    test('준비를 기다리는 중에 멈추면 멈춤으로 끝나고 실패로 덮어쓰지 않는다', () async {
      final (o, item) =
          await setUpItem(const ProcessService(id: 'x', command: ['sleep', '34'], ready: LogReady(pattern: 'never', timeout: _s5)));
      final states = <ItemState>[];
      o.events.listen((e) {
        if (e is ItemStateChanged && e.item == item) states.add(e.state);
      });

      final starting = o.start(item);
      await Future<void>.delayed(_ms300);
      expect((await o.stop(item)).outcome, ItemOutcome.ok);
      final r = await starting;
      await Future<void>.delayed(_ms300);

      expect(r.reason, contains('멈췄어요'));
      expect(o.stateOf(item), ItemState.stopped);
      expect(states, isNot(contains(ItemState.failed)));
      expect(await count('sleep 34'), 0);
    });

    test('준비 조건이 잘못돼 확인할 수 없으면 실패하고 띄운 프로세스를 남기지 않는다', () async {
      final (o, item) = await setUpItem(const ProcessService(id: 'x', command: ['sleep', '40'], ready: LogReady(pattern: '(')));
      final r = await o.start(item);
      expect(r.outcome, ItemOutcome.failed);
      expect(r.reason, contains('정규식'));
      expect(await count('sleep 40'), 0);
    });

    test('띄운 명령이 서버를 남기고 먼저 끝나도 포트가 열리면 준비 완료', () async {
      final ports = FakePortProbe();
      final (o, item) = await setUpItem(
          const ProcessService(
              id: 'x',
              command: ['sh', '-c', 'sleep 39 & exit 0'],
              ready: PortReady(port: 5999, timeout: _s5, interval: Duration(milliseconds: 50))),
          ports: ports);
      Timer(const Duration(milliseconds: 1500), () => ports.inUse[5999] = const PortInUse(5999));
      expect((await o.start(item)).outcome, ItemOutcome.ok);
    });

    test('띄운 명령이 자식을 남기고 먼저 끝나도 멈추면 자식까지 멈춘다', () async {
      final (o, item) = await setUpItem(const ProcessService(id: 'x', command: ['sh', '-c', 'sleep 35 & exit 0']));
      expect((await o.start(item)).outcome, ItemOutcome.ok);
      await Future<void>.delayed(_ms300);
      expect(await count('sleep 35'), 1);

      expect((await o.stop(item)).outcome, ItemOutcome.ok);
      expect(await count('sleep 35'), 0);
    });
  });

  test('멈추다 예상 못 한 예외가 나도 결과로 알리고 종료 중에 머물지 않는다', () async {
    final o = orchestrator(demo(tempProject()), launcher: _BrokenStopLauncher.new);
    const db = ItemRef(projectId: 'demo', serviceId: 'db');
    expect((await o.start(db)).outcome, ItemOutcome.ok);

    final r = await o.stop(db);
    expect(r.outcome, ItemOutcome.failed);
    expect(r.reason, contains('멈추지 못했어요'));
    expect(o.stateOf(db), ItemState.failed);
  });

  group('실행 기록', () {
    test('마지막 전체 실행 결과는 앱을 다시 켜도 남는다', () async {
      final dir = Directory.systemTemp.createTempSync('ppoling_runtime_');
      addTearDown(() => dir.deleteSync(recursive: true));
      RuntimeStore store() => RuntimeStore(() async => File('${dir.path}/runtime.json'));
      final project = demo(tempProject());
      final o = orchestrator(project, store: store());
      addTearDown(() => o.stopAll('demo'));
      final summary = await o.runAll('demo');

      final again = await orchestrator(project, store: store()).lastRun('demo');
      expect(again!.startedAt, summary.startedAt);
      expect(again.items.map((r) => (r.item, r.outcome)), summary.items.map((r) => (r.item, r.outcome)));
    });

    test('띄운 프로세스를 기록하고, 멈추면 기록에서 뺀다', () async {
      final store = tempStore();
      final o = orchestrator(demo(tempProject(), extra: [const ProcessService(id: 'x', command: ['sleep', '37'])]),
          store: store);
      const item = ItemRef(projectId: 'demo', serviceId: 'x');
      addTearDown(() => o.stop(item));
      await o.start(item);
      final record = (await store.processes()).single;
      expect(record.item, item);
      expect(record.pid, o.liveProcesses.single.process.pid);
      expect(record.command, ['sleep', '37']);
      expect(record.appRunId, store.appRunId);

      await o.stop(item);
      expect(await store.processes(), isEmpty);
    });
  });

  group('앱 재시작 후 복구', () {
    const x = ItemRef(projectId: 'demo', serviceId: 'x');
    Project withX() => demo(tempProject(), extra: [const ProcessService(id: 'x', command: ['sh', '-c', 'sleep 30 & wait'])]);

    /// 앱을 다시 켜기 전 실행이 남긴 [x] 의 기록.
    Future<RuntimeStore> storeWithOldRecord() async {
      final store = tempStore();
      await store.putProcess(ProcessRecord(
          item: x, pid: 4242, pgid: 4242, command: const ['sh'], startedAt: DateTime(2026, 11, 22), appRunId: 'old'));
      return store;
    }

    test('앱을 다시 켜면 증명된 프로세스를 실행 중으로 되살리고 멈출 수 있다 (AT-06)', () async {
      final dir = Directory.systemTemp.createTempSync('ppoling_recover_');
      addTearDown(() => dir.deleteSync(recursive: true));
      RuntimeStore store() => RuntimeStore(() async => File('${dir.path}/runtime.json'));
      final project = withX();
      final logs = tempLogs();
      final before = orchestrator(project, store: store(), logs: logs);
      expect((await before.start(x)).outcome, ItemOutcome.ok);
      final pid = before.liveProcesses.single.process.pid;
      addTearDown(() => Process.run('kill', ['-KILL', '--', '-$pid']));

      // 기록은 비동기로 써진다. 파일에 남을 때까지 기다린다(실제 재시작은 몇 초 뒤라 상관없다).
      for (var i = 0; i < 50 && (await store().processes()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final after = orchestrator(project, store: store(), logs: logs); // 다시 켠 앱
      final states = <ItemState>[];
      after.events.where((e) => e is ItemStateChanged).cast<ItemStateChanged>().listen((e) => states.add(e.state));
      await after.recover();
      expect(after.stateOf(x), ItemState.ready);
      expect(states, [ItemState.running, ItemState.ready]);
      expect(after.liveProcesses.single.process.pid, pid);
      expect((await store().processes()).single.appRunId, isNot('old'));

      expect((await after.stop(x)).outcome, ItemOutcome.ok);
      expect((await Process.run('kill', ['-0', '--', '-$pid'])).exitCode, isNot(0), reason: '그룹째 멈췄다');
    });

    test('증명되지 않은 기록은 확인 불가이고 멈추지 않는다 (AT-07)', () async {
      final store = await storeWithOldRecord();
      final o = orchestrator(withX(), store: store, processes: _AttachOnly(const Unverified()));
      await o.recover();
      expect(o.stateOf(x), ItemState.unknown);
      final r = await o.stop(x);
      expect(r.outcome, ItemOutcome.failed);
      expect(o.stateOf(x), ItemState.unknown, reason: '멈춘 척하지 않는다');
      expect(await o.stopAll('demo'), isA<RunSummary>());
      expect(o.stateOf(x), ItemState.unknown);
      expect((await store.processes()).single.pid, 4242, reason: '기록은 남긴다');
    });

    test('끝난 기록은 지우고 중지로 둔다', () async {
      final store = await storeWithOldRecord();
      final o = orchestrator(withX(), store: store, processes: _AttachOnly(const Gone()));
      await o.recover();
      expect(o.stateOf(x), ItemState.stopped);
      expect(await store.processes(), isEmpty);
    });

    test('설정에서 항목이 빠졌으면 확인 불가로 둔다', () async {
      final store = await storeWithOldRecord();
      final fake = _FakeRunning();
      final o = orchestrator(demo(tempProject()), store: store, processes: _AttachOnly(Attached(fake)));
      await o.recover();
      expect(o.stateOf(x), ItemState.unknown);
      expect(fake.stopped, isFalse);
    });

    test('되살린 항목이 끝나면 로그의 종료 코드로 상태를 바꾼다', () async {
      final store = await storeWithOldRecord();
      final logs = tempLogs();
      final fake = _FakeRunning();
      final o = orchestrator(withX(), store: store, logs: logs, processes: _AttachOnly(Attached(fake)));
      await o.recover();
      expect(o.stateOf(x), ItemState.ready);

      final log = await logs.fileOf(x);
      log.parent.createSync(recursive: true);
      log.writeAsStringSync('${endLine(2)}\n');
      final failed = o.events.where((e) => e is ItemStateChanged).cast<ItemStateChanged>().firstWhere((e) => e.state == ItemState.failed);
      fake.finish();
      expect((await failed).exitCode, 2);
      expect(await store.processes(), isEmpty);
    });

    test('프로젝트 목록을 못 읽어도 복구는 예외 없이 끝난다', () async {
      final o = RunnerOrchestrator(
        projects: () => throw StateError('아직 준비 안 됨'),
        launcher: () => throw StateError('아직 준비 안 됨'),
        ports: () => FakePortProbe(),
        http: () => FakeHttpProbe(),
        runtime: () => FakeRuntimeQuery(),
        processes: _AttachOnly(const Gone()),
        logs: tempLogs(),
        store: tempStore(),
      );
      await o.recover();
    });

    test('앱을 다시 켜면 떠 있는 Compose 항목을 실행 중으로 보여 준다', () async {
      final project = demo(tempProject());
      FakeItemLauncher? shared;
      ItemLauncher launcher(ProjectRepository repo) => shared ??= FakeItemLauncher(repo, reachable: {'storage'});
      const db = ItemRef(projectId: 'demo', serviceId: 'db');
      expect((await orchestrator(project, launcher: launcher).start(db)).outcome, ItemOutcome.ok);

      final after = orchestrator(project, launcher: launcher);
      await after.recover();
      expect(after.stateOf(db), ItemState.running);
      expect(after.stateOf(const ItemRef(projectId: 'demo', serviceId: 'api')), ItemState.stopped);
    });
  });
}

/// [attach] 결과만 정해 주는 실행기. 띄우지는 않는다.
class _AttachOnly implements ProcessLauncher {
  _AttachOnly(this.result);

  final AttachResult result;

  @override
  Future<AttachResult> attach({required int pid, required DateTime startedAt, String? jobName}) async => result;

  @override
  Future<RunningProcess> start(List<String> command,
          {required String workingDirectory, Map<String, String> environment = const {}, required LogTarget log}) =>
      throw UnimplementedError();
}

/// 다시 붙은 것처럼 보이는 프로세스. [finish] 를 부르면 끝난다.
class _FakeRunning implements RunningProcess {
  final _done = Completer<int>();
  var stopped = false;

  void finish() => _done.complete(-1);

  @override
  int get pid => 4242;

  @override
  int get pgid => 4242;

  @override
  DateTime get startedAt => DateTime(2026, 11, 22);

  @override
  String? get jobName => null;

  @override
  Stream<OutputLine> get output => const Stream.empty();

  @override
  Future<int> get exitCode => _done.future;

  @override
  Future<bool> get groupAlive async => !_done.isCompleted;

  @override
  Future<bool> contains(int pid) async => false;

  @override
  Future<StopResult> stop(Duration timeout) async {
    stopped = true;
    finish();
    return const StopResult(forced: false);
  }
}

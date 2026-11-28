import 'dart:async';

import '../contracts/orchestrator.dart';
import '../contracts/project_repository.dart';
import '../events/run_events.dart';
import '../models/failure.dart';
import '../models/item_ref.dart';
import '../models/run.dart';
import '../models/service_config.dart';

/// [Orchestrator] 의 가짜 구현. 실제로 띄우지 않고, 상태만 바로바로 바꾸며 이벤트를 보낸다.
///
/// [failing] 에 넣은 항목은 시작에 실패한다(원격이면 연결 안 됨). 테스트 중에 바꿔도 된다.
/// 실패 원인은 [causes] 에 넣은 것이고, 없으면 `시작 실패`([CommandFailed], 종료 코드 1)다.
/// 상태는 원인을 따른다(예: [ReadyTimeout] 이면 `준비 시간 초과`). 실패 안내 카드를 원인별로 만들 때 쓴다.
/// ```dart
/// const api = ItemRef(projectId: 'my-team-project', serviceId: 'api');
/// final runner = FakeOrchestrator(FakeProjectRepository.withSamples(),
///     failing: {api}, causes: {api: ReadyTimeout(Duration(seconds: 60))});
/// final summary = await runner.runAll('my-team-project');   // api 준비 시간 초과, web 건너뜀
/// ```
class FakeOrchestrator implements Orchestrator {
  FakeOrchestrator(this._projects, {Set<ItemRef> failing = const {}, Map<ItemRef, FailureCause> causes = const {}})
      : failing = {...failing},
        causes = {...causes};

  final ProjectRepository _projects;
  final Set<ItemRef> failing;
  final Map<ItemRef, FailureCause> causes;
  final Map<ItemRef, FailureCause> _causes = {};
  final _events = StreamController<RunEvent>.broadcast();
  final Map<ItemRef, ItemState> _states = {};
  final Map<String, RunSummary> _lastRuns = {};

  @override
  Stream<RunEvent> get events => _events.stream;

  @override
  ItemState stateOf(ItemRef item) => _states[item] ?? ItemState.stopped;

  @override
  FailureCause? causeOf(ItemRef item) => _causes[item];

  @override
  Future<RunSummary> runAll(String projectId) async {
    final startedAt = DateTime.now();
    final results = <String, ItemResult>{};
    for (final s in _inOrder(await _services(projectId))) {
      final item = ItemRef(projectId: projectId, serviceId: s.id);
      final failedDep = s.dependsOn.where((d) => results[d] != null && results[d]!.outcome != ItemOutcome.ok);
      results[s.id] = failedDep.isNotEmpty
          ? ItemResult(item: item, outcome: ItemOutcome.skipped, reason: '${failedDep.first} 항목이 실패해서 시작하지 않았어요.')
          : await _up(item, s);
    }
    final summary =
        RunSummary(projectId: projectId, startedAt: startedAt, finishedAt: DateTime.now(), items: [...results.values]);
    _lastRuns[projectId] = summary;
    if (summary.succeeded) _events.add(RunSucceeded(summary));
    return summary;
  }

  @override
  Future<RunSummary> stopAll(String projectId) async {
    final startedAt = DateTime.now();
    final order = _inOrder(await _services(projectId)).reversed.where((s) => s is! RemoteService);
    final items = [for (final s in order) _down(ItemRef(projectId: projectId, serviceId: s.id))];
    return RunSummary(projectId: projectId, startedAt: startedAt, finishedAt: DateTime.now(), items: items);
  }

  @override
  Future<ItemResult> start(ItemRef item) async => _up(item, await _service(item));

  @override
  Future<ItemResult> stop(ItemRef item) async {
    final service = await _service(item);
    if (service is RemoteService) return ItemResult(item: item, outcome: ItemOutcome.ok);
    return _down(item);
  }

  @override
  Future<RunSummary?> lastRun(String projectId) async {
    await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    return _lastRuns[projectId];
  }

  Future<ItemResult> _up(ItemRef item, ServiceConfig service) async {
    final state = stateOf(item);
    if (state == ItemState.ready || state == ItemState.connected) return ItemResult(item: item, outcome: ItemOutcome.ok);

    if (service is RemoteService) {
      if (failing.contains(item)) {
        const reason = '연결할 수 없어요.';
        _set(item, ItemState.disconnected, reason: reason);
        return ItemResult(item: item, outcome: ItemOutcome.failed, reason: reason);
      }
      _set(item, ItemState.connected);
      return ItemResult(item: item, outcome: ItemOutcome.ok);
    }

    _set(item, ItemState.starting);
    _set(item, ItemState.running);
    if (failing.contains(item)) {
      final cause =
          causes[item] ?? const CommandFailed(exitCode: 1, evidence: ['Error: Cannot find module \'express\'']);
      final exitCode = switch (cause) {
        CommandFailed(:final exitCode) || Crashed(:final exitCode) => exitCode,
        _ => null,
      };
      final reason = causes.containsKey(item) ? '실패했어요.' : '시작하자마자 종료됐어요 (종료 코드 1).';
      _set(item, cause.state, reason: reason, exitCode: exitCode, cause: cause);
      return ItemResult(item: item, outcome: ItemOutcome.failed, reason: reason, exitCode: exitCode, cause: cause);
    }
    _set(item, ItemState.ready);
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  ItemResult _down(ItemRef item) {
    if (stateOf(item) != ItemState.stopped) {
      _set(item, ItemState.stopping);
      _set(item, ItemState.stopped);
    }
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  void _set(ItemRef item, ItemState state, {String? reason, int? exitCode, FailureCause? cause}) {
    _states[item] = state;
    if (cause == null) {
      _causes.remove(item);
    } else {
      _causes[item] = cause;
    }
    _events.add(ItemStateChanged(item, state, reason: reason, exitCode: exitCode, cause: cause));
  }

  Future<List<ServiceConfig>> _services(String projectId) async =>
      (await _projects.getProject(projectId)).config?.services ?? const []; // 없으면 ProjectNotFoundException

  Future<ServiceConfig> _service(ItemRef item) async {
    final services = await _services(item.projectId);
    return services.firstWhere((s) => s.id == item.serviceId,
        orElse: () => throw ArgumentError.value(item.serviceId, 'serviceId', '프로젝트에 없는 항목'));
  }

  /// 의존하는 항목이 앞에 오도록 줄 세운다. 순환은 설정 검증이 막으므로 남으면 그대로 뒤에 붙인다.
  static List<ServiceConfig> _inOrder(List<ServiceConfig> services) {
    final ids = {for (final s in services) s.id};
    final done = <String>{};
    final order = <ServiceConfig>[];
    var rest = [...services];
    while (rest.isNotEmpty) {
      final next = rest.where((s) => s.dependsOn.every((d) => done.contains(d) || !ids.contains(d))).toList();
      if (next.isEmpty) return order..addAll(rest);
      order.addAll(next);
      done.addAll(next.map((s) => s.id));
      rest = rest.where((s) => !done.contains(s.id)).toList();
    }
    return order;
  }
}

import 'dart:async';

import 'package:ppoling_core/contracts.dart';

import 'run_info.dart';

/// A 의 [Orchestrator] 에서 카드용 실행 정보를 만든다.
///
/// - 마지막 실행: [Orchestrator.lastRun] 의 시작 시각과 성공 여부(마지막 전체 실행).
/// - 실행 중 개수: 원격이 아닌 항목 가운데 떠 있는 것(시작 중·실행 중·준비 완료·종료 중).
///   원격 항목은 전체 종료에서도 연결됨으로 남아서 세지 않는다.
/// - 프로젝트 목록이나 [Orchestrator.events] 가 바뀔 때마다 전체를 다시 만들어 보낸다.
class OrchestratorRunInfoSource implements RunInfoSource {
  OrchestratorRunInfoSource(this._runner, this._projects);

  final Orchestrator _runner;
  final ProjectRepository _projects;

  static const _up = {ItemState.starting, ItemState.running, ItemState.ready, ItemState.stopping};

  @override
  Stream<Map<String, RunInfo>> watchRunInfo() {
    late final StreamController<Map<String, RunInfo>> controller;
    StreamSubscription<Object>? events;
    StreamSubscription<List<Project>>? projects;
    var current = const <Project>[];
    var latest = 0;

    Future<void> refresh() async {
      final ticket = ++latest;
      final info = await _read(current);
      // 늦게 끝난 옛 계산이 새 결과를 덮지 않게, 마지막으로 시작한 것만 보낸다.
      if (ticket == latest && !controller.isClosed) controller.add(info);
    }

    controller = StreamController(
      onListen: () {
        events = _runner.events.listen((_) => refresh());
        projects = _projects.watchProjects().listen((p) {
          current = p;
          refresh();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await events?.cancel();
        await projects?.cancel();
      },
    );
    return controller.stream;
  }

  Future<Map<String, RunInfo>> _read(List<Project> projects) async {
    final info = <String, RunInfo>{};
    for (final p in projects) {
      RunSummary? last;
      try {
        last = await _runner.lastRun(p.id);
      } on PpolingException {
        last = null; // 읽는 사이 목록에서 빠졌다. 다음 목록 갱신 때 사라진다.
      }
      final running = (p.config?.services ?? const <ServiceConfig>[])
          .where((s) => s is! RemoteService && _up.contains(_runner.stateOf(ItemRef(projectId: p.id, serviceId: s.id))))
          .length;
      if (last != null || running > 0) {
        info[p.id] = RunInfo(lastRunAt: last?.startedAt, lastSucceeded: last?.succeeded, running: running);
      }
    }
    return info;
  }
}

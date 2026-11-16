import 'package:flutter_test/flutter_test.dart';

import '../contracts/orchestrator.dart';
import '../events/run_events.dart';
import '../models/errors.dart';
import '../models/item_ref.dart';
import '../models/run.dart';
import '../models/service_config.dart';

/// [orchestratorContract] 가 테스트마다 받는 준비물.
class OrchestratorFixture {
  OrchestratorFixture({
    required this.orchestrator,
    required this.failingOrchestrator,
    required this.projectId,
    required this.services,
    required this.failingServiceId,
    this.unknownProjectId = 'no-such-project',
  });

  /// 아무 항목도 띄우지 않은 Orchestrator. [projectId] 의 항목이 모두 성공해야 한다.
  final Orchestrator orchestrator;

  /// [orchestrator] 와 같지만 [failingServiceId] 항목이 실패하는 Orchestrator.
  /// 진짜 구현 테스트에서는 그 항목의 명령이 바로 실패하는 프로젝트를 쓴다.
  final Orchestrator failingOrchestrator;

  /// 등록된 프로젝트. 의존 관계가 있는 항목과 원격 항목이 하나 이상 있어야 한다.
  final String projectId;

  /// [projectId] 의 실행 항목 전부(ppoling.yaml 의 services 그대로).
  final List<ServiceConfig> services;

  /// 실패시킬 항목. 다른 항목이 이 항목에 의존해야 건너뜀을 확인할 수 있다.
  final String failingServiceId;

  final String unknownProjectId;

  ItemRef ref(String serviceId) => ItemRef(projectId: projectId, serviceId: serviceId);
}

/// [Orchestrator] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
/// 테스트가 띄운 항목은 끝날 때 스스로 멈춘다.
void orchestratorContract(Future<OrchestratorFixture> Function() setUp) {
  /// [action] 동안 나온 이벤트를 모은다.
  Future<(T, List<RunEvent>)> recording<T>(Orchestrator o, Future<T> Function() action) async {
    final events = <RunEvent>[];
    final sub = o.events.listen(events.add);
    final result = await action();
    await Future<void>.delayed(Duration.zero); // 마지막 이벤트가 도착할 시간
    await sub.cancel();
    return (result, events);
  }

  List<ItemStateChanged> changesOf(List<RunEvent> events, ItemRef item) =>
      events.whereType<ItemStateChanged>().where((e) => e.item == item).toList();

  int indexOf(List<RunEvent> events, ItemRef item, bool Function(ItemState) match) =>
      events.indexWhere((e) => e is ItemStateChanged && e.item == item && match(e.state));

  bool isUp(ItemState s) => s == ItemState.ready || s == ItemState.connected;

  /// [id] 에 바로 또는 건너서 의존하는 항목들.
  Set<String> dependentsOf(List<ServiceConfig> services, String id) {
    final found = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final s in services) {
        if (!found.contains(s.id) && s.dependsOn.any((d) => d == id || found.contains(d))) {
          found.add(s.id);
          changed = true;
        }
      }
    }
    return found;
  }

  test('전체 실행은 의존하는 항목이 준비된 뒤에 시작하고, 모두 성공하면 RunSucceeded 를 한 번 보낸다', () async {
    final f = await setUp();
    final o = f.orchestrator;
    final (summary, events) = await recording(o, () => o.runAll(f.projectId));
    addTearDown(() => o.stopAll(f.projectId));

    expect(summary.projectId, f.projectId);
    expect(summary.succeeded, isTrue, reason: '${summary.items.map((r) => '${r.item}: ${r.reason}')}');
    expect(summary.items.map((r) => r.item.serviceId), unorderedEquals(f.services.map((s) => s.id)));

    for (final s in f.services) {
      final first = indexOf(events, f.ref(s.id), (_) => true);
      for (final d in s.dependsOn) {
        expect(first, greaterThan(indexOf(events, f.ref(d), isUp)), reason: '${s.id} 는 $d 가 준비된 뒤에 시작해야 한다');
      }
      expect(isUp(o.stateOf(f.ref(s.id))), isTrue, reason: s.id);
      expect(o.stateOf(f.ref(s.id)) == ItemState.connected, s is RemoteService, reason: s.id);
    }

    final succeeded = events.whereType<RunSucceeded>().toList();
    expect(succeeded, hasLength(1));
    expect(succeeded.single.summary.projectId, f.projectId);
    expect(events.last, isA<RunSucceeded>());
  });

  test('항목이 실패하면 그 항목에 의존하는 항목은 시작하지 않고 건너뜀, 나머지는 계속한다', () async {
    final f = await setUp();
    final o = f.failingOrchestrator;
    final (summary, events) = await recording(o, () => o.runAll(f.projectId));
    addTearDown(() => o.stopAll(f.projectId));

    final skipped = dependentsOf(f.services, f.failingServiceId);
    expect(skipped, isNotEmpty, reason: '준비물: 실패 항목에 의존하는 항목이 있어야 한다');

    final byId = {for (final r in summary.items) r.item.serviceId: r};
    expect(byId[f.failingServiceId]!.outcome, ItemOutcome.failed);
    expect(byId[f.failingServiceId]!.reason, isNotNull);
    expect(o.stateOf(f.ref(f.failingServiceId)), ItemState.failed);
    for (final id in skipped) {
      expect(byId[id]!.outcome, ItemOutcome.skipped, reason: id);
      expect(changesOf(events, f.ref(id)), isEmpty, reason: '$id 는 시작하지 않아야 한다');
    }
    for (final s in f.services.where((s) => s.id != f.failingServiceId && !skipped.contains(s.id))) {
      expect(byId[s.id]!.outcome, ItemOutcome.ok, reason: s.id);
    }

    expect(summary.succeeded, isFalse);
    expect(events.whereType<RunSucceeded>(), isEmpty);
  });

  test('전체 종료는 역순으로 멈추고 원격 항목은 건드리지 않는다', () async {
    final f = await setUp();
    final o = f.orchestrator;
    await o.runAll(f.projectId);
    final (summary, events) = await recording(o, () => o.stopAll(f.projectId));

    expect(summary.succeeded, isTrue);
    final local = f.services.where((s) => s is! RemoteService);
    expect(summary.items.map((r) => r.item.serviceId), unorderedEquals(local.map((s) => s.id)));

    for (final s in f.services) {
      if (s is RemoteService) {
        expect(changesOf(events, f.ref(s.id)), isEmpty, reason: '${s.id} 는 원격이라 건드리지 않는다');
        continue;
      }
      expect(o.stateOf(f.ref(s.id)), ItemState.stopped, reason: s.id);
      for (final d in s.dependsOn.where((d) => f.services.any((x) => x.id == d && x is! RemoteService))) {
        expect(indexOf(events, f.ref(d), (st) => st == ItemState.stopping),
            greaterThan(indexOf(events, f.ref(s.id), (st) => st == ItemState.stopped)),
            reason: '$d 는 ${s.id} 가 멈춘 뒤에 멈춰야 한다');
      }
    }
  });

  test('항목 하나를 시작·중지하고, 이미 멈춘 항목을 멈춰도 성공이다', () async {
    final f = await setUp();
    final o = f.orchestrator;
    final item = f.ref(f.services.firstWhere((s) => s.dependsOn.isEmpty && s is! RemoteService).id);
    addTearDown(() => o.stopAll(f.projectId));

    expect(o.stateOf(item), ItemState.stopped);
    expect((await o.start(item)).outcome, ItemOutcome.ok);
    expect(o.stateOf(item), ItemState.ready);

    expect((await o.stop(item)).outcome, ItemOutcome.ok);
    expect(o.stateOf(item), ItemState.stopped);
    expect((await o.stop(item)).outcome, ItemOutcome.ok);
  });

  test('마지막 전체 실행은 없으면 null, 실행하면 그 결과다', () async {
    final f = await setUp();
    final o = f.orchestrator;
    expect(await o.lastRun(f.projectId), isNull);

    final summary = await o.runAll(f.projectId);
    addTearDown(() => o.stopAll(f.projectId));
    final last = await o.lastRun(f.projectId);
    expect(last?.finishedAt, summary.finishedAt);
    expect(last?.succeeded, isTrue);
  });

  test('없는 프로젝트면 ProjectNotFoundException, 없는 항목이면 ArgumentError', () async {
    final f = await setUp();
    final o = f.orchestrator;
    await expectLater(o.runAll(f.unknownProjectId), throwsA(isA<ProjectNotFoundException>()));
    await expectLater(o.stopAll(f.unknownProjectId), throwsA(isA<ProjectNotFoundException>()));
    await expectLater(o.lastRun(f.unknownProjectId), throwsA(isA<ProjectNotFoundException>()));
    await expectLater(o.start(f.ref('no-such-service')), throwsArgumentError);
    await expectLater(o.stop(f.ref('no-such-service')), throwsArgumentError);
  });
}

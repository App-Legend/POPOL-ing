import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/src/orchestrator_run_info.dart';
import 'package:popoling_catalog/src/run_info.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/models.dart';

void main() {
  late FakeProjectRepository repo;
  late FakeOrchestrator runner;
  late OrchestratorRunInfoSource source;

  setUp(() {
    repo = FakeProjectRepository.withSamples();
    runner = FakeOrchestrator(repo);
    source = OrchestratorRunInfoSource(runner, repo);
  });

  test('한 번도 전체 실행하지 않았으면 기록이 없다', () async {
    expect(await source.watchRunInfo().first, isEmpty);
  });

  test('전체 실행하면 마지막 실행 시각·성공·떠 있는 항목 수가 생긴다', () async {
    final before = DateTime.now();
    await runner.runAll('my-team-project');
    final info = (await source.watchRunInfo().first)['my-team-project']!;
    expect(info.lastSucceeded, isTrue);
    expect(info.lastRunAt!.isBefore(before), isFalse);
    expect(info.running, 3, reason: '원격 항목(storage)은 세지 않는다');
  });

  test('항목이 실패한 전체 실행은 실패로 남고, 뜬 항목만 센다', () async {
    runner.failing.add(const ItemRef(projectId: 'my-team-project', serviceId: 'api'));
    await runner.runAll('my-team-project');
    final info = (await source.watchRunInfo().first)['my-team-project']!;
    expect(info.lastSucceeded, isFalse);
    expect(info.running, 1, reason: 'db 만 떠 있고 api 는 실패, web 은 건너뜀');
  });

  test('전체 종료하면 실행 중은 0 이 되고 마지막 실행은 남는다', () async {
    await runner.runAll('popoling');
    await runner.stopAll('popoling');
    final info = (await source.watchRunInfo().first)['popoling']!;
    expect(info.running, 0);
    expect(info.lastRunAt, isNotNull);
  });

  test('구독 중에 실행하면 바뀐 정보를 다시 보낸다', () async {
    final got = <Map<String, RunInfo>>[];
    final sub = source.watchRunInfo().listen(got.add);
    await pumpEventQueue();
    await runner.runAll('popoling');
    await pumpEventQueue();
    await sub.cancel();
    expect(got.first, isEmpty);
    expect(got.last['popoling']!.running, 1);
  });

  test('실행 기록을 읽다 생긴 오류는 스트림 오류로 알린다', () async {
    final broken = OrchestratorRunInfoSource(_BrokenOrchestrator(repo), repo);
    await expectLater(broken.watchRunInfo().first, throwsStateError);
  });

  test('프로젝트가 빠지면 그 실행 정보도 빠진다', () async {
    await runner.runAll('popoling');
    final got = <Map<String, RunInfo>>[];
    final sub = source.watchRunInfo().listen(got.add);
    await pumpEventQueue();
    await repo.removeProject('popoling');
    await pumpEventQueue();
    await sub.cancel();
    expect(got.first.keys, contains('popoling'));
    expect(got.last.keys, isNot(contains('popoling')));
  });
}

/// 실행 기록 저장소가 깨진 경우처럼, 약속에 없는 오류를 던지는 Orchestrator.
class _BrokenOrchestrator extends FakeOrchestrator {
  _BrokenOrchestrator(super.projects);

  @override
  Future<RunSummary?> lastRun(String projectId) async => throw StateError('실행 기록을 읽지 못했습니다');
}

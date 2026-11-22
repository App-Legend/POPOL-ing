import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_runner/src/runtime/runtime_store.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ppoling_runtime_');
    file = File('${dir.path}${Platform.pathSeparator}runtime.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  RuntimeStore store() => RuntimeStore(() async => file);

  const api = ItemRef(projectId: 'demo', serviceId: 'api');
  const web = ItemRef(projectId: 'demo', serviceId: 'web');

  test('마지막 전체 실행 결과를 다시 읽어도 같다', () async {
    final summary = RunSummary(
      projectId: 'demo',
      startedAt: DateTime(2026, 11, 18, 10),
      finishedAt: DateTime(2026, 11, 18, 10, 1),
      items: const [
        ItemResult(item: api, outcome: ItemOutcome.failed, reason: '준비 시간(60초)을 넘겼어요.', exitCode: 1, forced: true),
        ItemResult(item: web, outcome: ItemOutcome.skipped),
      ],
    );
    await store().saveRun(summary);

    final read = (await store().lastRun('demo'))!;
    expect(read.startedAt, summary.startedAt);
    expect(read.finishedAt, summary.finishedAt);
    expect(read.items.map((r) => (r.item, r.outcome, r.reason, r.exitCode, r.forced)), [
      (api, ItemOutcome.failed, '준비 시간(60초)을 넘겼어요.', 1, true),
      (web, ItemOutcome.skipped, null, null, false),
    ]);
    expect(await store().lastRun('other'), isNull);
  });

  test('프로세스 기록을 넣고 빼면 파일에도 남는다', () async {
    final s = store();
    final record = ProcessRecord(
        item: api, pid: 4321, pgid: 4321, command: const ['npm', 'run', 'dev'], startedAt: DateTime(2026, 11, 18), appRunId: s.appRunId);
    await s.putProcess(record);
    await s.putProcess(ProcessRecord(
        item: web, pid: 99, pgid: 99, command: const ['sleep', '1'], startedAt: DateTime(2026, 11, 18), appRunId: s.appRunId));
    await s.removeProcess(web);

    final read = (await store().processes()).single;
    expect((read.item, read.pid, read.pgid, read.startedAt, read.appRunId), (api, 4321, 4321, DateTime(2026, 11, 18), s.appRunId));
    expect(read.command, ['npm', 'run', 'dev']);
  });

  test('jobName 을 저장하고 다시 읽는다', () async {
    final s = store();
    await s.putProcess(ProcessRecord(
        item: api, pid: 1, pgid: 1, command: const ['a'], startedAt: DateTime(2026, 11, 22), appRunId: 'r', jobName: 'ppoling-1-2'));
    expect((await store().processes()).single.jobName, 'ppoling-1-2');
  });

  test('jobName 이 없는 예전 기록도 읽는다', () async {
    file.writeAsStringSync(
        '{"lastRuns":[],"processes":[{"projectId":"p","serviceId":"api","pid":1,"pgid":1,"command":["a"],"startedAt":"2026-11-18T00:00:00.000","appRunId":"old"}]}');
    final read = (await store().processes()).single;
    expect((read.pid, read.jobName), (1, null));
  });

  test('파일이 깨져 있으면 빈 기록으로 시작하고, 다음 저장에서 고친다', () async {
    file.writeAsStringSync('{깨진');
    final s = store();
    expect(await s.lastRun('demo'), isNull);
    expect(await s.processes(), isEmpty);
    await s.saveRun(RunSummary(projectId: 'demo', startedAt: DateTime(2026), finishedAt: DateTime(2026), items: const []));
    expect(await store().lastRun('demo'), isNotNull);
  });

  test('파일을 쓸 수 없어도 예외를 내지 않는다', () async {
    final blocker = File('${dir.path}${Platform.pathSeparator}not_a_dir')..writeAsStringSync('x');
    final s = RuntimeStore(() async => File('${blocker.path}${Platform.pathSeparator}runtime.json'));
    await s.saveRun(RunSummary(projectId: 'demo', startedAt: DateTime(2026), finishedAt: DateTime(2026), items: const []));
    expect(await s.lastRun('demo'), isNotNull, reason: '이번 실행 동안은 메모리 기록으로 답한다');
  });
}

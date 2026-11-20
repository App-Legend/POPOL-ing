import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/testing.dart';
import 'package:ppoling_runner/src/log/log_store.dart';
import 'package:ppoling_runner/src/log/runner_log_excerpt.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';

void main() {
  late Directory tmp;
  const item = ItemRef(projectId: 'my-team-project', serviceId: 'api');

  setUp(() => tmp = Directory.systemTemp.createTempSync('log_excerpt_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  OutputLine out(String t) => OutputLine(t, isError: false, at: DateTime(2026, 11, 20));

  group('RunnerLogExcerpt', () {
    const log = ['DB_PASSWORD=hunter2', 'Started', 'Connection refused: localhost:3306'];
    logExcerptContract(() async {
      final logs = LogStore(() async => tmp);
      // 기록이 다 써지기 전에 물어도 마지막 줄까지 돌려줘야 한다
      unawaited(logs.record(item, Stream.fromIterable(log.map(out)), secrets: ['hunter2']));
      return LogExcerptFixture(
        excerpt: RunnerLogExcerpt(projects: () => FakeProjectRepository.withSamples(), logs: logs),
        projectId: item.projectId,
        serviceId: item.serviceId,
        logLines: log,
        secret: 'hunter2',
      );
    });
  });

  test('아직 기록 중인 항목이면 오래 기다리지 않고 지금까지 쓴 줄을 돌려준다', () async {
    final logs = LogStore(() async => tmp);
    final c = StreamController<OutputLine>();
    unawaited(logs.record(item, c.stream));
    c.add(out('running'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final excerpt = RunnerLogExcerpt(
        projects: () => FakeProjectRepository.withSamples(), logs: logs, wait: const Duration(milliseconds: 100));
    expect((await excerpt.tail(item.projectId, item.serviceId)).last, 'running');
    await c.close();
  });
}

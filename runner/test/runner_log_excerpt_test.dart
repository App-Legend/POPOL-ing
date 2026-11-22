import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/testing.dart';
import 'package:popoling_runner/src/log/log_store.dart';
import 'package:popoling_runner/src/log/runner_log_excerpt.dart';
import 'package:popoling_runner_relay/log_file.dart';

void main() {
  late Directory tmp;
  const item = ItemRef(projectId: 'my-team-project', serviceId: 'api');

  setUp(() => tmp = Directory.systemTemp.createTempSync('log_excerpt_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final at = DateTime(2026, 11, 20);

  group('RunnerLogExcerpt', () {
    const log = ['DB_PASSWORD=hunter2', 'Started', 'Connection refused: localhost:3306'];
    logExcerptContract(() async {
      final logs = LogStore(() async => tmp);
      final file = RotatingLogFile(await logs.fileOf(item));
      await file.open();
      await file.write(startLine(at));
      for (final l in log) {
        await file.write(outputLine(at, maskSecrets(l, ['hunter2']), isError: false));
      }
      await file.close();
      return LogExcerptFixture(
        excerpt: RunnerLogExcerpt(projects: () => FakeProjectRepository.withSamples(), logs: logs),
        projectId: item.projectId,
        serviceId: item.serviceId,
        logLines: log,
        secret: 'hunter2',
      );
    });
  });
}

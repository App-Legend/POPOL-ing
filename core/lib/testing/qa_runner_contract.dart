import 'package:flutter_test/flutter_test.dart';

import '../contracts/qa_runner.dart';
import '../models/check_config.dart';
import '../models/errors.dart';
import '../models/qa.dart';

/// [qaRunnerContract] 가 테스트마다 받는 준비물.
class QaRunnerFixture {
  QaRunnerFixture({
    required this.runner,
    required this.projectId,
    required this.checks,
    this.unknownProjectId = 'no-such-project',
  });

  /// 검사 이력이 비어 있는 QaRunner.
  final QaRunner runner;

  /// 등록된 프로젝트. 그 ppoling.yaml 의 checks 가 [checks] 와 같아야 하고,
  /// 주소가 없는 check 가 하나 이상 있어야 한다.
  final String projectId;
  final List<CheckConfig> checks;

  /// 등록되지 않은 프로젝트 ID.
  final String unknownProjectId;
}

/// [QaRunner] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
/// ```dart
/// group('HttpQaRunner', () {
///   qaRunnerContract(() async => QaRunnerFixture(runner: ..., projectId: ..., checks: ...));
/// });
/// ```
void qaRunnerContract(Future<QaRunnerFixture> Function() setUp) {
  test('준비물: 주소가 없는 check 가 하나 이상 있다', () async {
    final f = await setUp();
    expect(f.checks.any((c) => !c.hasTarget), isTrue, reason: '주소 없는 check 를 하나 넣어 주세요.');
  });

  test('결과는 checks 와 같은 순서·같은 개수다', () async {
    final f = await setUp();
    final run = await f.runner.runChecks(f.projectId);

    expect(run.projectId, f.projectId);
    expect([for (final r in run.results) r.name], [for (final c in f.checks) c.name]);
  });

  test('주소가 없는 check 는 검사하지 않고 설정 필요로 둔다', () async {
    final f = await setUp();
    final run = await f.runner.runChecks(f.projectId);

    for (final (i, check) in f.checks.indexed) {
      if (!check.hasTarget) {
        expect(run.results[i].status, QaStatus.needsSetup, reason: check.name);
        expect(run.results[i].statusCode, isNull, reason: check.name);
      }
    }
  });

  test('계기를 넘기면 그대로 기록하고, 안 넘기면 수동 검사다', () async {
    final f = await setUp();
    expect((await f.runner.runChecks(f.projectId)).trigger, QaTrigger.manual);
    expect((await f.runner.runChecks(f.projectId, trigger: QaTrigger.staleCheck)).trigger, QaTrigger.staleCheck);
  });

  test('이력은 처음엔 비어 있고, 검사할 때마다 최근 것이 앞에 쌓인다', () async {
    final f = await setUp();
    expect(await f.runner.history(f.projectId), isEmpty);

    await f.runner.runChecks(f.projectId);
    await f.runner.runChecks(f.projectId, trigger: QaTrigger.staleCheck);

    final history = await f.runner.history(f.projectId);
    expect(history.map((r) => r.trigger), [QaTrigger.staleCheck, QaTrigger.manual]);
  });

  test('없는 프로젝트를 검사하면 ProjectNotFoundException, 이력은 빈 목록', () async {
    final f = await setUp();
    await expectLater(f.runner.runChecks(f.unknownProjectId), throwsA(isA<ProjectNotFoundException>()));
    expect(await f.runner.history(f.unknownProjectId), isEmpty);
  });
}

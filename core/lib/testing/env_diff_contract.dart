import 'package:flutter_test/flutter_test.dart';

import '../contracts/env_diff.dart';
import '../models/errors.dart';

/// [envDiffContract] 가 테스트마다 받는 준비물.
class EnvDiffFixture {
  EnvDiffFixture({
    required this.diff,
    required this.changedProjectId,
    required this.changedNames,
    required this.noRecordProjectId,
    this.unknownProjectId = 'no-such-project',
  });

  final EnvDiff diff;

  /// 성공 기록이 있고 그 뒤로 [changedNames] 가 바뀐 프로젝트.
  final String changedProjectId;
  final Set<String> changedNames;

  /// 등록은 됐지만 성공한 실행이 아직 없는 프로젝트.
  final String noRecordProjectId;

  final String unknownProjectId;
}

/// [EnvDiff] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void envDiffContract(Future<EnvDiffFixture> Function() setUp) {
  test('바뀐 것을 돌려준다', () async {
    final f = await setUp();
    final changes = await f.diff.sinceLastSuccess(f.changedProjectId);
    expect({for (final c in changes!) c.name}, f.changedNames);
  });

  test('성공 기록이 없으면 null, 없는 프로젝트면 ProjectNotFoundException', () async {
    final f = await setUp();
    expect(await f.diff.sinceLastSuccess(f.noRecordProjectId), isNull);
    await expectLater(f.diff.sinceLastSuccess(f.unknownProjectId), throwsA(isA<ProjectNotFoundException>()));
  });
}

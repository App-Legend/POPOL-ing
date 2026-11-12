import 'package:flutter_test/flutter_test.dart';

import '../contracts/log_excerpt.dart';
import '../models/errors.dart';

/// [logExcerptContract] 가 테스트마다 받는 준비물.
class LogExcerptFixture {
  LogExcerptFixture({
    required this.excerpt,
    required this.projectId,
    required this.serviceId,
    required this.logLines,
    required this.secret,
    this.unknownProjectId = 'no-such-project',
  });

  final LogExcerpt excerpt;
  final String projectId;
  final String serviceId;

  /// [serviceId] 가 남긴 로그 전체(가리기 전). 3줄 이상, 첫 줄에 [secret] 이 있고 마지막 두 줄에는 없어야 한다.
  final List<String> logLines;

  /// 그 항목 `.env` 의 값 하나.
  final String secret;

  final String unknownProjectId;
}

/// [LogExcerpt] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void logExcerptContract(Future<LogExcerptFixture> Function() setUp) {
  test('준비물: 로그 3줄 이상, 첫 줄에만 비밀값', () async {
    final f = await setUp();
    expect(f.logLines.length, greaterThanOrEqualTo(3));
    expect(f.logLines.first, contains(f.secret));
    expect(f.logLines.skip(f.logLines.length - 2).any((l) => l.contains(f.secret)), isFalse);
  });

  test('마지막 n줄을 로그 순서대로 돌려준다', () async {
    final f = await setUp();
    expect(await f.excerpt.tail(f.projectId, f.serviceId, lines: 2), f.logLines.sublist(f.logLines.length - 2));
  });

  test('비밀값은 가려서 돌려준다', () async {
    final f = await setUp();
    final lines = await f.excerpt.tail(f.projectId, f.serviceId, lines: f.logLines.length);
    expect(lines, hasLength(f.logLines.length));
    expect(lines.any((l) => l.contains(f.secret)), isFalse);
  });

  test('모르는 항목이면 빈 목록, 없는 프로젝트면 ProjectNotFoundException', () async {
    final f = await setUp();
    expect(await f.excerpt.tail(f.projectId, 'no-such-service'), isEmpty);
    await expectLater(f.excerpt.tail(f.unknownProjectId, f.serviceId), throwsA(isA<ProjectNotFoundException>()));
  });
}

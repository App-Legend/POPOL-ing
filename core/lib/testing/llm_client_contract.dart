import 'package:flutter_test/flutter_test.dart';

import '../contracts/llm_client.dart';
import '../models/errors.dart';
import '../models/llm.dart';

/// [llmClientContract] 가 테스트마다 받는 준비물.
class LlmClientFixture {
  LlmClientFixture({required this.configured, required this.unconfigured});

  /// API 키가 들어 있는 LlmClient. 진짜 구현은 실제 서버 대신 가짜 HTTP 를 물려서 넘긴다.
  final LlmClient configured;

  /// API 키가 없는 LlmClient.
  final LlmClient unconfigured;
}

/// [LlmClient] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void llmClientContract(Future<LlmClientFixture> Function() setUp) {
  test('modelName 은 키가 없어도 비어 있지 않다 (분석 기록의 "사용 모델")', () async {
    final f = await setUp();
    expect(f.configured.modelName.trim(), isNotEmpty);
    expect(f.unconfigured.modelName.trim(), isNotEmpty);
  });

  test('키가 없으면 isConfigured 는 false, complete 는 missingKey', () async {
    final f = await setUp();
    expect(await f.unconfigured.isConfigured(), isFalse);
    await expectLater(
      f.unconfigured.complete('요약해 줘'),
      throwsA(isA<LlmException>().having((e) => e.failure, 'failure', LlmFailure.missingKey)),
    );
  });

  test('키가 있으면 isConfigured 는 true, complete 는 빈 문자열이 아닌 답', () async {
    final f = await setUp();
    expect(await f.configured.isConfigured(), isTrue);
    expect(await f.configured.complete('요약해 줘'), isNotEmpty);
  });
}

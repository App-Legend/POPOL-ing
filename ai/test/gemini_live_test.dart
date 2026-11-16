// 실제 Gemini 에 짧은 질문 하나를 보내 키와 연결을 확인한다. 평소(CI 포함)에는 건너뛴다.
//
// 실행: 환경변수 GEMINI_API_KEY 에 내 키를 넣고 `flutter test test/gemini_live_test.dart`
// 키는 파일에 적지 않는다. 프로젝트 내용은 보내지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/ai.dart';
import 'package:ppoling_core/models.dart';

void main() {
  final key = Platform.environment['GEMINI_API_KEY'];

  test(
    '실제 Gemini 가 답하고, 답한 모델 이름이 남는다',
    () async {
      final client = GeminiLlmClient(keys: MemoryApiKeyStore(key), retryDelay: const Duration(seconds: 5));
      try {
        final reply = await client.complete('1 더하기 1은? 숫자만 답해 주세요.');
        expect(reply, contains('2'));
        expect(client.modelName, startsWith('gemini-'));
        // ignore: avoid_print
        print('모델: ${client.modelName}, 답: ${reply.trim()}');
      } on LlmException catch (e) {
        // 서버가 붐비면(무료 등급에서 자주 있다) 실패가 아니라 상태만 알린다.
        if (e.failure != LlmFailure.network) rethrow;
        markTestSkipped('Gemini 서버가 붐벼서 확인하지 못했어요: ${e.message}');
      }
    },
    skip: key == null || key.isEmpty ? 'GEMINI_API_KEY 가 없어서 건너뜀' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

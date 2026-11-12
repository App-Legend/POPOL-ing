import '../contracts/llm_client.dart';
import '../models/errors.dart';
import '../models/llm.dart';

/// [LlmClient] 의 가짜 구현. 아무 데도 보내지 않고 [reply] 를 돌려준다.
///
/// 받은 prompt 는 [sent] 에 남는다. 보낸 내용 검사(AT-21) 테스트에 쓴다.
/// ```dart
/// final ai = FakeLlmClient(reply: 'API 헬스가 503으로 실패했어요.');
/// final noKey = FakeLlmClient(configured: false);     // complete 하면 missingKey
/// final busy = FakeLlmClient(failWith: LlmFailure.quotaExceeded);
/// ```
class FakeLlmClient implements LlmClient {
  FakeLlmClient({this.configured = true, this.reply = 'AI 답변 예시예요.', this.failWith});

  /// API 키가 들어 있는 것으로 칠지. 테스트 중에 바꿔도 된다.
  bool configured;

  /// [complete] 가 돌려줄 답.
  String reply;

  /// 주면 [complete] 가 이 이유로 실패한다.
  LlmFailure? failWith;

  /// 지금까지 보낸 prompt. 키가 없어 보내지 않은 것은 남지 않는다.
  final List<String> sent = [];

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<String> complete(String prompt, {String? system}) async {
    if (!configured) throw LlmException(LlmFailure.missingKey);
    sent.add(prompt);
    if (failWith case final failure?) throw LlmException(failure);
    return reply;
  }
}

import '../models/errors.dart';

/// AI 호출(AI-02 실행 실패 원인 분석, AI-03 QA 결과 요약). MVP 구현은 Gemini API.
///
/// - 진짜 구현: D (`ai/`). Gemini API 를 부르는 곳은 이 구현 하나뿐이다.
/// - 쓰는 곳: D(`ai/` 화면). 다른 기능은 데이터를 계약으로 넘길 뿐 직접 부르지 않는다.
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [llmClientContract] 로 확인한다.
/// - 사용자가 보낼 내용을 보고 [보내기]를 누른 뒤에만 [complete] 를 부른다. 확인은 부르는 쪽이 받는다.
/// - 보내는 내용에 `.env` 값·API 키를 넣지 않는다.
/// - API 키는 로그·화면에 평문으로 남기지 않는다.
abstract interface class LlmClient {
  /// 요청에 쓰는 모델 이름. 분석 기록의 "사용 모델"(기획서 §7)에 남긴다.
  /// 비어 있지 않고, 키 같은 비밀값은 넣지 않는다. 예: Gemini Flash 계열 모델 이름
  String get modelName;

  /// API 키가 들어 있는지. false 면 화면은 "API 키 필요"와 [키 입력]을 보여준다.
  Future<bool> isConfigured();

  /// [prompt] 를 보내고 답을 받는다. [system] 은 역할·형식 지시.
  /// 실패하면 [LlmException]. 키가 없으면 보내지 않고 [LlmFailure.missingKey].
  Future<String> complete(String prompt, {String? system});
}

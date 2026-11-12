import '../models/errors.dart';

/// 실행 항목 로그의 끝부분(AI-02 실행 실패 원인 분석의 재료).
///
/// - 진짜 구현: A (`runner/`)
/// - 쓰는 곳: D(`ai/` 실행 실패 원인 분석)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [logExcerptContract] 로 확인한다.
/// - `.env` 값은 가린 뒤 돌려준다(AT-11). 이 결과는 외부(Gemini API)로 나갈 수 있다.
/// - 줄 순서는 로그 순서 그대로(오래된 줄이 앞).
abstract interface class LogExcerpt {
  /// 항목 [serviceId] 로그의 마지막 [lines] 줄. 로그가 없거나 모르는 항목이면 빈 목록.
  /// 없는 프로젝트면 [ProjectNotFoundException].
  Future<List<String>> tail(String projectId, String serviceId, {int lines = 50});
}

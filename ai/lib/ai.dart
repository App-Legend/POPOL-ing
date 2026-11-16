/// AI 프로젝트 검사(D). `app/` 은 [register] 하나만 부른다.
/// `import 'package:ppoling_ai/ai.dart' as ai;`
///
/// Gemini API 는 이 패키지의 [GeminiLlmClient] 한 곳에서만 부른다.
/// 보낼 때는 [AiSender] 로 비밀값을 가리고 보내기 전 확인 창을 거친다.
library;

import 'package:ppoling_core/contracts.dart';

import 'src/api_key_store.dart';
import 'src/gemini_client.dart';

export 'src/ai_sender.dart' show AiSender;
export 'src/api_key_dialog.dart' show ApiKeyChange, ApiKeyDialog, showApiKeyDialog;
export 'src/api_key_store.dart' show ApiKeyStore, MemoryApiKeyStore, SecureApiKeyStore;
export 'src/gemini_client.dart' show GeminiHttpResponse, GeminiLlmClient, GeminiTransport;
export 'src/messages.dart' show LlmErrorText, llmErrorText;
export 'src/send_confirm_dialog.dart' show SendConfirmDialog;

/// AI 프로젝트 검사의 화면과 구현을 앱에 등록한다.
///
/// API 키는 사용자가 앱에서 넣고 이 컴퓨터의 보안 저장소에만 둔다. 앱 빌드에는 키를 넣지 않는다.
// 4주차에 AI-03 QA 결과 요약·AI-02 실행 실패 원인 분석과 AI 검사(8) 화면을 여기서 등록한다.
void register(AppRegistry app) {
  final keys = SecureApiKeyStore();
  app.provide<LlmClient>(GeminiLlmClient(keys: keys));
}

/// AI 프로젝트 검사(D). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_ai/ai.dart' as ai;`
///
/// Gemini API 는 이 패키지의 [GeminiLlmClient] 한 곳에서만 부른다.
/// 보낼 때는 [AiSender] 로 비밀값을 가리고 보내기 전 확인 창을 거친다.
library;

import 'package:flutter/widgets.dart';
import 'package:popoling_core/contracts.dart';

import 'src/ai_screen.dart';
import 'src/api_key_store.dart';
import 'src/gemini_client.dart';

export 'src/ai_sender.dart' show AiSender;
export 'src/api_key_dialog.dart' show ApiKeyChange, ApiKeyCheck, ApiKeyDialog, showApiKeyDialog;
export 'src/api_key_store.dart' show ApiKeyStore, MemoryApiKeyStore, SecureApiKeyStore;
export 'src/gemini_client.dart' show GeminiFetch, GeminiHttpResponse, GeminiLlmClient, GeminiTransport;
export 'src/messages.dart' show LlmErrorText, llmErrorText;
export 'src/qa_summary_panel.dart' show QaSummaryPanel, qaSummaryRequestName;
export 'src/send_confirm_dialog.dart' show SendConfirmDialog;

/// AI 프로젝트 검사의 화면과 구현을 앱에 등록한다.
///
/// API 키는 사용자가 앱에서 넣고 이 컴퓨터의 보안 저장소에만 둔다. 앱 빌드에는 키를 넣지 않는다.
/// AI 검사(8, `/ai`) 화면은 Gemini 연결과 같은 저장소의 키를 보여 주고 바꾼다.
/// 대시보드가 프로젝트 ID 를 넘기면(`arguments`) 그 프로젝트의 헬스체크 결과 요약(AI-03) 카드를 그린다.
// AI-02 실행 실패 원인 분석은 다음에 더한다.
void register(AppRegistry app) {
  final keys = SecureApiKeyStore();
  final gemini = GeminiLlmClient(keys: keys);
  app.provide<LlmClient>(gemini);
  // 키는 늘 Gemini 키라, 나중에 LlmClient 를 바꿔 끼워도 [연결 확인]은 Gemini 로 한다.
  app.route('/ai', (context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final projectId = args is String ? args : null;
    return AiScreen(
      keys: keys,
      client: app.read<LlmClient>(),
      checkKey: gemini.checkKey,
      projectId: projectId,
      // 프로젝트가 있을 때만 꺼낸다. 프로젝트 없이 여는 /ai 는 QA 쪽 등록에 기대지 않는다.
      qa: projectId == null ? null : app.read<QaRunner>(),
      orchestrator: projectId == null ? null : app.read<Orchestrator>(),
    );
  });
}

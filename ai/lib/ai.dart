/// AI 프로젝트 검사(D). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_ai/ai.dart' as ai;`
///
/// Gemini API 는 이 패키지의 [GeminiLlmClient] 한 곳에서만 부른다.
/// 보낼 때는 [AiSender] 로 비밀값을 가리고 보내기 전 확인 창을 거친다.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:popoling_core/contracts.dart';

import 'src/ai_screen.dart';
import 'src/app_settings_screen.dart';
import 'src/analysis_history.dart';
import 'src/api_key_store.dart';
import 'src/gemini_client.dart';

export 'src/ai_sender.dart' show AiSender;
export 'src/analysis_history.dart' show AnalysisHistory, AnalysisHistoryCorrupt, AnalysisKind, AnalysisOutcome, AnalysisRecord;
export 'src/api_key_dialog.dart' show ApiKeyChange, ApiKeyCheck, ApiKeyDialog, showApiKeyDialog;
export 'src/api_key_store.dart' show ApiKeyStore, MemoryApiKeyStore, SecureApiKeyStore;
export 'src/failure_analysis_panel.dart' show FailureAnalysisPanel, failureAnalysisDescription, failureAnalysisRequestName;
export 'src/gemini_client.dart' show GeminiFetch, GeminiHttpResponse, GeminiLlmClient, GeminiTransport;
export 'src/messages.dart' show LlmErrorText, llmErrorText;
export 'src/qa_summary_panel.dart' show QaSummaryPanel, qaSummaryRequestName;
export 'src/send_confirm_dialog.dart' show SendConfirmDialog;

/// AI 프로젝트 검사의 화면과 구현을 앱에 등록한다.
///
/// API 키는 사용자가 앱에서 넣고 이 컴퓨터의 보안 저장소에만 둔다. 앱 빌드에는 키를 넣지 않는다.
/// AI 검사(`/ai`) 화면은 키 상태와 분석 기록을 보여 준다. 분석 기록([AnalysisHistory])도 등록해,
/// 프로젝트 화면의 패널이 결과를 남길 수 있게 한다(`app/` 이 패널의 `onRecord` 에 연결).
void register(AppRegistry app) {
  final keys = SecureApiKeyStore();
  final gemini = GeminiLlmClient(keys: keys);
  final history = AnalysisHistory(() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}ai-history.json'));
  app.provide<LlmClient>(gemini);
  app.provide<AnalysisHistory>(history);
  // 키는 늘 Gemini 키라, 나중에 LlmClient 를 바꿔 끼워도 [연결 확인]은 Gemini 로 한다.
  app.route('/ai', (_) => AiScreen(keys: keys, client: app.read<LlmClient>(), checkKey: gemini.checkKey, history: app.read<AnalysisHistory>()));
  // 왼쪽 메뉴 [앱 설정](#105). 지금은 API 키만 둔다.
  app.route('/app-settings', (_) => AppSettingsScreen(keys: keys, client: app.read<LlmClient>(), checkKey: gemini.checkKey));
}

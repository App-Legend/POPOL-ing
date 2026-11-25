import 'package:flutter/widgets.dart';
import 'package:popoling_ai/ai.dart' as ai;
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 화면 6(QA 결과) 아래 [AI 요약] 자리에 넣을 위젯(AI-03).
///
/// 화면 6은 `ai/` 를 모르므로 `app/` 이 이 함수를 넘겨 채운다. 구현은 등록이 끝난 뒤 그릴 때 꺼낸다.
Widget Function(BuildContext context, QaRun run) qaSummarySlot(AppRegistry app) {
  final keys = ai.SecureApiKeyStore();
  final checkKey = ai.GeminiLlmClient(keys: keys).checkKey;
  return (_, run) => Panel(
        title: 'AI 요약',
        child: ai.QaSummaryPanel(
          run: run,
          client: app.read<LlmClient>(),
          keys: keys,
          qa: app.read<QaRunner>(),
          orchestrator: app.read<Orchestrator>(),
          checkKey: checkKey,
        ),
      );
}

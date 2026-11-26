import 'package:popoling_ai/ai.dart' as ai;
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 프로젝트 화면 안의 AI 자리(AI-02 실패 원인 분석, AI-03 헬스체크 요약).
///
/// `runner` 는 `ai/` 를 모르므로 `app/` 이 채워 [ProjectPanels] 로 넘긴다. 구현은 등록이 끝난 뒤 그릴 때 꺼낸다.
ProjectPanels projectPanels(AppRegistry app) {
  final keys = ai.SecureApiKeyStore();
  final checkKey = ai.GeminiLlmClient(keys: keys).checkKey;
  T? tryRead<T extends Object>() {
    try {
      return app.read<T>();
    } on StateError {
      return null; // 아직 붙지 않은 기능(예: EnvDiff)은 그 칸 없이 분석한다
    }
  }

  return ProjectPanels(
    failure: (_, item, run) => Panel(
      title: '${item.item.serviceId}이 실패한 이유',
      child: ai.FailureAnalysisPanel(
        item: item,
        run: run,
        client: app.read<LlmClient>(),
        keys: keys,
        projects: app.read<ProjectRepository>(),
        logs: tryRead<LogExcerpt>(),
        envDiff: tryRead<EnvDiff>(),
        checkKey: checkKey,
      ),
    ),
    qaSummary: (_, run) => Panel(
      title: 'AI 요약',
      child: ai.QaSummaryPanel(
        run: run,
        client: app.read<LlmClient>(),
        keys: keys,
        qa: app.read<QaRunner>(),
        orchestrator: app.read<Orchestrator>(),
        checkKey: checkKey,
      ),
    ),
  );
}

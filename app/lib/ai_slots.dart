import 'dart:async';

import 'package:flutter/widgets.dart';

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

  // 기록을 못 남겨도(파일 깨짐 등) 분석 화면은 그대로 둔다. 기록 화면이 따로 알린다.
  void record(ai.AnalysisRecord r) => unawaited(tryRead<ai.AnalysisHistory>()?.add(r).catchError((Object _) {}));

  return ProjectPanels(
    failure: (_, item, run) => Panel(
      title: '${item.item.serviceId}이 실패한 이유',
      danger: true,
      // 실행기가 준 원인으로 만든 실패 안내 카드(#89)를 먼저 보인다. AI 분석은 키가 없으면 "API 키 필요"만 나오기 때문.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        ai.FailureGuideCard(item: item, runner: app.read<Orchestrator>()),
        ai.FailureAnalysisPanel(
          item: item,
          run: run,
          client: app.read<LlmClient>(),
          keys: keys,
          projects: app.read<ProjectRepository>(),
          logs: tryRead<LogExcerpt>(),
          envDiff: tryRead<EnvDiff>(),
          checkKey: checkKey,
          onRecord: record,
        ),
      ]),
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
        onRecord: record,
      ),
    ),
  );
}

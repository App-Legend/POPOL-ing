import 'package:flutter/widgets.dart';

import '../models.dart';

/// 프로젝트 화면 안의 끼울 자리. 다른 기능의 위젯이라 `app/` 이 채워 `provide` 한다. 없으면 자리를 숨긴다.
class ProjectPanels {
  const ProjectPanels({this.failure, this.qaSummary});

  /// 실패한 항목의 안내 자리(로그 탭 위). 예: AI-02 원인 분석.
  final Widget Function(BuildContext context, ItemResult item, RunSummary run)? failure;

  /// 헬스체크 결과 아래 [AI 요약] 자리(AI-03).
  final Widget Function(BuildContext context, QaRun run)? qaSummary;
}

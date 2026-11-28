import 'package:flutter/widgets.dart';

/// 프로젝트 화면에 끼우는 탭 하나. 기능이 `register()` 에서 [AppRegistry.tab] 으로 등록한다.
///
/// 순서: 로그 0(runner) · 환경 점검 10(checks) · Git 20(runner) · 설정 30(project).
class ProjectTab {
  const ProjectTab({required this.id, required this.label, required this.order, required this.build, this.badge});

  /// 같은 id 를 다시 등록하면 나중 것이 이긴다.
  final String id;

  /// 탭 이름. 예: `환경 점검`
  final String label;

  /// 작을수록 앞.
  final int order;

  /// 탭 내용을 그린다.
  final Widget Function(BuildContext context, String projectId) build;

  /// 탭 옆에 보일 문제 수. 0 이면 숨긴다. null 이면 배지 없음.
  final Stream<int> Function(String projectId)? badge;
}

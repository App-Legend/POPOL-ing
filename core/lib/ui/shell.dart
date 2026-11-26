import 'package:flutter/widgets.dart';

/// 왼쪽 메뉴 아래 "지금 상태" 자리. `app/` 이 앱 맨 위에서 채운다(실패·오래된 프로젝트 목록).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.status, required super.child});

  final Widget? status;

  static Widget? statusOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()?.status;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => status != oldWidget.status;
}

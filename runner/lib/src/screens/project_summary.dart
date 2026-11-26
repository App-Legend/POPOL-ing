import 'dart:ui';

import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 프로젝트 요약 상태(기획서 v1.4 §6). 준비 완료·연결됨을 센다.
({String label, (Color, Color) tone}) projectSummary(List<ItemState> states) {
  final n = states.length;
  if (n == 0) return (label: '실행 항목 없음', tone: C.idle);
  final k = states.where((s) => s == ItemState.ready || s == ItemState.connected).length;
  if (states.any((s) => s == ItemState.failed || s == ItemState.portBusy || s == ItemState.disconnected)) {
    return (label: '일부 실패 · $k/$n', tone: C.bad);
  }
  if (states.any((s) => s == ItemState.starting || s == ItemState.running)) return (label: '시작 중 · $k/$n', tone: C.warn);
  if (k == n) return (label: '실행 중 · $n/$n', tone: C.ok);
  return (label: '중지', tone: C.idle);
}

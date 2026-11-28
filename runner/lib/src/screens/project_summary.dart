import 'dart:ui';

import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 프로젝트 요약 상태(기획서 v1.4 §6). 위에서부터 먼저 맞는 하나. 준비 완료·연결됨을 센다.
/// shortcut: `확인 필요`는 원격 연결 안 됨만 본다. Docker 꺼짐은 #110 에서 더한다.
({String label, (Color, Color) tone}) projectSummary(List<ItemState> states) {
  final n = states.length;
  if (n == 0) return (label: '실행 항목 없음', tone: C.idle);
  final k = states.where((s) => s == ItemState.ready || s == ItemState.connected).length;
  if (states.contains(ItemState.disconnected)) return (label: '확인 필요', tone: C.warn);
  if (states.any((s) => s.isFailure || s == ItemState.portBusy)) return (label: '일부 실패 · $k/$n', tone: C.bad);
  if (states.any(isStarting)) return (label: '시작 중 · $k/$n', tone: C.warn);
  if (k > 0) return (label: '실행 중 · $k/$n', tone: C.ok);
  return (label: '중지', tone: C.idle);
}

/// 전체 실행이 진행 중이거나 준비 전인 상태(`시작 중` 요약).
bool isStarting(ItemState s) => s == ItemState.starting || s == ItemState.running || s == ItemState.waiting;

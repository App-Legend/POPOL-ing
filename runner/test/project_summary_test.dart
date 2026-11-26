import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_runner/src/screens/project_summary.dart';

void main() {
  test('일부 실패', () => expect(projectSummary([ItemState.ready, ItemState.ready, ItemState.failed, ItemState.connected]).label, '일부 실패 · 3/4'));
  test('모두 실행 중', () => expect(projectSummary(List.filled(4, ItemState.ready)).label, '실행 중 · 4/4'));
  test('시작 중', () => expect(projectSummary([ItemState.ready, ItemState.starting]).label, '시작 중 · 1/2'));
  test('중지', () => expect(projectSummary([ItemState.stopped, ItemState.stopped]).label, '중지'));
  test('항목 없음', () => expect(projectSummary([]).label, '실행 항목 없음'));
}

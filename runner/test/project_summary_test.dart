import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_runner/src/screens/project_summary.dart';

void main() {
  test('일부 실패', () => expect(projectSummary([ItemState.ready, ItemState.ready, ItemState.failed, ItemState.connected]).label, '일부 실패 · 3/4'));
  test('모두 실행 중', () => expect(projectSummary(List.filled(4, ItemState.ready)).label, '실행 중 · 4/4'));
  test('시작 중', () => expect(projectSummary([ItemState.ready, ItemState.starting]).label, '시작 중 · 1/2'));
  test('일부만 실행 중', () => expect(projectSummary([ItemState.ready, ItemState.stopped, ItemState.stopped, ItemState.stopped]).label, '실행 중 · 1/4'));
  test('중지', () => expect(projectSummary([ItemState.stopped, ItemState.stopped]).label, '중지'));
  test('세 가지 실패는 모두 일부 실패', () {
    for (final f in [ItemState.startFailed, ItemState.readyTimeout, ItemState.crashed]) {
      expect(projectSummary([ItemState.ready, f]).label, '일부 실패 · 1/2', reason: '$f');
    }
  });
  test('원격 연결 안 됨이면 실패보다 먼저 확인 필요',
      () => expect(projectSummary([ItemState.disconnected, ItemState.crashed, ItemState.ready]).label, '확인 필요'));
  test('대기 중이면 시작 중', () => expect(projectSummary([ItemState.ready, ItemState.waiting]).label, '시작 중 · 1/2'));
  test('건너뜀만 남으면 중지', () => expect(projectSummary([ItemState.skipped, ItemState.stopped]).label, '중지'));
  test('항목 없음', () => expect(projectSummary([]).label, '실행 항목 없음'));
}

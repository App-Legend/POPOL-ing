import '../models/item_ref.dart';
import '../models/run.dart';

/// 실행 제어(A)가 내보내는 이벤트. `Orchestrator.events` 로 받고 `switch` 로 나눈다.
sealed class RunEvent {
  const RunEvent();
}

/// 항목 하나의 상태가 바뀌었다. 대시보드·항목 상세가 상태 배지를 바꾸는 데 쓴다.
final class ItemStateChanged extends RunEvent {
  const ItemStateChanged(this.item, this.state, {this.reason, this.exitCode});

  final ItemRef item;
  final ItemState state;

  /// [ItemState.failed]·[ItemState.disconnected] 일 때의 이유. 화면에 그대로 보여줄 수 있는 문장.
  final String? reason;

  /// 프로세스가 끝나 [ItemState.stopped]·[ItemState.failed] 가 됐을 때의 종료 코드.
  final int? exitCode;
}

/// 전체 실행이 모든 항목 성공으로 끝났다. C 는 이때 "마지막 성공 환경"을 저장한다(FR-16).
final class RunSucceeded extends RunEvent {
  const RunSucceeded(this.summary);

  final RunSummary summary;
}

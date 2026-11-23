import 'item_ref.dart';

/// 실행 항목의 지금 상태(기획서 §6 상태 전이). 화면에는 색과 함께 아래 라벨을 쓴다.
enum ItemState {
  /// 중지
  stopped,

  /// 시작 중: 프로세스·컨테이너를 만드는 중.
  starting,

  /// 실행 중: 떠 있지만 준비 조건을 아직 못 채웠다.
  running,

  /// 준비 완료
  ready,

  /// 종료 중
  stopping,

  /// 실패: 시작 실패, 비정상 종료, 준비 시간 초과.
  failed,

  /// 연결됨: 원격 항목 전용.
  connected,

  /// 연결 안 됨: 원격 항목 전용.
  disconnected,

  /// 포트 사용 중: 시작 전 포트 점검에서 걸려 시작하지 않았다.
  portBusy,

  /// 확인 불가: 앱 재시작 후 소유권을 검증할 수 없는 실행 기록.
  unknown,
}

/// 전체 실행·종료에서 항목 하나의 결과. 결과 요약의 성공 / 실패 / 건너뜀이다.
enum ItemOutcome {
  /// 성공: 실행이면 준비 완료(원격은 연결됨), 종료면 멈춤.
  ok,

  /// 실패
  failed,

  /// 건너뜀: 의존하는 항목이 실패해 시작하지 않았다(AT-04).
  skipped,
}

/// 항목 하나의 결과.
class ItemResult {
  const ItemResult({required this.item, required this.outcome, this.reason, this.exitCode, this.forced = false});

  final ItemRef item;
  final ItemOutcome outcome;

  /// 실패·건너뜀의 이유. 화면에 그대로 보여줄 수 있는 문장. 예: `준비 시간(60초)을 넘겼어요.`
  final String? reason;

  /// 프로세스가 끝났을 때의 종료 코드. 모르면 null.
  final int? exitCode;

  /// 종료 신호 뒤 `stopTimeout` 안에 멈추지 않아 강제 종료했다(전체 종료 결과에 표시).
  final bool forced;
}

/// 전체 실행 전에 최신 코드를 받은(Git pull) 결과(FR-19). 받지 못해도 실행은 계속한다.
class PullResult {
  const PullResult({required this.outcome, required this.message});

  /// [ItemOutcome.ok] 면 받았거나 받을 새 커밋이 없음, [ItemOutcome.skipped] 면 받지 않았다.
  final ItemOutcome outcome;

  /// 화면에 그대로 보여줄 수 있는 문장.
  final String message;
}

/// 전체 실행 또는 전체 종료 한 번의 결과.
class RunSummary {
  RunSummary(
      {required this.projectId, required this.startedAt, required this.finishedAt, required List<ItemResult> items, this.pull})
      : items = List.unmodifiable(items);

  final String projectId;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// 처리한 순서대로. 전체 종료에서 원격 항목은 건드리지 않으므로 들어가지 않는다.
  final List<ItemResult> items;

  /// 실행 전에 최신 코드를 받은 결과. 받기를 껐거나 Git 저장소가 아니거나 전체 종료면 null.
  final PullResult? pull;

  /// 모든 항목이 성공했다. [pull] 은 따지지 않는다.
  bool get succeeded => items.every((r) => r.outcome == ItemOutcome.ok);
}

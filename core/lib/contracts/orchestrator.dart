import '../events/run_events.dart';
import '../models/errors.dart';
import '../models/item_ref.dart';
import '../models/run.dart';

/// 항목 시작·중지(FR-03), 전체 실행(FR-04), 전체 종료(FR-05). 정책은 기획서 §6.
///
/// - 진짜 구현: A (`runner/`)
/// - 쓰는 곳: `app/` 대시보드·항목 상세, C(포트 알림의 [그 항목 중지], [RunSucceeded] 로 환경 기록),
///   D(카드의 [전체 실행]·마지막 실행, 오래된 프로젝트 점검, AI-02·03 실행 요약)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [orchestratorContract] 로 확인한다.
/// 1. 전체 실행은 `dependsOn` 순서를 지킨다. 항목은 의존하는 항목이 모두 성공한 뒤에 시작한다.
/// 2. 항목이 실패하면 그 항목에 의존하는 항목은 시작하지 않고 [ItemOutcome.skipped] 다.
///    나머지 독립 항목은 계속하고, 이미 시작한 항목은 자동으로 멈추지 않는다.
/// 3. 원격 항목은 켜지 않고 연결만 확인한다. 연결 안 됨은 실패와 같이 처리한다. 전체 종료에서는 건드리지 않는다.
/// 4. 전체 종료는 실행의 역순으로, 포폴링이 띄운 항목만 멈춘다.
/// 5. 상태가 바뀔 때마다 [ItemStateChanged] 를 보낸다. 전체 실행이 모두 성공하면 끝에 [RunSucceeded] 를 한 번 보낸다.
/// 6. 등록되지 않은 프로젝트면 [ProjectNotFoundException], 프로젝트에 없는 항목이면 [ArgumentError].
///    항목의 실패는 예외가 아니라 결과([ItemResult]·[ItemState.failed])로 알린다.
abstract interface class Orchestrator {
  /// 모든 프로젝트의 상태 변화와 전체 실행 성공. 여러 곳에서 동시에 구독할 수 있다.
  Stream<RunEvent> get events;

  /// [item] 의 지금 상태. 한 번도 띄우지 않았으면 [ItemState.stopped].
  ItemState stateOf(ItemRef item);

  /// 프로젝트 전체 실행. 모든 항목의 결과가 정해지면(준비 완료·실패·건너뜀) 끝난다.
  /// 이미 준비 완료인 항목은 다시 띄우지 않고 성공으로 친다.
  Future<RunSummary> runAll(String projectId);

  /// 프로젝트 전체 종료. 모든 항목이 멈추면 끝난다.
  Future<RunSummary> stopAll(String projectId);

  /// 항목 하나를 시작하고 준비 완료·실패가 정해질 때까지 기다린다. 의존 항목은 함께 띄우지 않는다.
  Future<ItemResult> start(ItemRef item);

  /// 항목 하나를 멈춘다(전체 종료와 같은 종료 절차). 이미 멈췄으면 아무것도 하지 않고 성공이다.
  Future<ItemResult> stop(ItemRef item);

  /// 이 프로젝트의 마지막 전체 실행 결과. 한 번도 없으면 null. 카탈로그 카드의 마지막 실행일·결과에 쓴다.
  Future<RunSummary?> lastRun(String projectId);
}

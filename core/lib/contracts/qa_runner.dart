import '../models/errors.dart';
import '../models/qa.dart';

/// 기본 QA(FR-10). 프로젝트 설정의 checks 를 검사하고 결과를 이력으로 남긴다.
///
/// - 진짜 구현: D (`qa/`). HTTP·포트 확인은 직접 하지 않고 C 의 계약을 부른다.
/// - 쓰는 곳: A(대시보드 [헬스체크]), D(QA 결과 화면, 오래된 프로젝트 점검)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [qaRunnerContract] 로 확인한다.
/// - 결과는 ppoling.yaml 의 checks 와 같은 순서다. 하나가 실패해도 나머지를 계속 검사한다.
/// - 주소(url·port)가 없는 check 는 검사하지 않고 [QaStatus.needsSetup] 으로 둔다.
/// - 검사할 때마다 이력에 남긴다. 앱을 다시 켜도 남아 있어야 한다.
abstract interface class QaRunner {
  /// 프로젝트의 checks 를 모두 검사한다. 없는 프로젝트면 [ProjectNotFoundException].
  Future<QaRun> runChecks(String projectId, {QaTrigger trigger = QaTrigger.manual});

  /// 지금까지의 검사 이력. 최근 것이 앞에 온다. 검사한 적이 없으면 빈 목록.
  Future<List<QaRun>> history(String projectId);
}

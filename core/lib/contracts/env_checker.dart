import '../models/env_check.dart';
import '../models/requirement.dart';

/// 환경 점검(FR-07). ppoling.yaml 의 `requires` 를 검사한다.
///
/// - 진짜 구현: C (`checks/`)
/// - 쓰는 곳: C(화면 5 환경 점검), A(전체 실행 전 확인, Docker 꺼짐이면 Compose 시작 막기),
///   D(오래된 프로젝트 점검)
///
/// 버전 범위(`CliRequirement.version`)는 공백으로 이은 조건을 모두 만족해야 한다.
/// 조건은 `>=`, `>`, `<=`, `<`, `=` 뒤에 버전을 쓰고, 연산자가 없으면 `=` 다.
/// 비교할 때 빠진 자리는 0 으로 보되, `=` 는 적은 자리까지만 비교한다(`20` 은 20.x 전부).
/// 예: `>=20`, `>=17 <22`, `20`, `=20.11.1`
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [envCheckerContract] 로 확인한다.
/// - 결과는 받은 목록과 같은 순서·같은 개수다. 하나가 실패해도 나머지를 계속 검사한다.
/// - 점검 중 문제는 예외 대신 [EnvStatus] 로 돌려준다.
abstract interface class EnvChecker {
  Future<List<EnvCheckResult>> check(List<Requirement> requires);
}

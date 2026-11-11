import '../models/config_issue.dart';
import '../models/project_config.dart';

/// 설정 항목 사이의 관계를 검사한다(FR-02, AT-10).
///
/// 형식(필수값, 타입, 허용 값)은 [ProjectConfig.fromMap] 이 먼저 거른다. 여기서는 형식은
/// 맞지만 항목끼리 어긋나는 것을 찾는다.
///
/// - 진짜 구현: B (`project/`) · 계약과 가짜 구현: D
/// - 쓰는 곳: B(설정 화면에서 저장하기 전), A(실행하기 전)
///
/// 찾아야 하는 문제와 그 위치([ConfigIssue.path]):
/// - 실행 항목 id 중복 → 뒤에 나온 항목의 `services[i].id`
/// - dependsOn 에 없는 id → `services[i].dependsOn[j]`
/// - 순환 의존(자기 자신 포함) → 순환에 든 항목의 `services[i].dependsOn`
///
/// 문제가 없으면 빈 목록을 돌려준다. 예외를 던지지 않는다.
abstract interface class ConfigValidator {
  List<ConfigIssue> validate(ProjectConfig config);
}

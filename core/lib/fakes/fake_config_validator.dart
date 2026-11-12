import '../contracts/config_validator.dart';
import '../models/config_issue.dart';
import '../models/project_config.dart';

/// [ConfigValidator] 의 가짜 구현. 규칙을 검사하지 않고 [issues] 에 넣어 둔 문제를 그대로 돌려준다.
///
/// 설정 화면이 오류를 어떻게 보여주는지 개발할 때 쓴다.
/// ```dart
/// final validator = FakeConfigValidator(issues: [
///   ConfigIssue(path: 'services[1].dependsOn[0]', message: '없는 항목이에요: dbb'),
/// ]);
/// ```
class FakeConfigValidator implements ConfigValidator {
  FakeConfigValidator({List<ConfigIssue> issues = const []}) : issues = [...issues];

  /// 돌려줄 문제. 테스트 중에 바꿔도 된다.
  List<ConfigIssue> issues;

  /// 지금까지 검사를 맡긴 설정. "저장 전에 검사를 불렀는지" 확인할 때 쓴다.
  final List<ProjectConfig> validated = [];

  @override
  List<ConfigIssue> validate(ProjectConfig config) {
    validated.add(config);
    return List.unmodifiable(issues);
  }
}

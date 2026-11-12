import 'package:flutter_test/flutter_test.dart';

import '../contracts/config_validator.dart';
import '../fakes/sample_projects.dart';
import '../models/config_issue.dart';
import '../models/project_config.dart';
import '../models/service_config.dart';

/// [ConfigValidator] 구현이 계약을 지키는지 확인하는 테스트 묶음.
///
/// - 기본 약속(올바른 설정이면 문제 없음, 예외를 던지지 않음)은 가짜 구현도 지킨다.
/// - [checkRules] 를 켜면 규칙(중복 id, 없는 의존 대상, 순환 의존)까지 확인한다.
///   가짜 구현은 규칙을 검사하지 않으므로 진짜 구현에서만 켠다.
/// ```dart
/// group('SchemaConfigValidator', () {
///   configValidatorContract(() => SchemaConfigValidator(), checkRules: true);
/// });
/// ```
void configValidatorContract(ConfigValidator Function() create, {bool checkRules = false}) {
  test('올바른 설정이면 문제가 없다', () {
    final config = SampleProjects.myTeamProject.config!;
    expect(create().validate(config), isEmpty);
  });

  test('실행 항목이 없는 설정도 문제가 없고, 예외를 던지지 않는다', () {
    expect(create().validate(const ProjectConfig()), isEmpty);
  });

  if (!checkRules) {
    return;
  }

  List<String> paths(List<ConfigIssue> issues) => [for (final i in issues) i.path];

  ProcessService service(String id, {List<String> dependsOn = const []}) =>
      ProcessService(id: id, command: const ['run'], dependsOn: dependsOn);

  test('규칙: id 가 겹치면 뒤에 나온 항목의 id 를 알린다', () {
    final issues = create().validate(ProjectConfig(services: [service('api'), service('api')]));
    expect(paths(issues), contains('services[1].id'));
  });

  test('규칙: dependsOn 에 없는 id 가 있으면 그 칸을 알린다', () {
    final issues = create().validate(ProjectConfig(services: [
      service('db'),
      service('web', dependsOn: ['db', 'api']),
    ]));
    expect(paths(issues), contains('services[1].dependsOn[1]'));
  });

  test('규칙: 순환 의존을 알린다', () {
    final issues = create().validate(ProjectConfig(services: [
      service('a', dependsOn: ['b']),
      service('b', dependsOn: ['a']),
    ]));
    expect(paths(issues), anyOf(contains('services[0].dependsOn'), contains('services[1].dependsOn')));
  });

  test('규칙: 자기 자신에 의존하면 순환으로 알린다', () {
    final issues = create().validate(ProjectConfig(services: [service('a', dependsOn: ['a'])]));
    expect(paths(issues), contains('services[0].dependsOn'));
  });

  test('규칙: 모든 문제는 위치와 안내 문장을 가진다', () {
    final issues = create().validate(ProjectConfig(services: [service('a', dependsOn: ['x']), service('a')]));
    expect(issues, isNotEmpty);
    for (final issue in issues) {
      expect(issue.path, isNotEmpty);
      expect(issue.message, isNotEmpty);
    }
  });
}

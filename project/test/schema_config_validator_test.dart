import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/models.dart';
import 'package:ppoling_core/testing.dart';
import 'package:ppoling_project/src/schema_config_validator.dart';

void main() {
  group('SchemaConfigValidator', () {
    configValidatorContract(() => const SchemaConfigValidator(), checkRules: true);
  });

  ProcessService service(String id, [List<String> dependsOn = const []]) =>
      ProcessService(id: id, command: const ['run'], dependsOn: dependsOn);

  List<String> paths(List<ConfigIssue> issues) => [for (final i in issues) i.path];

  test('세 항목이 도는 순환은 셋 다 알린다', () {
    final issues = const SchemaConfigValidator().validate(ProjectConfig(services: [
      service('a', ['b']),
      service('b', ['c']),
      service('c', ['a']),
      service('d', ['a']),
    ]));
    expect(paths(issues), ['services[0].dependsOn', 'services[1].dependsOn', 'services[2].dependsOn']);
  });

  test('여러 항목이 같은 항목을 기다리는 건 순환이 아니다', () {
    final issues = const SchemaConfigValidator().validate(ProjectConfig(services: [
      service('web', ['api', 'auth']),
      service('api', ['db']),
      service('auth', ['db']),
      service('db'),
    ]));
    expect(issues, isEmpty);
  });
}

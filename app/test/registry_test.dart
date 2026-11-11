import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling/main.dart';
import 'package:ppoling/registry.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';

void main() {
  test('나중에 등록한 구현이 가짜를 덮어쓴다', () {
    final app = Registry();
    final fake = FakeConfigValidator();
    final real = FakeConfigValidator(issues: const []);
    app.provide<ConfigValidator>(fake);
    app.provide<ConfigValidator>(real);
    expect(app.read<ConfigValidator>(), same(real));
  });

  test('등록하지 않은 타입을 꺼내면 StateError', () {
    expect(() => Registry().read<QaRunner>(), throwsStateError);
  });

  test('기본 조립에는 가짜 구현과 목업 화면 9개가 들어 있다', () {
    final app = buildRegistry();
    expect(app.read<ProjectRepository>(), isA<FakeProjectRepository>());
    expect(app.read<QaRunner>(), isA<FakeQaRunner>());
    expect(app.routes.keys, containsAll(['/', '/home', '/dashboard', '/qa']));
  });
}

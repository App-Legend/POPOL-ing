import 'package:flutter_test/flutter_test.dart';
import 'package:popoling/main.dart';
import 'package:popoling/registry.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';

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

  test('가짜 조립에는 가짜 구현과 목업 화면 9개가 들어 있다', () {
    final app = buildRegistry(features: false);
    expect(app.read<ProjectRepository>(), isA<FakeProjectRepository>());
    expect(app.read<QaRunner>(), isA<FakeQaRunner>());
    expect(app.read<HttpProbe>(), isA<FakeHttpProbe>());
    expect(app.routes.keys, containsAll(['/', '/home', '/dashboard', '/qa']));
  });

  test('기본 조립은 기능 패키지의 진짜 구현으로 바꿔 끼운다', () {
    final app = buildRegistry();
    expect(app.read<ProjectRepository>(), isNot(isA<FakeProjectRepository>()));
    expect(app.read<ConfigValidator>(), isNot(isA<FakeConfigValidator>()));
    expect(app.read<ItemLauncher>(), isNot(isA<FakeItemLauncher>()));
    expect(app.read<LlmClient>(), isNot(isA<FakeLlmClient>()));
    expect(app.read<HttpProbe>(), isNot(isA<FakeHttpProbe>()));
    expect(app.read<Orchestrator>(), isNot(isA<FakeOrchestrator>()));
  });

  test('가짜 Orchestrator 는 바꿔 끼운 ProjectRepository 의 프로젝트를 본다', () async {
    final app = buildRegistry(features: false);
    final real = FakeProjectRepository(existingFolders: ['/projects/new']);
    app.provide<ProjectRepository>(real);
    final added = await real.addProject('/projects/new');
    expect(await app.read<Orchestrator>().lastRun(added.id), isNull); // 옛 저장소를 보면 ProjectNotFoundException
  });
}

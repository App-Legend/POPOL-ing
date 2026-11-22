import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/ai.dart' as ai;
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/ui.dart';

/// `app/` 의 Registry 와 같은 규칙(나중에 등록한 것이 이긴다)의 테스트용 구현.
class TestRegistry implements AppRegistry {
  final Map<String, WidgetBuilder> routes = {};
  final Map<Type, Object> _services = {};

  @override
  void route(String path, WidgetBuilder builder) => routes[path] = builder;

  @override
  void provide<T extends Object>(T service) => _services[T] = service;

  @override
  T read<T extends Object>() => _services[T]! as T;
}

Future<void> openAi(WidgetTester tester, TestRegistry app) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), routes: app.routes, initialRoute: '/ai'));
  await tester.pumpAndSettle();
}

void main() {
  test('Gemini 연결과 AI 검사 화면(/ai)을 등록한다', () {
    final app = TestRegistry()..provide<LlmClient>(FakeLlmClient());
    ai.register(app);
    expect(app.read<LlmClient>(), isA<ai.GeminiLlmClient>());
    expect(app.routes.keys, contains('/ai'));
  });

  testWidgets('/ai 는 OS 보안 저장소에 둔 키를 읽어 보여 준다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'gemini_api_key': 'AQ.from-keychain-9876'});
    final app = TestRegistry();
    ai.register(app);
    await openAi(tester, app);
    expect(find.text('${ai.GeminiLlmClient.defaultModel} · 키 ••••••••9876'), findsOneWidget);
    await tester.tap(find.text('키 바꾸기'));
    await tester.pumpAndSettle();
    expect(find.text('연결 확인'), findsOneWidget, reason: 'Gemini 로 키를 확인할 수 있다');
  });

  testWidgets('/ai 는 register 뒤에 바꿔 끼운 LlmClient 의 모델 이름을 쓴다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'gemini_api_key': 'AQ.from-keychain-9876'});
    final app = TestRegistry();
    ai.register(app);
    app.provide<LlmClient>(FakeLlmClient(modelName: 'local-model'));
    await openAi(tester, app);
    expect(find.text('local-model · 키 ••••••••9876'), findsOneWidget);
  });

  testWidgets('/ai 에 프로젝트 ID 를 넘기면 등록된 QaRunner·Orchestrator 로 헬스체크 결과 요약 카드를 그린다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'gemini_api_key': 'AQ.from-keychain-9876'});
    final projects = FakeProjectRepository.withSamples();
    final qa = FakeQaRunner(projects, failing: {'API 헬스'});
    await qa.runChecks('my-team-project');
    final app = TestRegistry()
      ..provide<QaRunner>(qa)
      ..provide<Orchestrator>(FakeOrchestrator(projects));
    ai.register(app);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      routes: app.routes,
      home: Builder(builder: (c) => Btn('열기', onPressed: () => Navigator.pushNamed(c, '/ai', arguments: 'my-team-project'))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('헬스체크 결과 요약'), findsOneWidget);
    expect(find.text('AI 요약'), findsOneWidget);
  });
}

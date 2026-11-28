import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart' as ai;
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

/// `app/` 의 Registry 와 같은 규칙(나중에 등록한 것이 이긴다)의 테스트용 구현.
class TestRegistry implements AppRegistry {
  final Map<String, WidgetBuilder> routes = {};
  final Map<Type, Object> _services = {};
  final Map<String, ProjectTab> _tabs = {};

  @override
  void tab(ProjectTab tab) => _tabs[tab.id] = tab;

  @override
  List<ProjectTab> get tabs => _tabs.values.toList()..sort((a, b) => a.order.compareTo(b.order));

  @override
  void route(String path, WidgetBuilder builder) => routes[path] = builder;

  @override
  void provide<T extends Object>(T service) => _services[T] = service;

  @override
  T read<T extends Object>() {
    final service = _services[T];
    if (service == null) {
      throw StateError('$T 구현이 등록되지 않았습니다.'); // app/ 의 Registry 와 같게
    }
    return service as T;
  }
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
    expect(app.routes.keys, contains('/app-settings'));
    expect(app.read<ai.AnalysisHistory>(), isA<ai.AnalysisHistory>());
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
}

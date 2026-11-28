import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/catalog.dart' as catalog;
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
  T read<T extends Object>() => _services[T] as T? ?? (throw StateError('$T 가 등록되지 않았어요')); // AppRegistry 계약대로
}

/// 가짜를 먼저 깔고 catalog 를 등록한다(app/ 의 순서).
({TestRegistry app, FakeProjectRepository repo, FakeOrchestrator runner}) setUpApp() {
  final app = TestRegistry();
  final repo = FakeProjectRepository.withSamples();
  final runner = FakeOrchestrator(repo);
  app
    ..provide<ProjectRepository>(repo)
    ..provide<Orchestrator>(runner);
  catalog.register(app);
  return (app: app, repo: repo, runner: runner);
}

/// 쌓인 화면 이름을 센다.
class PushLog extends NavigatorObserver {
  final pushed = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

Future<void> openApp(WidgetTester tester, TestRegistry app, {String initialRoute = '/', NavigatorObserver? observer}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), routes: app.routes,
      initialRoute: initialRoute,
      // 처음 화면 하나만 쌓는다(기본은 '/home' 이면 '/' 위에 쌓는다).
      onGenerateInitialRoutes: (name) => [MaterialPageRoute(settings: RouteSettings(name: name), builder: app.routes[name]!)],
      navigatorObservers: [?observer]));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AT-16: 앱을 열면 카테고리 선택 화면이 나온다', (tester) async {
    final (:app, repo: _, runner: _) = setUpApp();
    await openApp(tester, app);
    expect(find.text('어떤 포트폴리오를 관리할까요?'), findsOneWidget);
    expect(find.text('프로젝트 5개'), findsOneWidget);
    expect(find.textContaining('실행 중'), findsNothing, reason: '실행 중인 프로젝트가 없으면 칩을 뺀다');
  });

  testWidgets('AT-16: 개발 카드를 누르면 개발 홈으로', (tester) async {
    final (:app, repo: _, runner: _) = setUpApp();
    await openApp(tester, app);
    await tester.tap(find.byKey(const Key('category-dev')));
    await tester.pumpAndSettle();
    expect(find.text('내 프로젝트  5'), findsOneWidget);
  });

  testWidgets('AT-16: 홈 위에서 연 카테고리 선택의 개발 카드는 홈을 또 쌓지 않고 돌아간다', (tester) async {
    final (:app, repo: _, runner: _) = setUpApp();
    final log = PushLog();
    await openApp(tester, app, initialRoute: '/home', observer: log);
    await tester.tap(find.text('카테고리 · 개발'));
    await tester.pumpAndSettle();
    expect(find.text('어떤 포트폴리오를 관리할까요?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category-dev')));
    await tester.pumpAndSettle();
    expect(find.text('내 프로젝트  5'), findsOneWidget);
    expect(log.pushed.where((n) => n == '/home'), hasLength(1), reason: '처음 연 홈으로 돌아가고 새로 쌓지 않는다');
  });

  testWidgets('실행 중인 프로젝트 수를 보여 준다', (tester) async {
    final (:app, repo: _, :runner) = setUpApp();
    await runner.runAll('popoling');
    await openApp(tester, app);
    expect(find.text('실행 중 1개'), findsOneWidget);
  });

  testWidgets('개발 홈 카드는 A 의 마지막 전체 실행을 보여 준다', (tester) async {
    final (:app, repo: _, :runner) = setUpApp();
    await runner.runAll('popoling');
    await runner.stopAll('popoling');
    await openApp(tester, app);
    await tester.tap(find.byKey(const Key('category-dev')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('catalog-card-popoling'));
    expect(find.descendant(of: card, matching: find.text('중지')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('마지막 실행 오늘')), findsOneWidget);
  });

  testWidgets('카드의 [전체 실행]은 등록된 Orchestrator 로 실행하고 카드에 바로 반영된다', (tester) async {
    final (:app, repo: _, :runner) = setUpApp();
    await openApp(tester, app);
    await tester.tap(find.byKey(const Key('category-dev')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('catalog-card-popoling'));
    await tester.tap(find.descendant(of: card, matching: find.text('전체 실행')));
    await tester.pumpAndSettle();
    expect(runner.stateOf(const ItemRef(projectId: 'popoling', serviceId: 'app')), ItemState.ready);
    expect(find.descendant(of: card, matching: find.text('실행 중 1/1')), findsOneWidget);
  });

  testWidgets('register 뒤에 바뀐 ProjectRepository 를 쓴다', (tester) async {
    final (:app, repo: _, runner: _) = setUpApp();
    app.provide<ProjectRepository>(FakeProjectRepository());
    await openApp(tester, app);
    expect(find.text('프로젝트 0개'), findsOneWidget);
  });
}

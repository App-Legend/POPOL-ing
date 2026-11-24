import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';
import 'package:popoling_ai/ai.dart' as ai;
import 'package:popoling_catalog/catalog.dart' as catalog;
import 'package:popoling_checks/checks.dart' as checks;
import 'package:popoling_compose/compose.dart' as compose;
import 'package:popoling_project/project.dart' as project;
import 'package:popoling_runner/runner.dart' as runner;

import 'registry.dart';
import 'screens/ai_screen.dart';
import 'screens/category_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/dialogs_screen.dart';
import 'screens/env_check_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qa_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runner.moveLegacyData(); // 등록한 프로젝트를 읽기 전에 옛 이름(ppoling)의 앱 데이터를 옮긴다
  runApp(PopolingApp(registry: buildRegistry()));
}

/// 가짜 구현과 목업 화면을 먼저 깔고, 기능의 `register()` 로 덮어쓴다.
/// 진짜 기능이 생기면 아래 목록에 `<기능>.register(app);` 한 줄을 더한다.
/// [features] 가 false 면 가짜와 목업만 깐다(목업 화면 테스트용. 진짜 구현은 파일·OS 보안 저장소를 쓴다).
Registry buildRegistry({bool features = true}) {
  final app = Registry();
  _registerFakes(app);
  _registerMockups(app);
  if (features) {
    project.register(app);
    runner.register(app);
    checks.register(app);
    compose.register(app);
    catalog.register(app);
    ai.register(app);
  }
  return app;
}

void _registerFakes(AppRegistry app) {
  app.provide<ProjectRepository>(FakeProjectRepository.withSamples());
  // 다른 가짜도 진짜 ProjectRepository 로 바뀐 뒤의 프로젝트를 보게 한다.
  final projects = _LazyProjects(app.read<ProjectRepository>);
  app.provide<ConfigValidator>(FakeConfigValidator());
  app.provide<QaRunner>(FakeQaRunner(projects));
  app.provide<PortProbe>(FakePortProbe());
  app.provide<HttpProbe>(FakeHttpProbe());
  app.provide<RuntimeQuery>(FakeRuntimeQuery());
  app.provide<Orchestrator>(FakeOrchestrator(projects));
}

void _registerMockups(AppRegistry app) {
  app.route('/', (_) => const CategoryScreen());
  app.route('/home', (_) => const HomeScreen());
  app.route('/dashboard', (_) => const DashboardScreen());
  app.route('/detail', (_) => const DetailScreen());
  app.route('/env', (_) => const EnvCheckScreen());
  app.route('/qa', (_) => const QaScreen());
  app.route('/settings', (context) {
    final projectId = ModalRoute.of(context)!.settings.arguments as String;
    return SettingsScreen(projectId: projectId);
  });
  app.route('/dialogs', (_) => const DialogsScreen());
  app.route('/ai', (_) => const AiScreen());
}

class PopolingApp extends StatelessWidget {
  PopolingApp({super.key, required this.registry});

  final Registry registry;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => RegistryHolder(
        app: registry,
        child: MaterialApp(
          title: '포폴링',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          navigatorKey: _navigator,
          builder: (_, child) => runner.exitGuard(registry, _navigator, child!),
          routes: registry.routes,
        ),
      );
}

/// 쓸 때마다 등록된 [ProjectRepository] 를 꺼내 넘긴다. 가짜 구현이 만들어질 때 아직 교체 전이라서.
class _LazyProjects implements ProjectRepository {
  _LazyProjects(this._read);

  final ProjectRepository Function() _read;

  @override
  Future<List<Project>> listProjects() => _read().listProjects();

  @override
  Stream<List<Project>> watchProjects() => _read().watchProjects();

  @override
  Future<Project> getProject(String id) => _read().getProject(id);

  @override
  Future<Project> addProject(String folderPath, {String? name}) => _read().addProject(folderPath, name: name);

  @override
  Future<Project> updateProject(Project project) => _read().updateProject(project);

  @override
  Future<void> removeProject(String id) => _read().removeProject(id);
}

import 'dart:async';
import 'dart:io';

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

import 'ai_slots.dart';
import 'registry.dart';
import 'screens/category_screen.dart';
import 'screens/dialogs_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runner.moveLegacyData(); // 등록한 프로젝트를 읽기 전에 옛 이름(ppoling)의 앱 데이터를 옮긴다
  runApp(PopolingApp(registry: buildRegistry()));
}

/// 가짜 구현과 목업 화면을 먼저 깔고, 기능의 `register()` 로 덮어쓴다.
/// 진짜 기능이 생기면 아래 목록에 `<기능>.register(app);` 한 줄을 더한다.
/// [features] 가 false 면 가짜와 목업만 깐다(목업 화면 테스트용. 진짜 구현은 파일·OS 보안 저장소를 쓴다).
Registry buildRegistry({bool features = true, bool demo = _demo}) {
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
    app.provide<ProjectPanels>(projectPanels(app));
    if (demo) _registerDemo(app);
  }
  return app;
}

/// `flutter run --dart-define=POPOLING_DEMO=true`: 진짜 화면에 샘플 데이터를 넣어 본다(화면 확인·발표 연습용).
/// 사용자 앱 데이터(등록 목록·실행 기록·환경 기록·AI 기록)는 쓰지 않는다. 로그 탭은 실제 로그 폴더를 읽기만 한다.
const _demo = bool.fromEnvironment('POPOLING_DEMO');

void _registerDemo(AppRegistry app) {
  final projects = FakeProjectRepository.withSamples();
  final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'shop-clone', serviceId: 'web')});
  // 상태가 여러 가지로 보이게 몇 개를 미리 실행해 둔다(가짜 실행이라 실제 프로세스는 없다).
  unawaited(runner.runAll('my-team-project'));
  unawaited(runner.runAll('shop-clone'));
  app
    ..provide<ProjectRepository>(projects)
    ..provide<Orchestrator>(runner)
    ..provide<QaRunner>(FakeQaRunner(projects))
    ..provide<EnvChecker>(FakeEnvChecker(installed: {'node': '22.3.0', 'java': '17.0.9'}))
    ..provide<EnvDiff>(FakeEnvDiff(projects, changes: {
      'my-team-project': const [EnvChange(name: 'node', before: '20.11.1', after: '22.3.0')],
    }))
    ..provide<PortProbe>(FakePortProbe())
    ..provide<RuntimeQuery>(FakeRuntimeQuery())
    ..provide<ItemLauncher>(FakeItemLauncher(projects))
    ..provide<LogExcerpt>(FakeLogExcerpt(projects))
    ..provide<FileHistory>(FakeFileHistory(projects))
    // AI 기록은 임시 폴더에 둔다. 발표 연습 기록이 실제 기록에 섞이지 않게.
    ..provide<ai.AnalysisHistory>(ai.AnalysisHistory(() async => File('${Directory.systemTemp.path}${Platform.pathSeparator}popoling-demo-ai-history.json')));
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
  app.route('/dialogs', (_) => const DialogsScreen());
}

class PopolingApp extends StatelessWidget {
  PopolingApp({super.key, required this.registry});

  final Registry registry;
  final _navigator = GlobalKey<NavigatorState>();
  late final Widget _status = catalog.statusList(registry);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '포폴링',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorKey: _navigator,
        builder: (_, child) => ShellScope(status: _status, child: runner.exitGuard(registry, _navigator, child!)),
        routes: registry.routes,
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

/// 실행 제어(A). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_runner/runner.dart' as runner;`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:popoling_core/contracts.dart';

import 'src/git/git_adapter.dart';
import 'src/log/log_store.dart';
import 'src/log/runner_log_excerpt.dart';
import 'src/orchestrator/runner_orchestrator.dart';
import 'src/process/process_launcher.dart';
import 'src/runtime/legacy_data.dart';
import 'src/runtime/runner_runtime_query.dart';
import 'src/runtime/runtime_store.dart';
import 'src/screens/dashboard_screen.dart';
import 'src/screens/exit_guard.dart';

/// 실행 제어의 화면(프로젝트 화면 `/dashboard`)과 구현([Orchestrator]·[RuntimeQuery]·[LogExcerpt])을 앱에 등록한다.
///
/// 다른 기능의 구현([ProjectRepository]·[ItemLauncher]·[PortProbe]·[HttpProbe]·[RuntimeQuery])은 처음 쓸 때 꺼낸다.
void register(AppRegistry app) {
  Future<String> data() async => (await getApplicationSupportDirectory()).path;
  final logs = LogStore(() async => Directory('${await data()}${Platform.pathSeparator}logs'));
  final git = GitAdapter(environment: toolEnvironment);
  final orchestrator = RunnerOrchestrator(
    projects: () => app.read<ProjectRepository>(),
    launcher: () => app.read<ItemLauncher>(),
    ports: () => app.read<PortProbe>(),
    http: () => app.read<HttpProbe>(),
    runtime: () => app.read<RuntimeQuery>(),
    processes: ProcessLauncher.forPlatform(relay: relayPath()),
    logs: logs,
    store: RuntimeStore(() async => File('${await data()}${Platform.pathSeparator}runtime.json')),
    git: git,
  );
  app.provide<Orchestrator>(orchestrator);
  unawaited(orchestrator.recover()); // 앱을 다시 켜기 전에 띄운 항목을 되살린다(FR-11). 다른 기능이 모두 등록된 뒤 돈다
  app.provide<RuntimeQuery>(RunnerRuntimeQuery(
    processes: () => orchestrator.liveProcesses,
    launcher: () => app.read<ItemLauncher>(),
  ));
  app.provide<LogExcerpt>(RunnerLogExcerpt(projects: () => app.read<ProjectRepository>(), logs: logs));

  Object? args(BuildContext context) => ModalRoute.of(context)?.settings.arguments;
  app.route(
      '/dashboard',
      (context) => DashboardScreen(
            projectId: args(context) as String? ?? '', // 인자 없이 열리면 '목록에 없는 프로젝트' 로 보인다
            projects: app.read<ProjectRepository>(),
            runner: app.read<Orchestrator>(),
            ports: app.read<PortProbe>(),
            runtime: app.read<RuntimeQuery>(),
            git: git,
            logs: logs,
            launcher: app.read<ItemLauncher>(),
            tabs: app.tabs,
            panels: _tryRead<ProjectPanels>(app) ?? const ProjectPanels(),
          ));
}

/// [child] 를 감싸, 앱을 닫을 때 실행 중인 항목이 있으면 묻는다(FR-12). 가짜 구현이면 그대로 둔다.
Widget exitGuard(AppRegistry app, GlobalKey<NavigatorState> navigatorKey, Widget child) =>
    switch (app.read<Orchestrator>()) {
      final RunnerOrchestrator o =>
        ExitGuard(navigatorKey: navigatorKey, stillUp: o.stillUp, stopEverything: o.stopEverything, child: child),
      _ => child,
    };

/// 앱에 함께 넣은 중계 실행 파일. 앱 실행 파일과 같은 폴더에 있다(macOS 는 `앱.app/Contents/MacOS/`).
String relayPath() =>
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}popoling-relay${Platform.isWindows ? '.exe' : ''}';

/// 앱 이름을 ppoling 에서 popoling 으로 바꾸기 전의 앱 데이터를 새 폴더로 옮긴다. 다른 기능이 데이터를 읽기 전에 `main` 에서 한 번 부른다.
Future<void> moveLegacyData() async => moveLegacyDataDir(await getApplicationSupportDirectory());

/// 등록된 구현을 꺼낸다. 아직 없으면 null.
T? _tryRead<T extends Object>(AppRegistry app) {
  try {
    return app.read<T>();
  } on StateError {
    return null;
  }
}

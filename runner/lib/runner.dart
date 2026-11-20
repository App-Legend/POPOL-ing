/// 실행 제어(A). `app/` 은 [register] 하나만 부른다.
/// `import 'package:ppoling_runner/runner.dart' as runner;`
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ppoling_core/contracts.dart';

import 'src/log/log_store.dart';
import 'src/log/runner_log_excerpt.dart';
import 'src/orchestrator/runner_orchestrator.dart';
import 'src/process/process_launcher.dart';
import 'src/runtime/runner_runtime_query.dart';
import 'src/runtime/runtime_store.dart';
import 'src/screens/dashboard_screen.dart';
import 'src/screens/detail_screen.dart';

/// 실행 제어의 화면(대시보드 `/dashboard`, 항목 상세 `/detail`)과 구현([Orchestrator]·[RuntimeQuery]·[LogExcerpt])을 앱에 등록한다.
///
/// 다른 기능의 구현([ProjectRepository]·[ItemLauncher]·[PortProbe]·[HttpProbe]·[RuntimeQuery])은 처음 쓸 때 꺼낸다.
void register(AppRegistry app) {
  Future<String> data() async => (await getApplicationSupportDirectory()).path;
  final logs = LogStore(() async => Directory('${await data()}${Platform.pathSeparator}logs'));
  final orchestrator = RunnerOrchestrator(
    projects: () => app.read<ProjectRepository>(),
    launcher: () => app.read<ItemLauncher>(),
    ports: () => app.read<PortProbe>(),
    http: () => app.read<HttpProbe>(),
    runtime: () => app.read<RuntimeQuery>(),
    processes: ProcessLauncher.forPlatform(),
    logs: logs,
    store: RuntimeStore(() async => File('${await data()}${Platform.pathSeparator}runtime.json')),
  );
  app.provide<Orchestrator>(orchestrator);
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
          ));
  app.route(
      '/detail',
      (context) => DetailScreen(
            item: args(context) as ItemRef,
            projects: app.read<ProjectRepository>(),
            runner: app.read<Orchestrator>(),
            process: (item) => orchestrator.liveProcesses.where((p) => p.item == item).firstOrNull,
            logs: logs,
            launcher: app.read<ItemLauncher>(),
          ));
}

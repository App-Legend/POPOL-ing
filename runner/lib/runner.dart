/// 실행 제어(A). `app/` 은 [register] 하나만 부른다.
/// `import 'package:ppoling_runner/runner.dart' as runner;`
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ppoling_core/contracts.dart';

import 'src/log/log_store.dart';
import 'src/orchestrator/runner_orchestrator.dart';
import 'src/process/process_launcher.dart';
import 'src/runtime/runner_runtime_query.dart';
import 'src/runtime/runtime_store.dart';

/// 실행 제어의 화면과 구현을 앱에 등록한다.
///
/// 다른 기능의 구현([ProjectRepository]·[ItemLauncher]·[PortProbe]·[HttpProbe]·[RuntimeQuery])은 처음 쓸 때 꺼낸다.
// 3주차에 LogExcerpt 구현과 대시보드(3)·항목 상세(4) 화면을 여기서 등록한다.
void register(AppRegistry app) {
  Future<String> data() async => (await getApplicationSupportDirectory()).path;
  final orchestrator = RunnerOrchestrator(
    projects: () => app.read<ProjectRepository>(),
    launcher: () => app.read<ItemLauncher>(),
    ports: () => app.read<PortProbe>(),
    http: () => app.read<HttpProbe>(),
    runtime: () => app.read<RuntimeQuery>(),
    processes: ProcessLauncher.forPlatform(),
    logs: LogStore(() async => Directory('${await data()}${Platform.pathSeparator}logs')),
    store: RuntimeStore(() async => File('${await data()}${Platform.pathSeparator}runtime.json')),
  );
  app.provide<Orchestrator>(orchestrator);
  app.provide<RuntimeQuery>(RunnerRuntimeQuery(
    processes: () => orchestrator.liveProcesses,
    launcher: () => app.read<ItemLauncher>(),
  ));
}

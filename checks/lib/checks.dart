/// 환경·연결 점검(C). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_checks/checks.dart' as checks;`
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:popoling_core/contracts.dart';

import 'src/env/env_snapshot.dart';
import 'src/env/system_env_checker.dart';
import 'src/env/system_env_diff.dart';
import 'src/screens/env_tab.dart';
import 'src/system_http_probe.dart';
import 'src/system_port_probe.dart';

export 'src/env/system_env_checker.dart' show SystemEnvChecker;
export 'src/env/system_env_diff.dart' show SystemEnvDiff;
export 'src/system_http_probe.dart' show SystemHttpProbe;
export 'src/system_port_probe.dart' show SystemPortProbe;

/// 환경·연결 점검의 화면(프로젝트 화면 환경 점검 탭)과 구현을 앱에 등록한다.
void register(AppRegistry app) {
  app.provide<PortProbe>(SystemPortProbe());
  app.provide<HttpProbe>(SystemHttpProbe());
  app.provide<EnvChecker>(SystemEnvChecker());

  final envDiff = SystemEnvDiff(
    projects: app.read<ProjectRepository>,
    store: EnvSnapshotStore(
      () async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}env-history.json'),
    ),
  );
  app.provide<EnvDiff>(envDiff);
  // 등록이 다 끝난 뒤 진짜 Orchestrator 의 성공 이벤트를 받는다(register 안에서 read 하면 가짜일 수 있다).
  // 데모 모드처럼 EnvDiff 가 가짜로 바뀌었으면 실제 환경 기록 파일을 쓰지 않게 듣지 않는다.
  scheduleMicrotask(() {
    if (identical(app.read<EnvDiff>(), envDiff)) envDiff.listenTo(app.read<Orchestrator>().events);
  });

  // 환경 점검 탭이 다시 점검한 문제 수를 탭 배지에 넘긴다.
  final problems = StreamController<(String, int)>.broadcast();
  app.tab(ProjectTab(
    id: 'env',
    label: '환경 점검',
    order: 10,
    build: (_, projectId) => EnvTab(
      projectId: projectId,
      projects: app.read<ProjectRepository>(),
      env: app.read<EnvChecker>(),
      ports: app.read<PortProbe>(),
      runtime: app.read<RuntimeQuery>(),
      runner: app.read<Orchestrator>(),
      diff: app.read<EnvDiff>(),
      onProblems: (n) => problems.add((projectId, n)),
    ),
    badge: (projectId) => envProblemCount(
      projectId: projectId,
      projects: app.read<ProjectRepository>(),
      env: app.read<EnvChecker>(),
      ports: app.read<PortProbe>(),
      runtime: app.read<RuntimeQuery>(),
      diff: app.read<EnvDiff>(),
      updates: problems.stream.where((e) => e.$1 == projectId).map((e) => e.$2),
    ),
  ));
}

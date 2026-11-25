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
import 'src/system_http_probe.dart';
import 'src/system_port_probe.dart';

export 'src/env/system_env_checker.dart' show SystemEnvChecker;
export 'src/env/system_env_diff.dart' show SystemEnvDiff;
export 'src/system_http_probe.dart' show SystemHttpProbe;
export 'src/system_port_probe.dart' show SystemPortProbe;

/// 환경·연결 점검의 화면과 구현을 앱에 등록한다.
// 4주차에 환경 점검(5) 화면을 여기서 등록한다.
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
  scheduleMicrotask(() => envDiff.listenTo(app.read<Orchestrator>().events));
}

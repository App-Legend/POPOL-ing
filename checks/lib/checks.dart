/// 환경·연결 점검(C). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_checks/checks.dart' as checks;`
library;

import 'package:popoling_core/contracts.dart';

import 'src/system_http_probe.dart';
import 'src/system_port_probe.dart';

export 'src/system_http_probe.dart' show SystemHttpProbe;
export 'src/system_port_probe.dart' show SystemPortProbe;

/// 환경·연결 점검의 화면과 구현을 앱에 등록한다.
// 3주차에 EnvChecker 구현을, 4주차에 EnvDiff 구현과 환경 점검(5) 화면을 여기서 등록한다.
void register(AppRegistry app) {
  app.provide<PortProbe>(SystemPortProbe());
  app.provide<HttpProbe>(SystemHttpProbe());
}

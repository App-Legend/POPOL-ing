/// Docker·원격 연결(C). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_compose/compose.dart' as compose;`
library;

import 'package:popoling_core/contracts.dart';

import 'src/docker_item_launcher.dart';

export 'src/docker_item_launcher.dart' show DockerItemLauncher;

/// Docker Compose 제어와 원격 연결 항목의 구현을 앱에 등록한다.
///
/// [ItemLauncher] 는 [ProjectRepository]·[HttpProbe]·[PortProbe] 를 쓴다. 등록이 다 끝난 뒤 처음 쓸 때 꺼낸다.
void register(AppRegistry app) {
  app.provide<ItemLauncher>(DockerItemLauncher(
    projects: () => app.read<ProjectRepository>(),
    http: () => app.read<HttpProbe>(),
    ports: () => app.read<PortProbe>(),
  ));
}

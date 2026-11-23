/// 카탈로그(D). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_catalog/catalog.dart' as catalog;`
library;

import 'package:popoling_core/contracts.dart';

import 'src/catalog_screen.dart';
import 'src/category_screen.dart';
import 'src/orchestrator_run_info.dart';
import 'src/run_info.dart';

/// 카테고리 선택(1, `/`)과 개발 홈 카탈로그(2, `/home`)를 등록한다.
///
/// `ProjectRepository`·`Orchestrator` 는 화면을 그릴 때 읽는다. 등록이 다 끝난 뒤라 가짜가 진짜로 바뀌어 있다.
// 4주차 후반에 오래된 프로젝트 점검(FR-17)을 여기서 더한다.
void register(AppRegistry app) {
  RunInfoSource? runs;
  RunInfoSource runInfo() => runs ??= OrchestratorRunInfoSource(app.read<Orchestrator>(), app.read<ProjectRepository>());

  app.route('/', (_) => CategoryScreen(projects: app.read<ProjectRepository>(), runs: runInfo()));
  app.route('/home', (_) => CatalogScreen(projects: app.read<ProjectRepository>(), runs: runInfo(), runner: app.read<Orchestrator>()));
}

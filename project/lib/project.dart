/// 프로젝트·설정(B). `app/` 은 [register] 하나만 부른다.
/// `import 'package:ppoling_project/project.dart' as project;`
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ppoling_core/contracts.dart';

import 'src/file_project_repository.dart';
import 'src/schema_config_validator.dart';

/// 프로젝트·설정의 화면과 구현을 앱에 등록한다.
// 3주차에 설정(7)·프로젝트 추가 화면을 여기서 등록한다.
void register(AppRegistry app) {
  app.provide<ProjectRepository>(FileProjectRepository(() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}projects.json');
  }));
  app.provide<ConfigValidator>(const SchemaConfigValidator());
}

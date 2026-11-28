/// 프로젝트·설정(B). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_project/project.dart' as project;`
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:popoling_core/contracts.dart';

import 'src/file_project_repository.dart';
import 'src/schema_config_validator.dart';
import 'src/screens/settings_tab.dart';

export 'src/command_summary.dart';

/// 프로젝트·설정의 화면(프로젝트 화면 설정 탭)과 구현을 앱에 등록한다.
void register(AppRegistry app) {
  app.provide<ProjectRepository>(FileProjectRepository(() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}projects.json');
  }));
  app.provide<ConfigValidator>(const SchemaConfigValidator());
  app.tab(ProjectTab(
    id: 'settings',
    label: '설정',
    order: 30,
    build: (_, projectId) => SettingsTab(projectId: projectId, projects: app.read<ProjectRepository>()),
  ));
}

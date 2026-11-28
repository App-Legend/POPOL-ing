/// 카탈로그(D). `app/` 은 [register] 하나만 부른다.
/// `import 'package:popoling_catalog/catalog.dart' as catalog;`
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:popoling_core/contracts.dart';

import 'src/catalog_screen.dart';
import 'src/category_screen.dart';
import 'src/home_layout.dart';
import 'src/orchestrator_run_info.dart';
import 'src/run_info.dart';
import 'src/status_list.dart';

/// 카테고리 선택(1, `/`)과 개발 홈 카탈로그(2, `/home`)를 등록한다.
///
/// `ProjectRepository`·`Orchestrator` 는 화면을 그릴 때 읽는다. 등록이 다 끝난 뒤라 가짜가 진짜로 바뀌어 있다.
/// 오래된 프로젝트 [실행 점검](FR-17)은 `EnvChecker`·`QaRunner` 가 등록돼 있을 때만 보인다.
void register(AppRegistry app) {
  app.route('/', (_) => CategoryScreen(projects: app.read<ProjectRepository>(), runs: _runInfo(app)));
  app.route(
    '/home',
    (_) => CatalogScreen(
      projects: app.read<ProjectRepository>(),
      runs: _runInfo(app),
      runner: app.read<Orchestrator>(),
      env: _tryRead<EnvChecker>(app),
      qa: _tryRead<QaRunner>(app),
      layout: _layout[app] ??= HomeLayoutStore(
        () async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}home-layout.json'),
      ),
    ),
  );
}

T? _tryRead<T extends Object>(AppRegistry app) {
  try {
    return app.read<T>();
  } on StateError {
    return null; // 아직 붙지 않은 기능
  }
}

/// 앱 하나에 묶음·고정 저장소 하나. 홈을 다시 열어도 읽어 둔 정리를 그대로 쓴다.
final _layout = Expando<HomeLayoutStore>();

/// 앱 하나에 실행 정보 계산 하나. 화면이 여러 개 쌓여도 이벤트마다 실행 기록을 한 번만 읽는다.
final _shared = Expando<RunInfoSource>();
RunInfoSource _runInfo(AppRegistry app) =>
    _shared[app] ??= _SharedRunInfo(OrchestratorRunInfoSource(app.read<Orchestrator>(), app.read<ProjectRepository>()));

/// 구독을 하나로 모으고, 나중에 구독한 화면에는 마지막 값을 먼저 준다.
/// shortcut: 구독자가 0명이 돼도 원본 구독은 앱이 끝날 때까지 남는다. 앱에 하나뿐이라 괜찮다.
class _SharedRunInfo implements RunInfoSource {
  _SharedRunInfo(this._source);

  final RunInfoSource _source;
  Map<String, RunInfo>? _last;
  late final _stream = _source.watchRunInfo().map((m) => _last = m).asBroadcastStream();

  @override
  Stream<Map<String, RunInfo>> watchRunInfo() async* {
    if (_last case final m?) yield m;
    yield* _stream;
  }
}

/// 왼쪽 메뉴 "지금 상태" 목록(실패·오래된 프로젝트). `app/` 이 앱 맨 위 [ShellScope] 에 넣는다.
/// 구현은 그릴 때 꺼낸다(등록이 다 끝난 뒤).
Widget statusList(AppRegistry app) => Builder(
      builder: (_) => StatusList(
        projects: app.read<ProjectRepository>(),
        runs: _runInfo(app),
      ),
    );

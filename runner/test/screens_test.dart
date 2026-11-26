import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_runner/src/git/git_adapter.dart';
import 'package:popoling_runner/src/log/log_store.dart';
import 'package:popoling_runner/src/screens/dashboard_screen.dart';
import 'package:popoling_runner/src/screens/item_log_view.dart';

const _web = ItemRef(projectId: 'my-team-project', serviceId: 'web');
const _shopWeb = ItemRef(projectId: 'shop-clone', serviceId: 'web');

/// web 을 시작하면 포트 사용 중이 된다. 멈춘 항목을 적어 둔다.
class _PortBusyOrchestrator extends FakeOrchestrator {
  _PortBusyOrchestrator(super.projects);

  final stopped = <ItemRef>[];
  var _busy = false;

  @override
  ItemState stateOf(ItemRef item) => item == _web && _busy ? ItemState.portBusy : super.stateOf(item);

  @override
  Future<ItemResult> start(ItemRef item) async {
    if (item != _web) return super.start(item);
    _busy = true;
    return const ItemResult(item: _web, outcome: ItemOutcome.failed, reason: '포트 5173 를 shop-clone / web 항목이 쓰고 있어요.');
  }

  @override
  Future<ItemResult> stop(ItemRef item) async {
    stopped.add(item);
    return super.stop(item);
  }
}

/// [gate] 를 열 때까지 전체 실행이 기다린다.
class _SlowRunAll extends FakeOrchestrator {
  _SlowRunAll(super.projects);

  final gate = Completer<void>();
  var stopAlls = 0;

  @override
  Future<RunSummary> runAll(String projectId) async {
    await gate.future;
    return super.runAll(projectId);
  }

  @override
  Future<RunSummary> stopAll(String projectId) {
    stopAlls++;
    return super.stopAll(projectId);
  }
}

/// fetch 하면 [remote] 로 바뀌는 Git 상태.
class _FakeGit extends GitAdapter {
  _FakeGit(this.current, {this.remote});

  GitStatus? current;
  final GitStatus? remote;

  @override
  Future<GitStatus?> status(String folder) async => current;

  @override
  Future<bool> fetch(String folder) async {
    if (remote == null) return false;
    current = remote;
    return true;
  }
}

/// 항목마다 정해 둔 줄을 돌려주는 로그.
class _FakeLogs extends LogStore {
  _FakeLogs(this.byService) : super(() async => Directory.systemTemp);

  final Map<String, List<String>> byService;

  @override
  Future<List<String>> tail(ItemRef item, {int lines = 5000, int maxRead = 1024 * 1024}) async =>
      byService[item.serviceId] ?? const [];
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('프로젝트 화면', () {
    late FakeProjectRepository projects;
    setUp(() => projects = FakeProjectRepository.withSamples());

    DashboardScreen dashboard(Orchestrator runner,
            {PortProbe? ports, RuntimeQuery? runtime, GitAdapter? git, LogStore? logs, List<ProjectTab> tabs = const [], ProjectPanels panels = const ProjectPanels(), String id = 'my-team-project'}) =>
        DashboardScreen(
          projectId: id,
          projects: projects,
          runner: runner,
          ports: ports ?? FakePortProbe(),
          runtime: runtime ?? FakeRuntimeQuery(),
          git: git,
          logs: logs ?? _FakeLogs({}),
          launcher: FakeItemLauncher(projects),
          tabs: tabs,
          panels: panels,
        );

    testWidgets('머리에 프로젝트 요약 상태를 보여 주고, 전체 실행하면 실행 흐름 카드 상태가 바뀐다', (tester) async {
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects)));
      for (final id in ['db', 'api', 'web', 'storage']) {
        expect(find.byKey(ValueKey('flow-$id')), findsOneWidget);
      }
      expect(find.text('중지'), findsWidgets);
      expect(find.text('Spring Boot'), findsOneWidget);
      expect(find.text('동아리 행사 예약 웹서비스 (2025 캡스톤)'), findsOneWidget);

      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('실행 중 · 4/4'), findsOneWidget);
      expect(find.text('준비 완료'), findsNWidgets(3));
      expect(find.text('연결됨'), findsOneWidget);
    });

    testWidgets('원격보다 뒤처지면 머리에 알리고 전체 실행 뒤 다시 읽는다 (AT-23)', (tester) async {
      final git = _FakeGit(const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev'),
          remote: const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev', behind: 3));
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), git: git));
      expect(find.text('최신 코드가 있어요 · 3커밋'), findsOneWidget);

      git.current = const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev');
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.textContaining('최신 코드가 있어요'), findsNothing);
    });

    testWidgets('의존 항목이 실패하면 일부 실패와 건너뜀을 보여 준다 (AT-04)', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'my-team-project', serviceId: 'api')});
      await pumpScreen(tester, dashboard(runner));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('일부 실패 · 2/4'), findsOneWidget);
      expect(find.text('성공 2 · 실패 1 · 건너뜀 1'), findsOneWidget);
      expect(find.text('건너뜀'), findsOneWidget);
    });

    testWidgets('shows tabs in order', (tester) async {
      final built = <String>[];
      Widget tab(String label) => const SizedBox();
      await pumpScreen(
        tester,
        dashboard(FakeOrchestrator(projects), tabs: [
          ProjectTab(id: 'env', label: '환경 점검', order: 10, build: (_, id) { built.add(id); return const Text('환경 내용'); }),
          ProjectTab(id: 'git', label: 'Git', order: 20, build: (_, _) => tab('Git')),
        ]),
      );
      final labels = tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('project-tabs')), matching: find.byType(Text))).map((t) => t.data).toList();
      expect(labels, ['로그', '환경 점검', 'Git']);
      await tester.tap(find.text('환경 점검'));
      await tester.pumpAndSettle();
      expect(find.text('환경 내용'), findsOneWidget);
      expect(built.last, 'my-team-project');
    });

    testWidgets('flow card selects log', (tester) async {
      final logs = _FakeLogs({'web': ['2026-11-24T10:00:02.000 out | VITE ready'], 'api': ['2026-11-24T10:00:01.000 out | Started']});
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), logs: logs));
      await tester.tap(find.byKey(const ValueKey('flow-web')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('web 로그'), findsOneWidget);
    });

    testWidgets('새로 실패한 항목의 로그를 먼저 보여 준다', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {_web});
      await pumpScreen(tester, dashboard(runner));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('web 로그'), findsOneWidget);
    });

    testWidgets('failure panel slot', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {_web});
      await pumpScreen(tester, dashboard(runner, panels: ProjectPanels(failure: (_, item, _) => Text('원인 자리 ${item.item.serviceId}'))));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('원인 자리 web'), findsOneWidget);
    });

    testWidgets('failure panel hidden without slot', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {_web});
      await pumpScreen(tester, dashboard(runner));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.textContaining('원인 자리'), findsNothing);
    });

    testWidgets('no services', (tester) async {
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), id: 'algo-study'));
      expect(find.textContaining('실행 항목이 아직 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow window', (tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: dashboard(FakeOrchestrator(projects))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('최신 코드를 기다리는 동안 알리고 전체 종료를 누를 수 있다', (tester) async {
      final runner = _SlowRunAll(projects);
      await pumpScreen(tester, dashboard(runner, git: _FakeGit(const GitStatus(branch: 'dev', changed: 0))));
      await tester.tap(find.text('전체 실행'));
      await tester.pump();
      expect(find.textContaining('전체 실행을 준비하고'), findsOneWidget);
      await tester.tap(find.text('전체 종료'));
      await tester.pumpAndSettle();
      expect(runner.stopAlls, 1);
      runner.gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('전체 실행을 준비하고'), findsNothing);
    });

    testWidgets('포트 주인이 내 다른 항목이면 그 항목 중지 버튼을 보여 준다 (AT-17)', (tester) async {
      final runner = _PortBusyOrchestrator(projects);
      await pumpScreen(
        tester,
        dashboard(
          runner,
          ports: FakePortProbe(inUse: [const PortInUse(5173, pid: 4321, processName: 'node')]),
          runtime: FakeRuntimeQuery(owned: [(port: 5173, pid: 4321, item: _shopWeb)]),
        ),
      );
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('flow-web')), matching: find.byTooltip('시작')));
      await tester.pumpAndSettle();
      expect(find.text('포트 사용 중'), findsOneWidget);
      expect(find.text('포트 5173 를 내 프로젝트 shop-clone / web 항목이 쓰고 있어요.'), findsOneWidget);

      await tester.tap(find.text('shop-clone / web 중지'));
      await tester.pumpAndSettle();
      expect(runner.stopped, [_shopWeb]);
      expect(find.text('shop-clone / web 중지'), findsNothing);
    });

    testWidgets('외부 프로그램이 포트를 쓰면 중지 버튼 없이 이유만 보여 준다 (AT-03)', (tester) async {
      final runner = _PortBusyOrchestrator(projects);
      await pumpScreen(tester, dashboard(runner, ports: FakePortProbe(inUse: [const PortInUse(5173, pid: 99, processName: 'java')])));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('flow-web')), matching: find.byTooltip('시작')));
      await tester.pumpAndSettle();
      expect(find.textContaining('/ web 중지'), findsNothing);
      expect(find.text('포트 5173 를 shop-clone / web 항목이 쓰고 있어요.'), findsOneWidget);
    });

    testWidgets('없는 프로젝트면 안내만 보여 준다', (tester) async {
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), id: 'nope'));
      expect(find.text('목록에 없는 프로젝트예요: nope'), findsOneWidget);
    });
  });

  group('항목 로그', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('popoling_detail_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('로그 파일을 보여 주고 stderr 만 골라 볼 수 있다', (tester) async {
      final projects = FakeProjectRepository.withSamples();
      final logs = LogStore(() async => tmp);
      final web = (await tester.runAsync(() => projects.getProject('my-team-project')))!.config!.services.firstWhere((s) => s.id == 'web');
      await tester.runAsync(() async {
        final f = await logs.fileOf(_web);
        await f.parent.create(recursive: true);
        await f.writeAsString('--- 시작 2026-11-19T10:00:00.000 ---\n'
            '2026-11-19T10:00:01.000 out | VITE ready\n'
            '2026-11-19T10:00:02.000 err | warning: pw=****\n');
      });
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(1280, 1600);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ItemLogView(item: _web, service: web, runner: FakeOrchestrator(projects), logs: logs, launcher: FakeItemLauncher(projects)),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 300)); // 파일 읽기
      });
      addTearDown(tester.view.reset);
      await tester.pump();
      expect(find.text('web 로그'), findsOneWidget);
      expect(find.textContaining('VITE ready', findRichText: true), findsOneWidget);
      expect(find.textContaining('warning: pw=****', findRichText: true), findsOneWidget);

      await tester.tap(find.text('stderr'));
      await tester.pump();
      expect(find.textContaining('VITE ready', findRichText: true), findsNothing);
      expect(find.textContaining('warning: pw=****', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // 1초 타이머를 멈춘다
    });
  });
}

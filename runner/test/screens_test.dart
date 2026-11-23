import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_runner/src/git/git_adapter.dart';
import 'package:popoling_runner/src/log/log_store.dart';
import 'package:popoling_runner/src/screens/dashboard_screen.dart';
import 'package:popoling_runner/src/screens/detail_screen.dart';
import 'package:popoling_runner/src/screens/log_preview.dart';

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
  group('대시보드', () {
    late FakeProjectRepository projects;
    setUp(() => projects = FakeProjectRepository.withSamples());

    DashboardScreen dashboard(Orchestrator runner, {PortProbe? ports, RuntimeQuery? runtime, GitAdapter? git, LogStore? logs}) => DashboardScreen(
          projectId: 'my-team-project',
          projects: projects,
          runner: runner,
          ports: ports ?? FakePortProbe(),
          runtime: runtime ?? FakeRuntimeQuery(),
          git: git,
          logs: logs,
        );

    testWidgets('항목을 상태 라벨과 함께 보여 주고, 전체 실행하면 상태와 결과가 바뀐다', (tester) async {
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects)));
      for (final id in ['db', 'api', 'web', 'storage']) {
        expect(find.text(id), findsOneWidget);
      }
      expect(find.text('중지'), findsWidgets);
      expect(find.text('아직 전체 실행 기록이 없어요.'), findsOneWidget);

      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('준비 완료'), findsNWidgets(3));
      expect(find.text('연결됨'), findsOneWidget);
      expect(find.text('성공'), findsNWidgets(4));
    });

    testWidgets('Git 상태를 보여 주고 전체 실행 뒤 다시 읽는다 (AT-23)', (tester) async {
      final git = _FakeGit(const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev'),
          remote: const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev', behind: 3));
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), git: git));
      expect(find.text('dev'), findsOneWidget);
      expect(find.text('커밋하지 않은 변경 2개'), findsOneWidget);
      expect(find.text('원격보다 3커밋 뒤처짐'), findsOneWidget);

      git.current = const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev');
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.textContaining('뒤처짐'), findsNothing);
    });

    testWidgets('Git 저장소가 아니면 표시를 숨긴다', (tester) async {
      await pumpScreen(tester, dashboard(FakeOrchestrator(projects), git: _FakeGit(null)));
      expect(find.text('브랜치'), findsNothing);
    });

    testWidgets('의존 항목이 실패하면 결과에 건너뜀을 보여 준다 (AT-04)', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'my-team-project', serviceId: 'api')});
      await pumpScreen(tester, dashboard(runner));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('건너뜀'), findsOneWidget);
      expect(find.text('성공 2 · 실패 1 · 건너뜀 1'), findsOneWidget);
      expect(find.text('실패'), findsWidgets);
    });

    testWidgets('최근 로그는 실패한 항목을 먼저 보여 주고 다른 항목을 고를 수 있다', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'my-team-project', serviceId: 'api')});
      final logs = _FakeLogs({
        'api': ['2026-11-24T10:00:01.000 err | Port 8080 already in use ${'x' * 400}'],
        'web': ['2026-11-24T10:00:02.000 out | VITE ready'],
      });
      await pumpScreen(tester, dashboard(runner, logs: logs));
      Finder tab(String id) => find.descendant(of: find.byType(LogPreview), matching: find.widgetWithText(TextButton, id));
      expect(tab('storage'), findsNothing); // 원격은 로그가 없다

      await tester.tap(tab('web'));
      await tester.pumpAndSettle();
      expect(find.textContaining('VITE ready', findRichText: true), findsOneWidget);

      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('최근 로그 · api'), findsOneWidget); // 새로 실패해 고른 항목 대신 보인다
      expect(find.textContaining('err  Port 8080 already in use', findRichText: true), findsOneWidget);
      expect(find.textContaining('x' * 350, findRichText: true), findsNothing);

      await tester.tap(tab('web'));
      await tester.pumpAndSettle();
      expect(find.textContaining('VITE ready', findRichText: true), findsOneWidget);
      expect(find.textContaining('Port 8080', findRichText: true), findsNothing);

      logs.byService['web'] = ['2026-11-24T10:00:03.000 out | 새 줄'];
      await tester.pump(const Duration(seconds: 1)); // 1초마다 다시 읽는다
      await tester.pump();
      expect(find.textContaining('새 줄', findRichText: true), findsOneWidget);

      await tester.tap(tab('db'));
      await tester.pumpAndSettle();
      expect(find.text('Compose 로그는 [전체 로그]에서 볼 수 있어요.'), findsOneWidget);
    });

    testWidgets('고르지 않았으면 첫 항목이 아니라 실패한 항목의 로그를 보여 준다', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {_web});
      await pumpScreen(tester, dashboard(runner, logs: _FakeLogs({})));
      expect(find.text('최근 로그 · api'), findsOneWidget);
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('최근 로그 · web'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(OutlinedButton, '시작').at(2)); // db, api, web 순서
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
      await tester.tap(find.widgetWithText(OutlinedButton, '시작').at(2));
      await tester.pumpAndSettle();
      expect(find.textContaining('/ web 중지'), findsNothing);
      expect(find.text('포트 5173 를 shop-clone / web 항목이 쓰고 있어요.'), findsOneWidget);
    });

    testWidgets('없는 프로젝트면 안내만 보여 준다', (tester) async {
      await pumpScreen(
        tester,
        DashboardScreen(
          projectId: 'nope',
          projects: projects,
          runner: FakeOrchestrator(projects),
          ports: FakePortProbe(),
          runtime: FakeRuntimeQuery(),
        ),
      );
      expect(find.text('목록에 없는 프로젝트예요: nope'), findsOneWidget);
    });
  });

  group('항목 상세', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('popoling_detail_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('로그 파일을 보여 주고 stderr 만 골라 볼 수 있다', (tester) async {
      final projects = FakeProjectRepository.withSamples();
      final logs = LogStore(() async => tmp);
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
          home: DetailScreen(
            item: _web,
            projects: projects,
            runner: FakeOrchestrator(projects),
            process: (_) => null,
            logs: logs,
            launcher: FakeItemLauncher(projects),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 300)); // 파일 읽기
      });
      addTearDown(tester.view.reset);
      await tester.pump();
      expect(find.textContaining('VITE ready', findRichText: true), findsOneWidget);
      expect(find.textContaining('warning: pw=****', findRichText: true), findsOneWidget);
      expect(find.text('npm run dev'), findsOneWidget);
      expect(find.text('띄운 프로세스 없음'), findsOneWidget);

      await tester.tap(find.text('stderr'));
      await tester.pump();
      expect(find.textContaining('VITE ready', findRichText: true), findsNothing);
      expect(find.textContaining('warning: pw=****', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // 1초 타이머를 멈춘다
    });
  });
}

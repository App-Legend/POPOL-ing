import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_runner/src/log/log_store.dart';
import 'package:ppoling_runner/src/screens/dashboard_screen.dart';
import 'package:ppoling_runner/src/screens/detail_screen.dart';

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

    DashboardScreen dashboard(Orchestrator runner, {PortProbe? ports, RuntimeQuery? runtime}) => DashboardScreen(
          projectId: 'my-team-project',
          projects: projects,
          runner: runner,
          ports: ports ?? FakePortProbe(),
          runtime: runtime ?? FakeRuntimeQuery(),
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

    testWidgets('의존 항목이 실패하면 결과에 건너뜀을 보여 준다 (AT-04)', (tester) async {
      final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'my-team-project', serviceId: 'api')});
      await pumpScreen(tester, dashboard(runner));
      await tester.tap(find.text('전체 실행'));
      await tester.pumpAndSettle();
      expect(find.text('건너뜀'), findsOneWidget);
      expect(find.text('실패'), findsWidgets);
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
    setUp(() => tmp = Directory.systemTemp.createTempSync('ppoling_detail_'));
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

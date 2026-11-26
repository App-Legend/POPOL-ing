import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/screens/env_tab.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';

const _id = 'my-team-project';
const _shopWeb = ItemRef(projectId: 'shop-clone', serviceId: 'web');

class _RecordingRunner extends FakeOrchestrator {
  _RecordingRunner(super.projects);
  final stopped = <ItemRef>[];
  @override
  Future<ItemResult> stop(ItemRef item) {
    stopped.add(item);
    return super.stop(item);
  }
}

class _BrokenChecker implements EnvChecker {
  @override
  Future<List<EnvCheckResult>> check(List<Requirement> requires) async => throw StateError('boom');
}

void main() {
  late FakeProjectRepository projects;
  setUp(() => projects = FakeProjectRepository.withSamples());

  EnvTab tab({EnvChecker? env, PortProbe? ports, RuntimeQuery? runtime, EnvDiff? diff, Orchestrator? runner}) => EnvTab(
        projectId: _id,
        projects: projects,
        env: env ?? FakeEnvChecker(installed: {'node': '22.3.0', 'java': '17.0.9'}),
        ports: ports ?? FakePortProbe(),
        runtime: runtime ?? FakeRuntimeQuery(),
        diff: diff,
        runner: runner ?? FakeOrchestrator(projects),
      );

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    await tester.pumpAndSettle();
  }

  testWidgets('all versions ok', (tester) async {
    await pump(tester, tab());
    expect(find.text('3개 모두 맞아요'), findsOneWidget);
    expect(find.text('22.3.0'), findsOneWidget);
  });

  testWidgets('version mismatch shows label and badge', (tester) async {
    final env = FakeEnvChecker(installed: {'node': '18.0.0', 'java': '17.0.9'});
    await pump(tester, tab(env: env));
    expect(find.text('맞지 않음 1'), findsOneWidget);
    expect(find.text('버전이 맞지 않아요'), findsOneWidget);
    final count = await envProblemCount(projectId: _id, projects: projects, env: env, ports: FakePortProbe(), runtime: FakeRuntimeQuery()).first;
    expect(count, greaterThanOrEqualTo(1));
  });

  testWidgets('external port no stop button', (tester) async {
    await pump(tester, tab(ports: FakePortProbe(inUse: [const PortInUse(5173, pid: 99, processName: 'java')])));
    expect(find.text('사용 중 1'), findsOneWidget);
    expect(find.text('java (PID 99)'), findsOneWidget);
    expect(find.textContaining('중지'), findsNothing);
  });

  testWidgets('my other project shows stop', (tester) async {
    final runner = _RecordingRunner(projects);
    await pump(
      tester,
      tab(
        ports: FakePortProbe(inUse: [const PortInUse(5173, pid: 4321, processName: 'node')]),
        runtime: FakeRuntimeQuery(owned: [(port: 5173, pid: 4321, item: _shopWeb)]),
        runner: runner,
      ),
    );
    expect(find.text('shop-clone / web 중지'), findsOneWidget);
    expect(find.textContaining('내 다른 프로젝트'), findsOneWidget);
    await tester.tap(find.text('shop-clone / web 중지'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(runner.stopped, isEmpty, reason: '취소하면 멈추지 않는다');
  });

  testWidgets('no history', (tester) async {
    await pump(tester, tab(diff: FakeEnvDiff(projects)));
    expect(find.text('아직 성공한 실행 기록이 없어요.'), findsOneWidget);
  });

  testWidgets('diff rows', (tester) async {
    await pump(tester, tab(diff: FakeEnvDiff(projects, changes: {_id: [const EnvChange(name: 'node', before: '20.11.1', after: '22.3.0')]})));
    expect(find.text('1가지'), findsOneWidget);
    expect(find.text('20.11.1'), findsOneWidget);
  });

  testWidgets('checker throws', (tester) async {
    await pump(tester, tab(env: _BrokenChecker()));
    expect(find.text('도구를 확인하지 못했어요'), findsOneWidget);
    expect(find.text('모두 비어 있어요'), findsOneWidget); // 포트 칸은 그대로
    expect(tester.takeException(), isNull);
  });
}

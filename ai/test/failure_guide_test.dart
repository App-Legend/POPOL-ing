import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/src/failure_guide.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

const web = ItemRef(projectId: 'my-team-project', serviceId: 'web');
const owner = ItemRef(projectId: 'shop-clone', serviceId: 'web');

ItemResult failed(FailureCause cause) => ItemResult(item: web, outcome: ItemOutcome.failed, reason: '시작하지 못했어요.', cause: cause);

List<String> labels(FailureGuide g) => [for (final (_, label) in g.actions) label];

/// 부른 순서만 남기는 실행기.
class RecordingRunner implements Orchestrator {
  final calls = <String>[];

  @override
  Stream<RunEvent> get events => const Stream.empty();

  @override
  ItemState stateOf(ItemRef item) => ItemState.stopped;

  @override
  FailureCause? causeOf(ItemRef item) => null;

  @override
  Future<RunSummary> runAll(String projectId) => throw UnimplementedError();

  @override
  Future<RunSummary> stopAll(String projectId) => throw UnimplementedError();

  @override
  Future<ItemResult> start(ItemRef item) async {
    calls.add('start ${item.projectId}/${item.serviceId}');
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  @override
  Future<ItemResult> stop(ItemRef item) async {
    calls.add('stop ${item.projectId}/${item.serviceId}');
    return ItemResult(item: item, outcome: ItemOutcome.ok);
  }

  @override
  Future<RunSummary?> lastRun(String projectId) async => null;
}

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

Future<String?> show(WidgetTester tester, FailureCause cause, RecordingRunner runner) async {
  String? opened;
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    onGenerateRoute: (s) {
      opened = '${s.name} ${s.arguments}';
      return MaterialPageRoute(builder: (_) => const Text('열림'));
    },
    home: Scaffold(body: SingleChildScrollView(child: FailureGuideCard(item: failed(cause), runner: runner))),
  ));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  group('failureGuide (기획서 §8)', () {
    test('포트를 내 다른 항목이 쓰면 그 항목 중지하고 시작·그 프로젝트로 이동', () {
      final g = failureGuide(failed(const PortBusy(PortInUse(5173, pid: 4242, processName: 'node'), owner: owner)));
      expect(g.what, '5173 포트를 shop-clone / web이 쓰고 있어서 web을 시작하지 않았어요.');
      expect(labels(g), ['shop-clone / web 중지하고 web 시작', 'shop-clone으로 이동']);
    });

    test('포트를 외부 프로그램이 쓰면 멈추는 버튼은 없고 이름·PID 만', () {
      final g = failureGuide(failed(const PortBusy(PortInUse(5173, pid: 4242, processName: 'node'))));
      expect(g.evidence, contains('포트 주인: node (PID 4242), 포폴링이 띄우지 않은 프로그램'));
      expect(labels(g), ['다시 시도']);
      expect(g.actions.any((a) => a.$1 == GuideAction.stopOwnerAndStart), isFalse);
    });

    test('도구 없음은 필요한 도구를 근거로', () {
      final g = failureGuide(failed(const ToolMissing('java')));
      expect(g.what, 'java 명령을 찾지 못해 web을 시작하지 못했어요.');
      expect(g.evidence.first, '필요한 도구: java');
    });

    test('.env 없음은 경로만 보이고 값은 없다', () {
      final g = failureGuide(failed(const EnvFileMissing('api/.env')));
      expect(g.what, 'api/.env 파일이 없어 web을 시작하지 못했어요.');
      expect(g.tryThis, contains('값'));
    });

    test('준비 시간 초과는 [끄기]', () {
      final g = failureGuide(failed(const ReadyTimeout(Duration(seconds: 60))));
      expect(g.what, 'web이 60초 안에 준비되지 않았어요. 프로그램은 아직 켜져 있어요.');
      expect(labels(g), ['끄기']);
    });

    test('실행 중 멈춤은 종료 코드와 [다시 켜기]', () {
      final g = failureGuide(failed(const Crashed(exitCode: 137, evidence: ['Killed'])));
      expect(g.what, 'web이 실행 중에 멈췄어요 (종료 코드 137).');
      expect(g.evidence, contains('Killed'));
      expect(labels(g), ['다시 켜기']);
    });

    test('근거 로그의 비밀값은 다시 한 번 가린다', () {
      final g = failureGuide(failed(const CommandFailed(exitCode: 1, evidence: ['API_KEY=sk-live-abcdefghijklmnop'])));
      expect(g.evidence.join('\n'), isNot(contains('sk-live-abcdefghijklmnop')));
    });
  });

  group('FailureGuideCard', () {
    testWidgets('API 키 없이도 무슨 일·근거·이렇게 해 보세요가 보인다', (tester) async {
      await show(tester, const ToolMissing('java'), RecordingRunner());
      expect(find.text('java 명령을 찾지 못해 web을 시작하지 못했어요.'), findsOneWidget);
      expect(find.text('근거'), findsOneWidget);
      expect(find.text('이렇게 해 보세요'), findsOneWidget);
    });

    testWidgets('[중지하고 시작]은 확인 창(기본 취소)을 거쳐 내 항목만 멈추고 시작한다', (tester) async {
      final runner = RecordingRunner();
      await show(tester, const PortBusy(PortInUse(5173), owner: owner), runner);
      await tester.tap(btn('shop-clone / web 중지하고 web 시작'));
      await tester.pumpAndSettle();
      expect(find.text('다른 프로젝트의 shop-clone / web을 중지할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(runner.calls, isEmpty);

      await tester.tap(btn('shop-clone / web 중지하고 web 시작'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('중지'));
      await tester.pumpAndSettle();
      expect(runner.calls, ['stop shop-clone/web', 'start my-team-project/web']);
    });

    testWidgets('[○○으로 이동]은 그 프로젝트 화면을 연다', (tester) async {
      final runner = RecordingRunner();
      String? opened;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        onGenerateRoute: (s) {
          opened = '${s.name} ${s.arguments}';
          return MaterialPageRoute(builder: (_) => const Text('열림'));
        },
        home: Scaffold(body: FailureGuideCard(item: failed(const PortBusy(PortInUse(5173), owner: owner)), runner: runner)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(btn('shop-clone으로 이동'));
      await tester.pumpAndSettle();
      expect(opened, '/dashboard shop-clone');
    });

    testWidgets('[다시 켜기]는 그 항목만 시작한다', (tester) async {
      final runner = RecordingRunner();
      await show(tester, const Crashed(exitCode: 1), runner);
      await tester.tap(btn('다시 켜기'));
      await tester.pumpAndSettle();
      expect(runner.calls, ['start my-team-project/web']);
    });
  });
}

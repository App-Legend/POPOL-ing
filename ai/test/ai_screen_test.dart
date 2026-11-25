import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart';
import 'package:popoling_ai/src/ai_screen.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const fullKey = 'AQ.stored-key-abcdefghijklmnop';

Future<void> open(WidgetTester tester, ApiKeyStore keys, {String model = 'gemini-flash-latest', Future<void> Function(String)? checkKey}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: AiScreen(keys: keys, client: FakeLlmClient(modelName: model), checkKey: checkKey),
  ));
  await tester.pumpAndSettle();
}

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

/// 화면에 그려진 글자 전부.
String shownText(WidgetTester tester) =>
    [for (final w in tester.widgetList<RichText>(find.byType(RichText))) w.text.toPlainText()].join('\n');

const sendNotice = '[보내기]를 누른 뒤에만 Google로 보내요. .env 값과 API 키는 보내지 않아요.';
const noProjectNotice = '프로젝트 대시보드에서 [AI 검사]를 누르면 그 프로젝트의 실행 실패 원인 분석과 헬스체크 결과 요약을 볼 수 있어요.';
const noKeyNotice = 'AI 분석을 하려면 Gemini API 키가 필요해요. 키가 없어도 실행·종료·헬스체크 같은 다른 기능은 그대로 쓸 수 있어요.';

void main() {
  testWidgets('AT-19: 키가 없으면 "API 키 필요"와 [키 입력], 다른 기능은 그대로 쓴다고 알린다', (tester) async {
    await open(tester, MemoryApiKeyStore());
    expect(find.text('AI 검사'), findsWidgets);
    expect(find.widgetWithText(StatusChip, 'API 키 필요'), findsOneWidget);
    expect(find.text('Gemini API 키를 넣으면 AI 분석을 쓸 수 있어요.'), findsOneWidget);
    expect(find.text(noKeyNotice), findsOneWidget);
    expect(find.text(sendNotice), findsOneWidget);
    expect(btn('키 입력'), findsOneWidget);
    expect(btn('키 바꾸기'), findsNothing);
  });

  testWidgets('키가 있으면 모델 이름과 키 끝 4자리만 보여 준다', (tester) async {
    await open(tester, MemoryApiKeyStore(fullKey));
    expect(find.widgetWithText(StatusChip, 'API 키 입력됨'), findsOneWidget);
    expect(find.text('gemini-flash-latest · 키 ••••••••mnop'), findsOneWidget);
    expect(find.text(sendNotice), findsOneWidget, reason: '전송 안내는 키가 있어도 보인다');
    expect(find.text(noKeyNotice), findsNothing);
    expect(btn('키 바꾸기'), findsOneWidget);
    expect(shownText(tester), isNot(contains(fullKey.substring(0, fullKey.length - 4))));
  });

  testWidgets('8자 이하로 짧은 키는 끝 4자리도 보여 주지 않는다', (tester) async {
    await open(tester, MemoryApiKeyStore('AQ.short'));
    expect(find.text('gemini-flash-latest · 키 ••••••••'), findsOneWidget);
    expect(shownText(tester), isNot(contains('hort')));
  });

  testWidgets('[키 입력]으로 저장하면 키 있음으로 바뀌고 저장했다고 알린다', (tester) async {
    final keys = MemoryApiKeyStore();
    await open(tester, keys);
    await tester.tap(btn('키 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.new-key-1234wxyz');
    await tester.tap(btn('저장'));
    await tester.pumpAndSettle();
    expect(await keys.read(), 'AQ.new-key-1234wxyz');
    expect(find.widgetWithText(StatusChip, 'API 키 입력됨'), findsOneWidget);
    expect(find.text('gemini-flash-latest · 키 ••••••••wxyz'), findsOneWidget);
    expect(find.text('API 키를 저장했어요.'), findsOneWidget);
  });

  testWidgets('[키 바꾸기]에서 지우면 키 없음으로 바뀌고 지웠다고 알린다', (tester) async {
    final keys = MemoryApiKeyStore(fullKey);
    await open(tester, keys);
    await tester.tap(btn('키 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(btn('키 지우기'));
    await tester.pumpAndSettle();
    expect(await keys.read(), isNull);
    expect(find.widgetWithText(StatusChip, 'API 키 필요'), findsOneWidget);
    expect(find.text('API 키를 지웠어요. AI 분석을 하려면 다시 넣어 주세요.'), findsOneWidget);
  });

  testWidgets('[취소]하면 아무것도 바뀌지 않고 알림도 없다', (tester) async {
    await open(tester, MemoryApiKeyStore(fullKey));
    await tester.tap(btn('키 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(find.text('gemini-flash-latest · 키 ••••••••mnop'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('키 확인 방법을 넘겨받으면 키 창에 [연결 확인]이 생긴다', (tester) async {
    final checked = <String>[];
    await open(tester, MemoryApiKeyStore(fullKey), checkKey: (k) async => checked.add(k));
    await tester.tap(btn('키 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(btn('연결 확인'));
    await tester.pumpAndSettle();
    expect(checked, [fullKey]);
  });

  testWidgets('보안 저장소를 읽지 못하면 그렇게 알리고, 키 입력 창 대신 안내를 띄운다', (tester) async {
    await open(tester, _BrokenStore());
    expect(find.widgetWithText(StatusChip, '키를 읽지 못함'), findsOneWidget);
    expect(find.text('이 컴퓨터의 보안 저장소에서 API 키를 읽지 못했어요.'), findsOneWidget);
    expect(find.text(noKeyNotice), findsOneWidget);
    await tester.tap(btn('키 입력'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini API 키 입력'), findsNothing);
    expect(find.text('보안 저장소를 쓰지 못해 키 입력 창을 열지 못했어요.'), findsOneWidget);
  });

  group('헬스체크 결과 요약 카드 (AI-03)', () {
    final checkedAt = DateTime(2026, 11, 22, 14, 5, 2);
    late FakeProjectRepository projects;
    late FakeQaRunner qa;

    setUp(() {
      projects = FakeProjectRepository.withSamples();
      qa = FakeQaRunner(projects, failing: {'API 헬스'}, clock: () => checkedAt);
    });

    Future<void> openWithProject(WidgetTester tester, {String? projectId, DateTime? now}) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AiScreen(
          keys: MemoryApiKeyStore(fullKey),
          client: FakeLlmClient(),
          projectId: projectId,
          qa: qa,
          orchestrator: FakeOrchestrator(projects),
          clock: () => now ?? checkedAt.add(const Duration(hours: 1)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('프로젝트 없이 열면 카드 없이 준비 중 안내만', (tester) async {
      await openWithProject(tester);
      expect(find.text('헬스체크 결과 요약'), findsNothing);
      expect(find.text(noProjectNotice), findsOneWidget);
    });

    testWidgets('검사 이력이 없으면 빈 안내와 [헬스체크], 누르면 그 결과로 요약 패널', (tester) async {
      await openWithProject(tester, projectId: 'my-team-project');
      expect(find.text('헬스체크 결과 요약'), findsOneWidget);
      expect(find.text('아직 헬스체크 결과가 없어요.'), findsOneWidget);
      expect(btn('AI 요약'), findsNothing);
      expect(find.text('실행 실패 원인 분석은 준비 중이에요.'), findsNothing);

      await tester.tap(btn('헬스체크'));
      await tester.pumpAndSettle();
      expect(await qa.history('my-team-project'), hasLength(1), reason: '누를 때만 한 번 검사');
      expect(find.text('아직 헬스체크 결과가 없어요.'), findsNothing);
      expect(find.text('오늘 14:05 검사 기준'), findsOneWidget);
      expect(btn('AI 요약'), findsOneWidget);
    });

    testWidgets('카드에서 키를 넣으면 화면 위쪽 키 상태도 바뀐다', (tester) async {
      await qa.runChecks('my-team-project');
      final keys = MemoryApiKeyStore();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AiScreen(
          keys: keys,
          client: _StoreClient(keys),
          projectId: 'my-team-project',
          qa: qa,
          orchestrator: FakeOrchestrator(projects),
          clock: () => checkedAt,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(StatusChip, 'API 키 필요'), findsOneWidget);

      final panelKeyButton = find.descendant(of: find.byType(QaSummaryPanel), matching: btn('키 입력'));
      expect(panelKeyButton, findsOneWidget);
      await tester.tap(panelKeyButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.new-key-1234wxyz');
      await tester.tap(btn('저장'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(StatusChip, 'API 키 입력됨'), findsOneWidget);
      expect(find.text(noKeyNotice), findsNothing);
      expect(btn('AI 요약'), findsOneWidget);
    });

    testWidgets('최근 검사가 오늘이 아니면 날짜로 기준을 보여 준다', (tester) async {
      await qa.runChecks('my-team-project');
      await openWithProject(tester, projectId: 'my-team-project', now: DateTime(2026, 11, 23, 9));
      expect(find.text('11/22 14:05 검사 기준'), findsOneWidget);
      expect(btn('AI 요약'), findsOneWidget);
    });
  });

  group('실행 실패 원인 분석 카드 (AI-02)', () {
    const emptyRun = '실패한 실행이 없어요. 실행이 실패하면 여기서 원인을 찾아 드려요.';
    late FakeProjectRepository projects;
    late FakeOrchestrator runner;

    setUp(() {
      projects = FakeProjectRepository.withSamples();
      runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: 'my-team-project', serviceId: 'api')});
    });

    Future<void> openRun(WidgetTester tester, {ApiKeyStore? keys, LlmClient? client}) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = keys ?? MemoryApiKeyStore(fullKey);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AiScreen(
          keys: store,
          client: client ?? FakeLlmClient(),
          projectId: 'my-team-project',
          qa: FakeQaRunner(projects),
          orchestrator: runner,
          projects: projects,
          logs: FakeLogExcerpt(projects),
          envDiff: FakeEnvDiff(projects),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('전체 실행 기록이 없으면 실패한 실행이 없어요', (tester) async {
      await openRun(tester);
      expect(find.text('실행 실패 원인 분석'), findsOneWidget);
      expect(find.text(emptyRun), findsOneWidget);
      expect(btn('원인 분석'), findsNothing);
    });

    testWidgets('실패 항목마다 [원인 분석], 건너뜀은 버튼 없이, 설명은 한 번', (tester) async {
      await runner.runAll('my-team-project');
      await openRun(tester);
      expect(find.textContaining('전체 실행 기준'), findsOneWidget);
      expect(find.textContaining('api · 실패 · 시작하자마자 종료됐어요'), findsOneWidget);
      expect(find.textContaining('web · 건너뜀'), findsOneWidget);
      expect(find.textContaining('db · '), findsNothing, reason: '성공한 항목은 보여주지 않는다');
      expect(btn('원인 분석'), findsOneWidget);
      expect(find.text(failureAnalysisDescription), findsOneWidget);
      expect(find.text(emptyRun), findsNothing);
    });

    testWidgets('원인 분석 카드는 헬스체크 결과 요약 카드 위에', (tester) async {
      await openRun(tester);
      expect(tester.getTopLeft(find.text('실행 실패 원인 분석')).dy, lessThan(tester.getTopLeft(find.text('헬스체크 결과 요약')).dy));
    });

    testWidgets('카드에서 키를 넣으면 머리의 키 상태도 바뀌고 [원인 분석]이 나온다', (tester) async {
      await runner.runAll('my-team-project');
      final keys = MemoryApiKeyStore();
      await openRun(tester, keys: keys, client: _StoreClient(keys));
      expect(btn('원인 분석'), findsNothing);
      final cardKeyButton = find.descendant(of: find.byType(FailureAnalysisPanel), matching: btn('키 입력'));
      expect(cardKeyButton, findsOneWidget);
      await tester.tap(cardKeyButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.new-key-1234wxyz');
      await tester.tap(btn('저장'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(StatusChip, 'API 키 입력됨'), findsOneWidget);
      expect(btn('원인 분석'), findsOneWidget);
    });
  });
}

/// 키가 있는지를 저장소에서 읽는 가짜 AI(진짜 Gemini 연결처럼).
class _StoreClient implements LlmClient {
  _StoreClient(this.keys);

  final ApiKeyStore keys;

  @override
  String get modelName => 'store-model';

  @override
  Future<bool> isConfigured() async => await keys.read() != null;

  @override
  Future<String> complete(String prompt, {String? system}) async => '{}';
}

/// OS 보안 저장소를 쓸 수 없는 컴퓨터.
class _BrokenStore implements ApiKeyStore {
  @override
  Future<String?> read() async => throw StateError('keychain locked');

  @override
  Future<void> write(String key) async => throw StateError('keychain locked');

  @override
  Future<void> delete() async => throw StateError('keychain locked');
}

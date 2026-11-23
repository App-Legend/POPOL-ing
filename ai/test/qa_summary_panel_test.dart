import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const storedKey = 'AQ.test-key-abcdefghijklmnop';
final checkedAt = DateTime(2026, 11, 22, 14, 5, 2);

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

/// 답을 붙잡고 있다가 [answer] 로 돌려주는 가짜 AI. 분석 중·취소·화면 떠남을 시험한다.
class HeldLlmClient implements LlmClient {
  final _reply = Completer<String>();
  final sent = <String>[];

  void answer(String reply) => _reply.complete(reply);

  @override
  String get modelName => 'held-model';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<String> complete(String prompt, {String? system}) {
    sent.add(prompt);
    return _reply.future;
  }
}

/// 키가 있는지를 저장소에서 읽는 가짜 AI(진짜 Gemini 연결처럼). [completeError] 를 주면 보낼 때 그 예외를 던진다.
class StoreLlmClient implements LlmClient {
  StoreLlmClient(this.keys, {this.completeError});

  final ApiKeyStore keys;
  final Object? completeError;

  @override
  String get modelName => 'store-model';

  @override
  Future<bool> isConfigured() async => await keys.read() != null;

  @override
  Future<String> complete(String prompt, {String? system}) async {
    if (completeError case final e?) throw e;
    return failedReply;
  }
}

/// OS 보안 저장소를 쓸 수 없는 컴퓨터.
class BrokenStore implements ApiKeyStore {
  @override
  Future<String?> read() async => throw StateError('keychain locked');

  @override
  Future<void> write(String key) async => throw StateError('keychain locked');

  @override
  Future<void> delete() async => throw StateError('keychain locked');
}

class Setup {
  Setup({Set<String> failing = const {'API 헬스'}})
      : projects = FakeProjectRepository.withSamples(),
        clock = (() => checkedAt) {
    qa = FakeQaRunner(projects, failing: failing, clock: () => clock());
    orchestrator = FakeOrchestrator(projects);
  }

  final FakeProjectRepository projects;
  DateTime Function() clock;
  late final FakeQaRunner qa;
  late final FakeOrchestrator orchestrator;
}

Future<void> show(WidgetTester tester, QaRun run, LlmClient ai, Setup s, {ApiKeyStore? keys, Key? key}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: QaSummaryPanel(key: key, run: run, client: ai, keys: keys ?? MemoryApiKeyStore(storedKey), qa: s.qa, orchestrator: s.orchestrator),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// [AI 요약] → 확인 창 [보내기].
Future<void> summarize(WidgetTester tester) async {
  await tester.tap(btn('AI 요약'));
  await tester.pumpAndSettle();
  await tester.tap(btn('보내기'));
  await tester.pumpAndSettle();
}

const failedReply = '{"sentences":[{"text":"API 헬스가 괜찮아요.","checks":[1]}]}';
const description = '검사 결과를 AI가 두세 문장으로 정리해요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.';
const afterNotice = '요약은 판정을 바꾸지 않아요. 통과·실패는 헬스체크 규칙 그대로예요. AI 결과는 틀릴 수 있으니 근거를 확인해 주세요.';
const working = '분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.';

void main() {
  testWidgets('AT-21: [보내기] 전·[취소]하면 요청 0건, 보낸 내용에 호스트·주소·키가 없다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final ai = FakeLlmClient(reply: failedReply);
    await show(tester, run, ai, s);
    expect(find.text(description), findsOneWidget);

    await tester.tap(btn('AI 요약'));
    await tester.pumpAndSettle();
    expect(find.text('이 내용을 Google로 보낼까요?'), findsOneWidget);
    expect(find.textContaining('헬스체크 결과 요약을 하려고'), findsOneWidget);
    expect(ai.sent, isEmpty);
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(ai.sent, isEmpty);
    expect(btn('AI 요약'), findsOneWidget, reason: '처음 상태로 돌아온다');

    await summarize(tester);
    final sent = ai.sent.single;
    expect(sent, contains('#1 API 헬스 · 실패'));
    expect(sent, isNot(contains('localhost')));
    expect(sent, isNot(contains('http')));
    expect(sent, isNot(contains(storedKey)));
  });

  testWidgets('AT-20: 모두 통과하고 직전도 통과면 확인 창 없이 고정 문구, 요청 0건', (tester) async {
    final s = Setup(failing: {});
    s.clock = () => checkedAt.subtract(const Duration(hours: 1));
    await s.qa.runChecks('shop-clone');
    s.clock = () => checkedAt;
    final run = await s.qa.runChecks('shop-clone');
    final ai = FakeLlmClient();
    await show(tester, run, ai, s);

    expect(find.text('모든 검사를 통과했어요.'), findsOneWidget);
    expect(btn('AI 요약'), findsNothing);
    expect(ai.sent, isEmpty);
  });

  testWidgets('AT-20: 요약 뒤에도 실패 라벨 그대로, 근거는 AI 글이 아니라 실제 값', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    await show(tester, run, FakeLlmClient(reply: failedReply), s);
    await summarize(tester);

    expect(find.text('API 헬스가 괜찮아요.'), findsOneWidget);
    expect(find.text('근거  API 헬스 · 실패 · 연결 거부 · 14:05'), findsOneWidget, reason: 'AI 가 괜찮다고 써도 근거에 실제 판정');
    expect(find.widgetWithText(StatusChip, '실패 · API 헬스'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, '설정 필요 · 관리자 페이지'), findsOneWidget);
    expect(find.text('요약 완료 · fake-model'), findsOneWidget);
    expect(find.text(afterNotice), findsOneWidget);
    expect(btn('다시 요약'), findsOneWidget);
  });

  testWidgets('AT-19: 키가 없으면 API 키 필요와 [키 입력], [AI 요약]은 없다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    await show(tester, run, FakeLlmClient(configured: false), s, keys: MemoryApiKeyStore());

    expect(find.text('API 키 필요'), findsOneWidget);
    expect(btn('키 입력'), findsOneWidget);
    expect(btn('AI 요약'), findsNothing);
  });

  testWidgets('오류는 llmErrorText 의 제목과 버튼으로 안내한다', (tester) async {
    for (final failure in [LlmFailure.invalidKey, LlmFailure.quotaExceeded, LlmFailure.network]) {
      final s = Setup();
      final run = await s.qa.runChecks('my-team-project');
      await show(tester, run, FakeLlmClient(failWith: failure), s, key: ValueKey(failure));
      await summarize(tester);
      final text = llmErrorText(failure);
      expect(find.text(text.title), findsOneWidget, reason: '$failure');
      expect(btn(text.action), findsOneWidget, reason: '$failure');
    }
  });

  testWidgets('[다시 시도]하면 다시 보낸다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final ai = FakeLlmClient(failWith: LlmFailure.network, reply: failedReply);
    await show(tester, run, ai, s);
    await summarize(tester);

    ai.failWith = null;
    await tester.tap(btn('다시 시도'));
    await tester.pumpAndSettle();
    await tester.tap(btn('보내기'));
    await tester.pumpAndSettle();
    expect(ai.sent, hasLength(2));
    expect(find.text('API 헬스가 괜찮아요.'), findsOneWidget);
  });

  testWidgets('답을 못 읽으면 AI 답을 읽지 못했어요와 [다시 요약]', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    await show(tester, run, FakeLlmClient(reply: '다 괜찮아요!'), s);
    await summarize(tester);

    expect(find.text('AI 답을 읽지 못했어요.'), findsOneWidget);
    expect(btn('다시 요약'), findsOneWidget);
  });

  testWidgets('분석 중 [취소]하면 분석을 멈췄어요, 늦게 온 답은 버린다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final ai = HeldLlmClient();
    await show(tester, run, ai, s);
    await summarize(tester);

    expect(find.text(working), findsOneWidget);
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(find.text('분석을 멈췄어요.'), findsOneWidget);
    expect(btn('AI 요약'), findsOneWidget);

    ai.answer(failedReply);
    await tester.pumpAndSettle();
    expect(find.text('API 헬스가 괜찮아요.'), findsNothing);
    expect(find.text('분석을 멈췄어요.'), findsOneWidget);
  });

  testWidgets('검사할 항목이 없으면 안내만, 요청 0건', (tester) async {
    final s = Setup();
    final empty = QaRun(projectId: 'algo-study', startedAt: checkedAt, trigger: QaTrigger.manual, results: const []);
    final ai = FakeLlmClient();
    await show(tester, empty, ai, s);

    expect(find.text('검사할 항목이 없어요.'), findsOneWidget);
    expect(btn('AI 요약'), findsNothing);
    expect(ai.sent, isEmpty);
  });

  testWidgets('목록에서 지워진 프로젝트(lastRun 이 예외)여도 패널은 그대로 쓴다', (tester) async {
    final s = Setup();
    final gone = QaRun(
      projectId: 'gone',
      startedAt: checkedAt,
      trigger: QaTrigger.manual,
      results: [QaResult(name: 'API 헬스', status: QaStatus.failed, checkedAt: checkedAt, failureReason: '연결 거부')],
    );
    final ai = FakeLlmClient(reply: failedReply);
    await show(tester, gone, ai, s);
    expect(btn('AI 요약'), findsOneWidget);

    await summarize(tester);
    expect(ai.sent.single, isNot(contains('[마지막 전체 실행]')));
    expect(find.text('API 헬스가 괜찮아요.'), findsOneWidget);
  });

  testWidgets('보안 저장소를 읽지 못하면 빈 카드 대신 그렇게 알리고 [다시 시도]', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final keys = BrokenStore();
    await show(tester, run, StoreLlmClient(keys), s, keys: keys);

    expect(tester.takeException(), isNull);
    expect(find.text('이 컴퓨터의 보안 저장소에서 API 키를 읽지 못했어요.'), findsOneWidget);
    expect(btn('다시 시도'), findsOneWidget);
    expect(btn('AI 요약'), findsNothing);
  });

  testWidgets('보낸 뒤 예상 못 한 오류가 나도 분석 중에 멈추지 않고 연결 오류로 안내', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final keys = MemoryApiKeyStore(storedKey);
    await show(tester, run, StoreLlmClient(keys, completeError: StateError('boom')), s, keys: keys);
    await summarize(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(working), findsNothing);
    expect(find.text(llmErrorText(LlmFailure.network).title), findsOneWidget);
    expect(btn('다시 시도'), findsOneWidget);
  });

  testWidgets('패널에서 키를 바꾸면 onKeysChanged 로 알린다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final keys = MemoryApiKeyStore();
    var changed = 0;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: QaSummaryPanel(run: run, client: StoreLlmClient(keys), keys: keys, qa: s.qa, orchestrator: s.orchestrator, onKeysChanged: () => changed++),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(btn('키 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.new-key-1234wxyz');
    await tester.tap(btn('저장'));
    await tester.pumpAndSettle();
    expect(changed, 1);
    expect(btn('AI 요약'), findsOneWidget);
  });

  testWidgets('답을 기다리다 화면을 떠나도 오류가 없다', (tester) async {
    final s = Setup();
    final run = await s.qa.runChecks('my-team-project');
    final ai = HeldLlmClient();
    await show(tester, run, ai, s);
    await summarize(tester);

    await tester.pumpWidget(const SizedBox());
    ai.answer(failedReply);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const storedKey = 'AQ.test-key-abcdefghijklmnop';
const realLine = 'Error: The module was compiled against a different Node.js version';
const goodReply = '{"candidates":[{"cause":"지어낸 줄: Error: fake","likelihood":"high","logs":[2],"env":[1],'
    '"fixes":["npm install 을 다시 해 주세요."]}]}';

ItemRef ref(String id) => ItemRef(projectId: 'my-team-project', serviceId: id);

final api = ItemResult(item: ref('api'), outcome: ItemOutcome.failed, reason: '시작하자마자 종료됐어요 (종료 코드 1).', exitCode: 1);
final run = RunSummary(
  projectId: 'my-team-project',
  startedAt: DateTime(2026, 11, 22, 14),
  finishedAt: DateTime(2026, 11, 22, 14, 0, 30),
  items: [ItemResult(item: ref('db'), outcome: ItemOutcome.ok), api],
);

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

/// 답을 붙잡고 있다가 [answer] 로 돌려주는 가짜 AI. 분석 중·취소를 시험한다.
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

/// 테스트 중에 로그를 바꿀 수 있는 [LogExcerpt].
class ChangingLogs implements LogExcerpt {
  ChangingLogs(this.lines);

  List<String> lines;

  @override
  Future<List<String>> tail(String projectId, String serviceId, {int lines = 50}) async => this.lines;
}

final projects = FakeProjectRepository.withSamples();

Future<void> open(
  WidgetTester tester, {
  required LlmClient client,
  ApiKeyStore? keys,
  LogExcerpt? logs,
  String? description,
  void Function(AnalysisRecord)? onRecord,
}) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: FailureAnalysisPanel(
          item: api,
          run: run,
          client: client,
          keys: keys ?? MemoryApiKeyStore(storedKey),
          projects: projects,
          logs: logs ?? FakeLogExcerpt(projects, logs: {('my-team-project', 'api'): ['Starting backend', realLine]}),
          envDiff: FakeEnvDiff(projects, changes: {
            'my-team-project': [const EnvChange(name: 'node', before: '20.11.0', after: '22.3.0')],
          }),
          description: description,
          onRecord: onRecord,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> analyze(WidgetTester tester, {String start = '원인 분석'}) async {
  await tester.tap(btn(start));
  await tester.pumpAndSettle();
  await tester.tap(btn('보내기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('records received result', (tester) async {
    final records = <AnalysisRecord>[];
    await open(tester, client: FakeLlmClient(reply: goodReply, modelName: 'gemini-flash-latest'), onRecord: records.add);
    await analyze(tester);
    expect(records, hasLength(1));
    final r = records.single;
    expect(r.kind, AnalysisKind.failure);
    expect(r.outcome, AnalysisOutcome.received);
    expect(r.projectId, 'my-team-project');
    expect(r.serviceId, 'api');
    expect(r.title, '지어낸 줄: Error: fake');
    expect(r.model, 'gemini-flash-latest');
    expect(r.body, contains('npm install'));
    expect(r.toJson().toString(), isNot(contains(storedKey)));
  });

  testWidgets('records failure', (tester) async {
    final records = <AnalysisRecord>[];
    await open(tester, client: FakeLlmClient(failWith: LlmFailure.network), onRecord: records.add);
    await analyze(tester);
    expect(records.single.outcome, AnalysisOutcome.failed);
  });

  testWidgets('cancel not recorded', (tester) async {
    final records = <AnalysisRecord>[];
    await open(tester, client: HeldLlmClient(), onRecord: records.add);
    await analyze(tester);
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(records, isEmpty);
  });

  testWidgets('AT-21: [보내기] 전과 [취소] 뒤 요청 0건, 실행 설정에 환경변수·주소 호스트가 없고 키가 없다', (tester) async {
    final ai = FakeLlmClient(reply: goodReply);
    await open(tester, client: ai);
    await tester.tap(btn('원인 분석'));
    await tester.pumpAndSettle();
    expect(find.text('이 내용을 Google로 보낼까요?'), findsOneWidget);
    expect(find.textContaining('실행 실패 원인 분석을 하려고'), findsOneWidget);
    expect(ai.sent, isEmpty);
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(ai.sent, isEmpty);

    await analyze(tester);
    expect(ai.sent, hasLength(1));
    expect(ai.sent.single, contains('[실행 설정] 명령 ./gradlew bootRun'));
    for (final secret in ['SPRING_PROFILES_ACTIVE', 'localhost', storedKey]) {
      expect(ai.sent.single, isNot(contains(secret)));
    }
  });

  testWidgets('AT-22: Node 20 → 22 로 실패하면 후보에 환경 차이와 실제 로그 줄', (tester) async {
    await open(tester, client: FakeLlmClient(reply: goodReply, modelName: 'gemini-flash-latest'));
    await analyze(tester);
    expect(find.text('원인 후보 · 가능성 높음'), findsOneWidget);
    expect(find.text('근거 로그 · api 마지막 실행'), findsOneWidget);
    expect(find.text(realLine), findsOneWidget, reason: '근거 칸은 AI 가 쓴 글이 아니라 실제 로그 줄');
    expect(find.text('Error: fake'), findsNothing);
    expect(find.text('환경 차이 · node 20.11.0 → 22.3.0'), findsOneWidget);
    expect(find.text('해결 방법'), findsOneWidget);
    expect(find.text('1. npm install 을 다시 해 주세요.'), findsOneWidget);
    expect(find.text('분석 완료 · gemini-flash-latest'), findsOneWidget);
    expect(find.text('AI 결과는 틀릴 수 있어요. 근거(로그 줄, 검사 항목)를 확인한 뒤 판단해 주세요.'), findsOneWidget);
    expect(btn('다시 분석'), findsOneWidget);
  });

  testWidgets('실패 이유가 근거면 실패 이유 칸을 보여 준다', (tester) async {
    await open(tester, client: FakeLlmClient(reply: '{"candidates":[{"cause":"바로 꺼졌어요.","reason":true}]}'));
    await analyze(tester);
    expect(find.text('원인 후보 · 가능성 있음'), findsOneWidget);
    expect(find.text('실패 이유 · 시작하자마자 종료됐어요 (종료 코드 1).'), findsOneWidget);
    expect(find.text('해결 방법'), findsNothing);
  });

  testWidgets('Review 1: 로그에 남은 비밀값은 가리고 몇 곳인지 알린다', (tester) async {
    final ai = FakeLlmClient(reply: goodReply);
    await open(tester, client: ai, logs: ChangingLogs(['Starting backend', 'DB_PASSWORD=hunter2']));
    await tester.tap(btn('원인 분석'));
    await tester.pumpAndSettle();
    expect(find.textContaining('비밀값으로 보이는 1곳을 가렸어요.'), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('send-preview'))).data, isNot(contains('hunter2')));
    await tester.tap(btn('보내기'));
    await tester.pumpAndSettle();
    expect(ai.sent.single, isNot(contains('hunter2')));
  });

  testWidgets('근거 로그 줄도 화면에서는 비밀값을 가린다', (tester) async {
    final ai = FakeLlmClient(reply: '{"candidates":[{"cause":"x","logs":[2]}]}');
    await open(tester, client: ai, logs: ChangingLogs(['Starting backend', 'DB_PASSWORD=hunter2']));
    await analyze(tester);
    expect(find.text('근거 로그 · api 마지막 실행'), findsOneWidget);
    expect(find.text('DB_PASSWORD=••••••'), findsOneWidget);
    expect(find.textContaining('hunter2'), findsNothing);
  });

  testWidgets('Review 5: [다시 분석]은 새 로그로 다시 보낸다', (tester) async {
    final ai = FakeLlmClient(reply: '{"candidates":[{"cause":"a","logs":[1]}]}');
    final logs = ChangingLogs(['처음 줄']);
    await open(tester, client: ai, logs: logs);
    await analyze(tester);
    expect(ai.sent.single, contains('#L1 처음 줄'));
    logs.lines = ['새 줄: port 8080 in use'];
    await analyze(tester, start: '다시 분석');
    expect(ai.sent, hasLength(2));
    expect(ai.sent.last, contains('#L1 새 줄: port 8080 in use'));
    expect(find.text('새 줄: port 8080 in use'), findsOneWidget);
  });

  testWidgets('AT-19: 키가 없으면 API 키 필요와 [키 입력], [원인 분석]은 없다', (tester) async {
    await open(tester, client: FakeLlmClient(configured: false), keys: MemoryApiKeyStore());
    expect(find.text('API 키 필요'), findsOneWidget);
    expect(btn('키 입력'), findsOneWidget);
    expect(btn('원인 분석'), findsNothing);
  });

  testWidgets('오류는 llmErrorText 로 안내한다', (tester) async {
    await open(tester, client: FakeLlmClient(failWith: LlmFailure.quotaExceeded));
    await analyze(tester);
    expect(find.text('사용량을 넘었어요'), findsOneWidget);
    expect(btn('다시 시도'), findsOneWidget);
  });

  testWidgets('답을 못 읽으면 AI 답을 읽지 못했어요와 [다시 분석]', (tester) async {
    await open(tester, client: FakeLlmClient(reply: 'not json'));
    await analyze(tester);
    expect(find.text('AI 답을 읽지 못했어요.'), findsOneWidget);
    expect(btn('다시 분석'), findsOneWidget);
  });

  testWidgets('분석 중 [취소]하면 분석을 멈췄어요, 늦은 답은 버린다', (tester) async {
    final ai = HeldLlmClient();
    await open(tester, client: ai);
    await analyze(tester);
    expect(find.text('분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.'), findsOneWidget);
    await tester.tap(btn('취소'));
    await tester.pumpAndSettle();
    expect(find.text('분석을 멈췄어요.'), findsOneWidget);
    ai.answer(goodReply);
    await tester.pumpAndSettle();
    expect(find.text('분석을 멈췄어요.'), findsOneWidget);
    expect(find.text('원인 후보 · 가능성 높음'), findsNothing);
  });

  testWidgets('설명은 넘길 때만 보인다', (tester) async {
    await open(tester, client: FakeLlmClient());
    expect(find.text(failureAnalysisDescription), findsNothing);
    expect(btn('원인 분석'), findsOneWidget);
    await open(tester, client: FakeLlmClient(), description: failureAnalysisDescription);
    expect(find.text(failureAnalysisDescription), findsOneWidget);
    expect(failureAnalysisRequestName, '실행 실패 원인 분석');
  });
}

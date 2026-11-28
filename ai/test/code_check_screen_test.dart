import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart';
import 'package:popoling_ai/src/code_check.dart';
import 'package:popoling_ai/src/code_check_screen.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const reply = '{"criteria":['
    '{"id":"config","level":"danger","reason":".env 가 .gitignore 에 없어요.","fix":".gitignore 에 .env 를 넣어 주세요.","evidence":[".gitignore:1"]},'
    '{"id":"quality","level":"caution","reason":"한 파일이 900줄이에요.","fix":"기능별로 나눠 주세요."},'
    '{"id":"performance","level":"good","reason":"큰 문제는 안 보여요."},'
    '{"id":"release","level":"caution","reason":"README 에 실행 방법이 없어요.","fix":"실행 방법을 적어 주세요."}'
    ']}';

final now = DateTime(2026, 11, 28, 15, 4);

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

/// 규칙 검사(C, #107) 대신 쓰는 가짜 재료.
class FakeSource implements CodeCheckSource {
  @override
  Future<List<CodeCheckFile>> filesToSend(String projectId) async => const [
        CodeCheckFile('README.md', '# my-team-project'),
        CodeCheckFile('api/config.js', 'const port = 8080;\nconst SECRET_KEY = "sk-live-abcdefghijklmnop";'),
      ];

  @override
  Future<Map<CheckCriterion, List<String>>> appFindings(String projectId) async => const {
        CheckCriterion.config: ['.gitignore 에 .env 없음'],
        CheckCriterion.release: ['테스트 파일 0개'],
      };
}

/// 보낸 글을 남기는 가짜 AI.
class CountingLlm implements LlmClient {
  final sent = <String>[];

  @override
  String get modelName => 'gemini-flash-latest';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<String> complete(String prompt, {String? system}) async {
    sent.add(prompt);
    return reply;
  }
}

Future<void> open(WidgetTester tester, {CodeCheckSource? source, LlmClient? client, CodeCheckStore? store}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: CodeCheckScreen(
      projects: FakeProjectRepository.withSamples(),
      keys: MemoryApiKeyStore('AQ.test-key-abcdefghij3F2A'),
      client: client ?? CountingLlm(),
      store: store ?? CodeCheckStore.memory(),
      source: source,
      clock: () => now,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('검사 전: 기준 4개가 검사 전이고, 규칙 검사가 없으면 시작 대신 안내', (tester) async {
    await open(tester);
    final criteria = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('criterion-'));
    expect(find.descendant(of: criteria, matching: find.text('검사 전')), findsNWidgets(4));
    expect(find.text('검사 기록 없음 · 검사 전'), findsWidgets);
    expect(btn('AI 검사 시작'), findsNothing);
    expect(find.textContaining('규칙 검사가 아직 준비 중'), findsOneWidget);
  });

  testWidgets('검사 전에도 앱이 확인 줄이 보인다', (tester) async {
    await open(tester, source: FakeSource());
    expect(find.text('앱이 확인 · .gitignore 에 .env 없음'), findsOneWidget);
    expect(find.text('앱이 확인 · 테스트 파일 0개'), findsOneWidget);
  });

  testWidgets('AT-33: 확인 창에 보낼 파일과 가린 비밀값, [보내기] 전 요청 0건, 결과는 글자 상태로', (tester) async {
    final client = CountingLlm();
    final store = CodeCheckStore.memory();
    await open(tester, source: FakeSource(), client: client, store: store);
    await tester.tap(btn('AI 검사 시작'));
    await tester.pumpAndSettle();

    final preview = tester.widget<SelectableText>(find.byKey(const Key('send-preview'))).data!;
    expect(preview, contains('[보낼 파일 2개] README.md, api/config.js'));
    expect(preview, contains('[가린 비밀값 1곳] api/config.js:2'));
    expect(preview, isNot(contains('sk-live-abcdefghijklmnop')));
    expect(find.textContaining('보내지 않는 것: .env처럼 비밀값만 담은 파일'), findsOneWidget);
    expect(client.sent, isEmpty);

    await tester.tap(btn('보내기'));
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(1));
    expect(find.text('위험'), findsOneWidget);
    expect(find.text('주의'), findsNWidgets(2));
    expect(find.text('좋음'), findsOneWidget);
    expect(find.text('.env 가 .gitignore 에 없어요.'), findsWidgets);
    expect(find.text('보낸 것: 고른 파일 2개 · 가린 비밀값 1개 · gemini-flash-latest · 11/28 15:04'), findsOneWidget);
    expect(find.textContaining('점수는 매기지 않아요'), findsOneWidget);
    expect((await store.load())['my-team-project']!.countsLabel, '위험 1 · 주의 2 · 좋음 1');
  });

  testWidgets('저장해 둔 결과를 처음부터 보이고, 검사함 필터로 거른다', (tester) async {
    final store = CodeCheckStore.memory();
    final sent = prepareCodeCheck(const [CodeCheckFile('README.md', '# x')], const {});
    await store.save(parseCodeCheck(reply, projectId: 'shop-clone', at: now, model: 'm', sent: sent)!);
    await open(tester, source: FakeSource(), store: store);
    expect(find.text('11/28 15:04 · 위험 1 · 주의 2 · 좋음 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '검사함'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('check-row-shop-clone')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-row-my-team-project')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('check-row-shop-clone')));
    await tester.pumpAndSettle();
    expect(btn('다시 검사'), findsOneWidget);
  });
}

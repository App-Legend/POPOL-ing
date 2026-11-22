import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/ai.dart';
import 'package:ppoling_ai/src/send_confirm_dialog.dart' show withObjectParticle;
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/models.dart';
import 'package:ppoling_core/ui.dart';

/// 버튼 하나만 있는 화면. 누르면 [onTap] 을 부른다.
Widget host(Future<void> Function(BuildContext) onTap) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Builder(builder: (c) => Center(child: Btn('열기', onPressed: () => onTap(c))))),
    );

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('보내기 전 확인 (AT-21)', () {
    const log = 'web 종료 코드 1\nVITE_API_KEY=abc123\nDB_PASSWORD=pw-from-env-file\nError: Cannot find module';

    testWidgets('[취소]하면 아무것도 보내지 않는다', (tester) async {
      desktop(tester);
      final ai = FakeLlmClient();
      String? result = 'unset';
      await tester.pumpWidget(host((c) async => result = await AiSender(ai).send(c, requestName: '실행 실패 원인 분석', content: log)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('이 내용을 Google로 보낼까요?'), findsOneWidget);
      expect(find.textContaining('실행 실패 원인 분석을 하려고'), findsOneWidget);

      await tester.tap(btn('취소'));
      await tester.pumpAndSettle();
      expect(ai.sent, isEmpty);
      expect(result, isNull);
    });

    testWidgets('창에 보이는 내용이 곧 보내는 내용이고, 비밀값과 저장된 키는 가려져 있다', (tester) async {
      desktop(tester);
      final ai = FakeLlmClient(reply: '원인 후보: Node 22');
      final keys = MemoryApiKeyStore('AQ.stored-key-abcdefghijklmnop');
      String? result;
      await tester.pumpWidget(host((c) async => result = await AiSender(ai, keys: keys).send(
            c,
            requestName: 'QA 결과 요약',
            content: '$log\n키: AQ.stored-key-abcdefghijklmnop',
            secrets: ['pw-from-env-file'],
          )));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final shown = tester.widget<SelectableText>(find.byKey(const Key('send-preview'))).data!;
      expect(shown, isNot(contains('abc123')));
      expect(shown, isNot(contains('pw-from-env-file')));
      expect(shown, isNot(contains('stored-key')));
      expect(shown, contains('VITE_API_KEY=••••••'));
      expect(find.textContaining('비밀값으로 보이는 3곳을 가렸어요.'), findsOneWidget);

      await tester.tap(btn('보내기'));
      await tester.pumpAndSettle();
      expect(ai.sent, [shown]);
      expect(result, '원인 후보: Node 22');
    });

    testWidgets('키가 없으면 창을 띄우지 않고 "키 없음"으로 알린다', (tester) async {
      desktop(tester);
      final ai = FakeLlmClient(configured: false);
      Object? caught;
      await tester.pumpWidget(host((c) async {
        try {
          await AiSender(ai).send(c, requestName: 'QA 결과 요약', content: 'x');
        } on LlmException catch (e) {
          caught = e.failure;
        }
      }));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(caught, LlmFailure.missingKey);
      expect(find.text('이 내용을 Google로 보낼까요?'), findsNothing);
    });

    testWidgets('onConfirmed 는 [보내기]를 누른 직후·보내기 전에 한 번, [취소]하면 부르지 않는다', (tester) async {
      desktop(tester);
      final ai = FakeLlmClient();
      final sentWhenConfirmed = <int>[];
      await tester.pumpWidget(host((c) async {
        await AiSender(ai).send(c, requestName: 'QA 결과 요약', content: 'x', onConfirmed: () => sentWhenConfirmed.add(ai.sent.length));
      }));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(btn('취소'));
      await tester.pumpAndSettle();
      expect(sentWhenConfirmed, isEmpty);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(btn('보내기'));
      await tester.pumpAndSettle();
      expect(sentWhenConfirmed, [0], reason: '보내기 전에 불렸다');
      expect(ai.sent, hasLength(1));
    });
  });

  group('API 키 입력', () {
    testWidgets('넣은 키는 가려서 보이고, [저장]하면 앞뒤 공백을 빼고 저장한다', (tester) async {
      desktop(tester);
      final keys = MemoryApiKeyStore();
      ApiKeyChange? change;
      await tester.pumpWidget(host((c) async => change = await showApiKeyDialog(c, keys)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('Gemini API 키 입력'), findsOneWidget);
      expect(find.text('https://aistudio.google.com/apikey'), findsOneWidget, reason: '키 만드는 주소');
      expect(btn('키 지우기'), findsNothing);
      expect(btn('연결 확인'), findsNothing, reason: '확인할 방법을 주지 않으면 버튼이 없다');
      expect(tester.widget<TextField>(find.byKey(const Key('api-key-field'))).obscureText, isTrue);

      await tester.enterText(find.byKey(const Key('api-key-field')), '  AQ.new-key  ');
      await tester.tap(btn('저장'));
      await tester.pumpAndSettle();
      expect(await keys.read(), 'AQ.new-key');
      expect(change, ApiKeyChange.saved);
    });

    testWidgets('빈 칸으로 [저장]하면 안내만 하고 저장하지 않는다', (tester) async {
      desktop(tester);
      final keys = MemoryApiKeyStore();
      await tester.pumpWidget(host((c) => showApiKeyDialog(c, keys)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(btn('저장'));
      await tester.pumpAndSettle();
      expect(find.text('API 키를 넣어 주세요.'), findsOneWidget);
      expect(await keys.read(), isNull);
    });

    testWidgets('키가 있으면 [키 지우기]로 지울 수 있다', (tester) async {
      desktop(tester);
      final keys = MemoryApiKeyStore('AQ.old-key');
      ApiKeyChange? change;
      await tester.pumpWidget(host((c) async => change = await showApiKeyDialog(c, keys)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(btn('키 지우기'));
      await tester.pumpAndSettle();
      expect(await keys.read(), isNull);
      expect(change, ApiKeyChange.deleted);
    });

    testWidgets('보안 저장소에 쓰지 못하면 창에 알리고 다시 시도할 수 있다', (tester) async {
      desktop(tester);
      final keys = _ReadOnlyStore('AQ.old-key');
      await tester.pumpWidget(host((c) => showApiKeyDialog(c, keys)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.new-key');
      await tester.tap(btn('저장'));
      await tester.pumpAndSettle();
      expect(find.text('키를 저장하지 못했어요. 이 컴퓨터의 보안 저장소를 쓸 수 없어요.'), findsOneWidget);
      expect(tester.widget<Btn>(btn('저장')).onPressed, isNotNull);

      await tester.tap(btn('키 지우기'));
      await tester.pumpAndSettle();
      expect(find.text('키를 지우지 못했어요. 이 컴퓨터의 보안 저장소를 쓸 수 없어요.'), findsOneWidget);
      expect(find.text('Gemini API 키 입력'), findsOneWidget, reason: '창은 닫히지 않는다');
    });

    group('[연결 확인]', () {
      /// 확인한 키를 남기고, [fail] 이 있으면 그 이유로 실패한다.
      List<String> checked = [];
      Future<void> Function(String) checker({LlmFailure? fail}) => (key) async {
            checked.add(key);
            if (fail != null) throw LlmException(fail);
          };

      setUp(() => checked = []);

      Future<void> openWith(WidgetTester tester, ApiKeyStore keys, Future<void> Function(String) check) async {
        desktop(tester);
        await tester.pumpWidget(host((c) => showApiKeyDialog(c, keys, check: check)));
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
      }

      testWidgets('넣은 키로 확인만 하고 저장하지 않는다', (tester) async {
        final keys = MemoryApiKeyStore();
        await openWith(tester, keys, checker());
        expect(find.textContaining('다른 내용은 보내지 않아요'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('api-key-field')), '  AQ.typed-key  ');
        await tester.tap(btn('연결 확인'));
        await tester.pumpAndSettle();
        expect(checked, ['AQ.typed-key']);
        expect(find.text('연결됐어요. [저장]을 누르면 이 키를 써요.'), findsOneWidget);
        expect(await keys.read(), isNull);
        expect(find.text('Gemini API 키 입력'), findsOneWidget, reason: '창은 그대로');
      });

      testWidgets('키가 맞지 않으면 키 오류 안내를 보여 준다', (tester) async {
        await openWith(tester, MemoryApiKeyStore(), checker(fail: LlmFailure.invalidKey));
        await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.wrong');
        await tester.tap(btn('연결 확인'));
        await tester.pumpAndSettle();
        expect(find.text(llmErrorText(LlmFailure.invalidKey).title), findsOneWidget);
        expect(find.text(llmErrorText(LlmFailure.invalidKey).body), findsOneWidget);
      });

      testWidgets('칸이 비어 있으면 저장된 키로 확인한다', (tester) async {
        await openWith(tester, MemoryApiKeyStore('AQ.old-key'), checker());
        await tester.tap(btn('연결 확인'));
        await tester.pumpAndSettle();
        expect(checked, ['AQ.old-key']);
        expect(find.text('연결됐어요. 저장된 키로 AI 분석을 쓸 수 있어요.'), findsOneWidget);
      });

      testWidgets('칸도 비고 저장된 키도 없으면 보내지 않고 안내만 한다', (tester) async {
        await openWith(tester, MemoryApiKeyStore(), checker());
        await tester.tap(btn('연결 확인'));
        await tester.pumpAndSettle();
        expect(checked, isEmpty);
        expect(find.text('API 키를 넣어 주세요.'), findsOneWidget);
      });

      testWidgets('키를 고치면 전 확인 결과를 지운다', (tester) async {
        await openWith(tester, MemoryApiKeyStore(), checker());
        await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.first');
        await tester.tap(btn('연결 확인'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.second');
        await tester.pump();
        expect(find.textContaining('연결됐어요'), findsNothing);
      });
    });

    testWidgets('[취소]하면 아무것도 바꾸지 않는다', (tester) async {
      desktop(tester);
      final keys = MemoryApiKeyStore('AQ.old-key');
      ApiKeyChange? change = ApiKeyChange.saved;
      await tester.pumpWidget(host((c) async => change = await showApiKeyDialog(c, keys)));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('api-key-field')), 'AQ.typed-but-cancelled');
      await tester.tap(btn('취소'));
      await tester.pumpAndSettle();
      expect(await keys.read(), 'AQ.old-key');
      expect(change, isNull);
    });
  });

  test('오류 안내는 네 가지가 서로 다르고, 모두 다음에 할 일을 버튼으로 준다', () {
    final texts = [for (final f in LlmFailure.values) llmErrorText(f)];
    expect({for (final t in texts) t.title}, hasLength(LlmFailure.values.length));
    expect(llmErrorText(LlmFailure.missingKey).action, '키 입력');
    expect(llmErrorText(LlmFailure.invalidKey).action, '키 바꾸기');
    expect(llmErrorText(LlmFailure.quotaExceeded).action, '다시 시도');
    expect(llmErrorText(LlmFailure.network).action, '다시 시도');
  });

  test('받침에 맞춰 을/를을 붙인다', () {
    expect(withObjectParticle('QA 결과 요약'), 'QA 결과 요약을');
    expect(withObjectParticle('코드 점검'), '코드 점검을');
    expect(withObjectParticle('프로젝트 파악'), '프로젝트 파악을');
    expect(withObjectParticle('오류 정리'), '오류 정리를');
    expect(withObjectParticle('Summary'), 'Summary을(를)');
  });
}

/// 읽기만 되고 쓰기·지우기는 실패하는 보안 저장소.
class _ReadOnlyStore implements ApiKeyStore {
  _ReadOnlyStore(this._key);

  final String _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => throw StateError('keychain locked');

  @override
  Future<void> delete() async => throw StateError('keychain locked');
}

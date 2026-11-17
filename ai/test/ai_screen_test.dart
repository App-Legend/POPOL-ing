import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/ai.dart';
import 'package:ppoling_ai/src/ai_screen.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/ui.dart';

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

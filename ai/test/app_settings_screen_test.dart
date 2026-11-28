import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/ai.dart';
import 'package:popoling_ai/src/app_settings_screen.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const fullKey = 'AQ.test-key-abcdefghij3F2A';

Finder btn(String label) => find.ancestor(of: find.text(label), matching: find.byType(Btn));

Future<void> open(WidgetTester tester, ApiKeyStore keys) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: AppSettingsScreen(keys: keys, client: FakeLlmClient(modelName: 'gemini-flash-latest')),
  ));
  await tester.pumpAndSettle();
}

/// 화면 어디에도 키 원문이 없다.
void expectNoRawKey(WidgetTester tester) {
  final texts = [
    for (final w in tester.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
    for (final w in tester.widgetList<SelectableText>(find.byType(SelectableText))) w.data ?? '',
  ];
  expect(texts.where((t) => t.contains(fullKey)), isEmpty);
}

void main() {
  testWidgets('#105: 키가 없으면 API 키 필요와 [키 입력]', (tester) async {
    await open(tester, MemoryApiKeyStore());
    expect(find.text('앱 설정'), findsWidgets);
    expect(find.text('API 키 필요'), findsOneWidget);
    expect(btn('키 입력'), findsOneWidget);
  });

  testWidgets('#105: 키가 있으면 끝 4자리와 [키 바꾸기], 원문은 없다', (tester) async {
    await open(tester, MemoryApiKeyStore(fullKey));
    expect(find.textContaining('••••••••3F2A'), findsOneWidget);
    expect(btn('키 바꾸기'), findsOneWidget);
    expectNoRawKey(tester);
  });

  testWidgets('#105: 8자 이하 키는 모두 가린다', (tester) async {
    await open(tester, MemoryApiKeyStore('short12'));
    expect(find.textContaining('••••••••'), findsOneWidget);
    expect(find.textContaining('rt12'), findsNothing);
  });

  testWidgets('#105: 키를 저장하면 바로 끝 4자리가 보인다', (tester) async {
    final keys = MemoryApiKeyStore();
    await open(tester, keys);
    await tester.tap(btn('키 입력'));
    await tester.pumpAndSettle();
    expect(btn('저장'), findsOneWidget, reason: '이어서 할 분석이 없으니 [나중에]·[저장하고 계속]이 아니다');
    await tester.enterText(find.byKey(const Key('api-key-field')), fullKey);
    await tester.tap(btn('저장'));
    await tester.pumpAndSettle();
    expect(await keys.read(), fullKey);
    expect(find.textContaining('••••••••3F2A'), findsOneWidget);
    expect(find.text('API 키를 저장했어요.'), findsOneWidget);
    expectNoRawKey(tester);
  });
}

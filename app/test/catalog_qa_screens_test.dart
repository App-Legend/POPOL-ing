import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling/main.dart';
import 'package:ppoling_core/ui.dart';

Future<void> _open(WidgetTester tester, String route) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PpolingApp(registry: buildRegistry(features: false)));
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
  await tester.pumpAndSettle();
}

// 화면 2(개발 홈) 동작은 진짜 화면이 들어온 `catalog/` 테스트에서 확인한다.
void main() {
  group('화면 6 QA 결과', () {
    testWidgets('상태 라벨이 잘리지 않는다', (tester) async {
      await _open(tester, '/qa');
      for (final label in ['통과', '실패', '설정 필요']) {
        final text = find.descendant(of: find.byType(StatusChip), matching: find.text(label));
        expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$label 라벨이 잘렸어요');
      }
    });
  });
}

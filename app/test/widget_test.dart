import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling/main.dart';

const _routes = ['/', '/dialogs'];

void main() {
  // 모든 목업 화면이 데스크톱 기본 크기에서 오류(넘침 포함) 없이 그려지는지 확인한다.
  for (final route in _routes) {
    testWidgets('$route 화면이 그려진다', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(PopolingApp(registry: buildRegistry(features: false)));
      if (route != '/') {
        tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}

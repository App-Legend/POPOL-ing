import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_runner/src/screens/exit_guard.dart';

const _api = ItemRef(projectId: 'demo', serviceId: 'api');
const _db = ItemRef(projectId: 'demo', serviceId: 'db');

void main() {
  late int stops;
  setUp(() => stops = 0);

  Future<void> pump(WidgetTester tester,
      {List<ItemRef> up = const [_db, _api], Future<List<ItemResult>> Function()? stop}) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) => ExitGuard(
        navigatorKey: navigator,
        stillUp: () async => up,
        stopEverything: () {
          stops++;
          return stop?.call() ?? Future.value(const []);
        },
        child: child!,
      ),
      home: const Scaffold(),
    ));
  }

  /// 운영체제가 닫기를 요청한 것처럼 부른다.
  Future<AppExitResponse> request(WidgetTester tester) => tester.binding.handleRequestAppExit();

  testWidgets('실행 중인 항목이 없으면 묻지 않고 닫는다', (tester) async {
    await pump(tester, up: const []);
    expect(await request(tester), AppExitResponse.exit);
    expect(stops, 0);
  });

  testWidgets('모두 종료는 다 멈춘 뒤에 닫는다', (tester) async {
    final done = Completer<List<ItemResult>>();
    await pump(tester, stop: () => done.future);
    AppExitResponse? response;
    unawaited(request(tester).then((r) => response = r));
    await tester.pumpAndSettle();
    expect(find.textContaining('demo — db, api'), findsOneWidget);

    await tester.tap(find.text('모두 종료하고 닫기'));
    await tester.pump();
    expect(find.textContaining('종료하는 중'), findsOneWidget);
    expect(response, isNull);
    done.complete(const []);
    await tester.pumpAndSettle();
    expect(response, AppExitResponse.exit);
    expect(stops, 1);
  });

  testWidgets('Enter 는 기본값인 모두 종료다', (tester) async {
    await pump(tester);
    final response = request(tester);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await response, AppExitResponse.exit);
    expect(stops, 1);
  });

  testWidgets('exit dialog has two buttons', (tester) async {
    await pump(tester);
    unawaited(request(tester));
    await tester.pumpAndSettle();
    expect(find.text('그대로 두고 닫기'), findsNothing);
    expect(find.text('모두 종료하고 닫기'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(find.textContaining('demo — db, api'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('취소와 Esc 는 닫지 않고, 다시 닫으면 또 묻는다', (tester) async {
    await pump(tester);
    var response = request(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(await response, AppExitResponse.cancel);

    response = request(tester);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await response, AppExitResponse.cancel);
    expect(stops, 0);
  });

  testWidgets('묻는 중에 또 닫으면 창을 겹쳐 띄우지 않는다', (tester) async {
    await pump(tester);
    final first = request(tester);
    await tester.pumpAndSettle();
    expect(await request(tester), AppExitResponse.cancel);
    await tester.pumpAndSettle();
    expect(find.text('취소'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(await first, AppExitResponse.cancel);
  });

  for (final (button, expected) in [('취소', AppExitResponse.cancel), ('그래도 닫기', AppExitResponse.exit)]) {
    testWidgets('멈추지 못하면 이유를 보여 주고 [$button]을 따른다', (tester) async {
      await pump(tester,
          stop: () async => const [ItemResult(item: _db, outcome: ItemOutcome.failed, reason: 'docker 응답 없음')]);
      final response = request(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('모두 종료하고 닫기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('docker 응답 없음'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(await response, expected);
    });
  }
}

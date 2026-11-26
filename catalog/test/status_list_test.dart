import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/src/run_info.dart';
import 'package:popoling_catalog/src/status_list.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

void main() {
  final now = DateTime(2026, 11, 27, 12);

  Future<List<Object?>> pump(WidgetTester tester) async {
    final opened = <Object?>[];
    final runs = FakeRunInfoSource({
      'shop-clone': RunInfo(lastRunAt: now.subtract(const Duration(hours: 1)), lastSucceeded: false),
      'weather-bot': RunInfo(lastRunAt: now.subtract(const Duration(days: 249)), lastSucceeded: true),
      'my-team-project': RunInfo(lastRunAt: now.subtract(const Duration(days: 1)), lastSucceeded: true),
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: StatusList(projects: FakeProjectRepository.withSamples(), runs: runs, clock: () => now)),
      onGenerateRoute: (s) {
        opened.add(s.arguments);
        return MaterialPageRoute(settings: s, builder: (_) => Text('열림 ${s.name}'));
      },
    ));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('shows failed and stale projects only', (tester) async {
    await pump(tester);
    expect(find.text('실패 · 눌러서 원인 보기'), findsOneWidget);
    expect(find.text('오래됨 · 8개월'), findsOneWidget);
    expect(find.text('shop-clone'), findsOneWidget);
    expect(find.text('weather-bot'), findsOneWidget);
    expect(find.text('my-team-project'), findsNothing);
  });

  testWidgets('heading shown with rows', (tester) async {
    await pump(tester);
    expect(find.text('지금 상태'), findsOneWidget);
  });

  testWidgets('nothing to show hides heading', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatusList(projects: FakeProjectRepository(), runs: FakeRunInfoSource(), clock: () => now)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('지금 상태'), findsNothing);
  });

  testWidgets('tapping failed opens dashboard with id', (tester) async {
    final opened = await pump(tester);
    await tester.tap(find.text('shop-clone'));
    await tester.pumpAndSettle();
    expect(find.text('열림 /dashboard'), findsOneWidget);
    expect(opened.last, 'shop-clone');
  });
}

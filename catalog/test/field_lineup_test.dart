import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/src/catalog_view.dart';
import 'package:popoling_catalog/src/field/field_lineup.dart';
import 'package:popoling_catalog/src/field/field_panel.dart';
import 'package:popoling_catalog/src/run_info.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/ui.dart';

final now = DateTime(2026, 11, 28, 10);

CatalogEntry entry(String id, RunInfo run, {int services = 1}) => CatalogEntry(
      Project(
        id: id,
        name: id,
        folderPath: '/projects/$id',
        registeredAt: DateTime(2026, 1, 1),
        config: ProjectConfig(services: [
          for (var i = 0; i < services; i++) ProcessService(id: 's$i', command: const ['npm', 'start']),
        ]),
      ),
      run,
    );

RunInfo running(int n) => RunInfo(lastRunAt: now, lastSucceeded: true, running: n);
RunInfo failed({int daysAgo = 1}) => RunInfo(lastRunAt: now.subtract(Duration(days: daysAgo)), lastSucceeded: false);
RunInfo stopped({int daysAgo = 1}) => RunInfo(lastRunAt: now.subtract(Duration(days: daysAgo)), lastSucceeded: true);

void main() {
  test('score counts every project, not only the first four lanes', () {
    final lineup = fieldLineup([
      for (var i = 0; i < 5; i++) entry('run$i', running(1)),
      entry('bad1', failed()),
      entry('bad2', failed()),
    ], now);
    expect(lineup.running, 5);
    expect(lineup.fallen, 2);
    expect(lineup.score, '달리는 중 5 · 넘어짐 2');
  });

  test('running status does not claim ready', () {
    final lineup = fieldLineup([entry('api', running(1), services: 2)], now);
    expect(lineup.lanes.single.status, '실행 중 · 1/2');
  });

  test('a stale project that failed stays on a lane as fallen', () {
    final lineup = fieldLineup([entry('old-bad', failed(daysAgo: 200))], now);
    expect(lineup.bench, isNull);
    expect(lineup.lanes.single.pose, FieldPose.fallen);
    expect(lineup.fallen, 1);
  });

  test('bench takes the oldest stale project and counts the rest', () {
    final lineup = fieldLineup([
      entry('old', stopped(daysAgo: 120)),
      entry('older', stopped(daysAgo: 300)),
      entry('oldest', stopped(daysAgo: 400)),
      entry('fresh', stopped()),
    ], now);
    expect(lineup.bench!.$1, 'oldest');
    expect(lineup.bench!.$2, endsWith('외 2개'));
    expect([for (final l in lineup.lanes) l.name], ['fresh']);
  });

  testWidgets('field fits a 1280x720 window without overflow', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lineup = fieldLineup([entry('a', running(1)), entry('b', stopped(daysAgo: 200))], now);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Row(children: [const Spacer(), FieldPanel(lineup: lineup)])),
    ));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp('달리는 중 1 · 넘어짐 0')), findsOneWidget);
  });
}

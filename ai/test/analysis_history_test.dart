import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/src/analysis_history.dart';

void main() {
  late Directory tmp;
  late File file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('popoling_ai_history_');
    file = File('${tmp.path}/ai-history.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  AnalysisRecord rec(String title, DateTime at, {AnalysisOutcome outcome = AnalysisOutcome.received}) => AnalysisRecord(
        kind: AnalysisKind.failure,
        projectId: 'my-team-project',
        serviceId: 'web',
        title: title,
        body: '해 볼 것: 포트를 바꿔 주세요.',
        sentSummary: 'web 로그(비밀값 가림)',
        model: 'fake-model',
        at: at,
        outcome: outcome,
      );

  test('history round trip', () async {
    final h = AnalysisHistory(() async => file);
    await h.add(rec('첫째', DateTime(2026, 11, 27, 10)));
    await h.add(rec('둘째', DateTime(2026, 11, 27, 11), outcome: AnalysisOutcome.failed));
    final list = await AnalysisHistory(() async => file).list();
    expect(list.map((r) => r.title), ['둘째', '첫째']);
    expect(list.first.outcome, AnalysisOutcome.failed);
    expect(list.last.serviceId, 'web');
    expect(list.last.at, DateTime(2026, 11, 27, 10));
  });

  test('history cap', () async {
    final h = AnalysisHistory(() async => file, max: 3);
    for (var i = 0; i < 4; i++) {
      await h.add(rec('$i', DateTime(2026, 11, 27, i)));
    }
    final list = await h.list();
    expect(list.map((r) => r.title), ['3', '2', '1']);
  });

  test('concurrent adds keep both', () async {
    final h = AnalysisHistory(() async => file);
    await Future.wait([h.add(rec('a', DateTime(2026, 11, 27, 1))), h.add(rec('b', DateTime(2026, 11, 27, 2)))]);
    expect((await h.list()).map((r) => r.title).toSet(), {'a', 'b'});
  });

  test('missing file is empty', () async {
    expect(await AnalysisHistory(() async => file).list(), isEmpty);
  });

  test('corrupt file not overwritten', () async {
    file.writeAsStringSync('not json');
    final h = AnalysisHistory(() async => file);
    await expectLater(h.list(), throwsA(isA<AnalysisHistoryCorrupt>()));
    await expectLater(h.add(rec('x', DateTime(2026))), throwsA(isA<AnalysisHistoryCorrupt>()));
    expect(file.readAsStringSync(), 'not json');
  });
}

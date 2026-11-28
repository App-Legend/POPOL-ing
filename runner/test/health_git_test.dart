import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_runner/src/git/git_adapter.dart';
import 'package:popoling_runner/src/screens/git_tab.dart';
import 'package:popoling_runner/src/screens/health_section.dart';

const _id = 'my-team-project';

/// 가짜가 아닌 QaRunner(샘플 라벨이 없어야 한다).
class _RealishQa implements QaRunner {
  _RealishQa(this.inner);
  final QaRunner inner;
  @override
  Future<QaRun> runChecks(String projectId, {QaTrigger trigger = QaTrigger.manual}) => inner.runChecks(projectId, trigger: trigger);
  @override
  Future<List<QaRun>> history(String projectId) => inner.history(projectId);
}

class _BrokenQa implements QaRunner {
  @override
  Future<QaRun> runChecks(String projectId, {QaTrigger trigger = QaTrigger.manual}) async => throw StateError('boom');
  @override
  Future<List<QaRun>> history(String projectId) async => throw StateError('boom');
}

class _Git extends GitAdapter {
  _Git(this.s);
  final GitStatus? s;
  @override
  Future<GitStatus?> status(String folder) async => s;
  @override
  Future<bool> fetch(String folder) async => false;
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
  await tester.pumpAndSettle();
}

void main() {
  final projects = FakeProjectRepository.withSamples();

  testWidgets('health sample label', (tester) async {
    await _pump(tester, HealthSection(projectId: _id, qa: FakeQaRunner(projects)));
    expect(find.text('샘플 · 진짜 검사 기능이 아직 없어요'), findsOneWidget);
  });

  testWidgets('no sample label for real runner', (tester) async {
    await _pump(tester, HealthSection(projectId: _id, qa: _RealishQa(FakeQaRunner(projects))));
    expect(find.text('샘플 · 진짜 검사 기능이 아직 없어요'), findsNothing);
  });

  testWidgets('health failure row', (tester) async {
    await _pump(tester, HealthSection(projectId: _id, qa: FakeQaRunner(projects, failing: {'API 헬스'})));
    expect(find.text('아직 헬스체크 결과가 없어요.'), findsOneWidget);
    await tester.tap(find.text('다시 검사'));
    await tester.pumpAndSettle();
    expect(find.text('실패 1'), findsOneWidget);
    expect(find.text('API 헬스'), findsOneWidget);
  });

  testWidgets('health summary slot gets the run', (tester) async {
    await _pump(tester, HealthSection(projectId: _id, qa: FakeQaRunner(projects), summary: (_, run) => Text('요약 ${run.results.length}')));
    await tester.tap(find.text('다시 검사'));
    await tester.pumpAndSettle();
    expect(find.textContaining('요약 '), findsOneWidget);
  });

  testWidgets('health error', (tester) async {
    await _pump(tester, HealthSection(projectId: _id, qa: _BrokenQa()));
    await tester.tap(find.text('다시 검사'));
    await tester.pumpAndSettle();
    expect(find.text('헬스체크를 하지 못했어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('git tab behind', (tester) async {
    await _pump(tester, GitTab(projectId: _id, projects: projects, git: _Git(const GitStatus(branch: 'dev', changed: 2, upstream: 'origin/dev', behind: 3))));
    expect(find.textContaining('3커밋 뒤처져 있어요', findRichText: true), findsOneWidget);
    expect(find.textContaining('커밋 안 한 변경 2개', findRichText: true), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
  });

  testWidgets('git tab not a repo', (tester) async {
    await _pump(tester, GitTab(projectId: _id, projects: projects, git: _Git(null)));
    expect(find.text('이 폴더는 Git 저장소가 아니에요'), findsOneWidget);
  });
}

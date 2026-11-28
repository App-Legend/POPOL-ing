import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling/ai_slots.dart';
import 'package:popoling/registry.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

const _id = 'my-team-project';

void main() {
  late FakeProjectRepository projects;
  late FakeQaRunner qa;
  late FakeLlmClient llm;
  late Registry app;

  setUp(() {
    projects = FakeProjectRepository.withSamples();
    qa = FakeQaRunner(projects, failing: {'API 헬스'});
    llm = FakeLlmClient();
    app = Registry();
  });

  Future<void> pump(WidgetTester tester, QaRun run) async {
    final summary = projectPanels(app).qaSummary!; // 등록 전에 만들어도 그릴 때 진짜 구현을 꺼낸다
    app
      ..provide<QaRunner>(qa)
      ..provide<Orchestrator>(FakeOrchestrator(projects))
      ..provide<LlmClient>(llm);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Builder(builder: (c) => summary(c, run)))));
    await tester.pumpAndSettle();
  }

  testWidgets('실패한 검사가 있으면 [AI 요약] 버튼을 보이고, 누르기 전에는 보내지 않는다', (tester) async {
    await pump(tester, await qa.runChecks(_id));
    expect(find.widgetWithText(Btn, 'AI 요약'), findsOneWidget);
    expect(llm.sent, isEmpty);
  });

  testWidgets('API 키가 없으면 [AI 요약] 대신 [키 입력]만 보인다', (tester) async {
    llm.configured = false;
    await pump(tester, await qa.runChecks(_id));
    expect(find.widgetWithText(Btn, '키 입력'), findsOneWidget);
    expect(find.widgetWithText(Btn, 'AI 요약'), findsNothing);
  });

  testWidgets('실패 안내 자리에 원인 분석 패널을 넣는다', (tester) async {
    final runner = FakeOrchestrator(projects, failing: {const ItemRef(projectId: _id, serviceId: 'web')});
    final failure = projectPanels(app).failure!;
    app
      ..provide<ProjectRepository>(projects)
      ..provide<Orchestrator>(runner)
      ..provide<LlmClient>(llm);
    final run = await runner.runAll(_id);
    final item = run.items.firstWhere((r) => r.outcome == ItemOutcome.failed);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Builder(builder: (c) => failure(c, item, run)))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Btn, '원인 분석'), findsOneWidget);
    expect(find.text(item.reason!), findsOneWidget, reason: 'API 키가 없어도 실행기가 준 실패 원인은 먼저 보여야 한다');
    expect(llm.sent, isEmpty);
  });
}

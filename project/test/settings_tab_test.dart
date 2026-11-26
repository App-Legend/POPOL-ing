import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_project/src/screens/settings_tab.dart';

void main() {
  Future<void> pump(WidgetTester tester, String id, {ProjectRepository? repo}) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SettingsTab(projectId: id, projects: repo ?? FakeProjectRepository.withSamples()))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows service command', (tester) async {
    await pump(tester, 'my-team-project');
    expect(find.text('./gradlew bootRun'), findsOneWidget);
    expect(find.text('2 · db 다음'), findsOneWidget);
    expect(find.text('동아리 행사 예약 웹서비스 (2025 캡스톤)'), findsOneWidget);
  });

  testWidgets('read only', (tester) async {
    await pump(tester, 'my-team-project');
    expect(find.text('저장'), findsNothing);
    expect(find.text('항목 추가'), findsNothing);
  });

  testWidgets('env file name only', (tester) async {
    await pump(tester, 'my-team-project');
    await tester.tap(find.text('api'));
    await tester.pumpAndSettle();
    expect(find.text('./backend/.env'), findsOneWidget);
    expect(find.text('./backend'), findsOneWidget);
  });

  testWidgets('no config', (tester) async {
    final repo = FakeProjectRepository(projects: [
      Project(id: 'empty', name: 'empty', folderPath: '/projects/empty', registeredAt: DateTime(2026)),
    ]);
    await pump(tester, 'empty', repo: repo);
    expect(find.text('실행 방법이 아직 없어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issues', (tester) async {
    final repo = FakeProjectRepository(projects: [
      Project(
        id: 'bad',
        name: 'bad',
        folderPath: '/projects/bad',
        registeredAt: DateTime(2026),
        configIssues: const [ConfigIssue(path: 'services[1].dependsOn', message: 'api와 web이 서로를 먼저 시작하라고 되어 있어요.')],
      ),
    ]);
    await pump(tester, 'bad', repo: repo);
    expect(find.text('설정 파일에 고칠 곳이 1개 있어요'), findsOneWidget);
    expect(find.textContaining('서로를 먼저 시작하라고'), findsOneWidget);
  });
}

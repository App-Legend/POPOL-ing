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

  testWidgets('실행 항목은 아직 고칠 수 없다', (tester) async {
    await pump(tester, 'my-team-project');
    expect(find.text('항목 추가'), findsNothing);
  });

  testWidgets('메모를 고치고 [메모 저장]을 누르면 저장소에 저장된다', (tester) async {
    final repo = FakeProjectRepository.withSamples();
    await pump(tester, 'my-team-project', repo: repo);
    await tester.enterText(find.byKey(const ValueKey('settings-memo')), '새 메모');
    await tester.tap(find.text('메모 저장'));
    await tester.pumpAndSettle();
    expect((await repo.getProject('my-team-project')).about.memo, '새 메모');
    expect((await repo.getProject('my-team-project')).about.summary, '동아리 행사 예약 웹서비스 (2025 캡스톤)', reason: '다른 소개 값은 그대로');
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
    expect(find.text('메모 저장'), findsNothing, reason: '읽지 못한 설정 위에 저장하면 원래 내용이 지워진다');
  });
}

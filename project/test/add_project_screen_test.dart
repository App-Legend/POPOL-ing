import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_project/src/screens/add_project_screen.dart';

const _folder = '/projects/shop-clone';
const _web = ProcessService(id: 'web', command: ['npm', 'run', 'dev'], cwd: './web');

void main() {
  late FakeProjectRepository repo;
  late List<Object?> opened;
  setUp(() {
    repo = FakeProjectRepository(existingFolders: [_folder]);
    opened = [];
  });

  /// [config] 는 미리 읽은 popoling.yaml, [issues] 는 형식 문제.
  Future<void> pump(WidgetTester tester,
      {String? picked = _folder, ProjectConfig? config, List<ConfigIssue> issues = const []}) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/': (_) => AddProjectScreen(
              projects: repo,
              pickFolder: () async => picked,
              readConfig: (p) async => p.copyWith(config: config, configIssues: issues),
            ),
        '/dashboard': (c) {
          opened.add(ModalRoute.of(c)!.settings.arguments);
          return const Text('프로젝트 화면');
        },
      },
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pickAndRegister(WidgetTester tester) async {
    await tester.tap(find.text('폴더 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('폴더를 고르면 경로와 폴더 이름이 채워진다', (tester) async {
    await pump(tester);
    expect(find.text('등록하기'), findsOneWidget);
    await tester.tap(find.text('폴더 고르기'));
    await tester.pumpAndSettle();
    expect(find.text(_folder), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('add-project-name'))).controller!.text, 'shop-clone');
  });

  testWidgets('폴더 고르기를 닫으면 아무것도 바뀌지 않는다', (tester) async {
    await pump(tester, picked: null);
    await tester.tap(find.text('폴더 고르기'));
    await tester.pumpAndSettle();
    expect(find.text('아직 고르지 않았어요'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '등록하기')).onPressed, isNull);
  });

  testWidgets('명령이 없는 폴더는 바로 등록하고 프로젝트 화면으로 간다', (tester) async {
    await pump(tester);
    await pickAndRegister(tester);
    final projects = await repo.listProjects();
    expect(projects.single.folderPath, _folder);
    expect(opened, [projects.single.id]);
  });

  testWidgets('명령이 있으면 등록 전에 명령 목록을 보여 주고, 취소하면 등록하지 않는다', (tester) async {
    await pump(tester, config: const ProjectConfig(services: [_web]));
    await pickAndRegister(tester);
    expect(find.text('이 폴더의 명령을 확인해 주세요'), findsOneWidget);
    expect(find.textContaining('web: npm run dev (작업 폴더: ./web)'), findsOneWidget);
    expect(await repo.listProjects(), isEmpty, reason: '확인 전에는 등록하지 않는다');

    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('취소')));
    await tester.pumpAndSettle();
    expect(await repo.listProjects(), isEmpty);
    expect(opened, isEmpty);
  });

  testWidgets('확인하고 등록하면 등록하고 프로젝트 화면으로 간다', (tester) async {
    await pump(tester, config: const ProjectConfig(services: [_web]));
    await pickAndRegister(tester);
    await tester.tap(find.text('확인하고 등록'));
    await tester.pumpAndSettle();
    final projects = await repo.listProjects();
    expect(projects.single.name, 'shop-clone');
    expect(opened, [projects.single.id]);
  });

  testWidgets('설정 파일에 문제가 있으면 등록하지 않고 고친 뒤 다시 등록하라고 알린다', (tester) async {
    // 등록해 두면 나중에 파일을 고쳤을 때 명령을 한 번도 확인받지 않고 실행할 수 있다
    await pump(tester, issues: const [ConfigIssue(path: 'services[0]', message: '형식이 틀렸어요', line: 3)]);
    await pickAndRegister(tester);
    expect(find.text('이 폴더의 명령을 확인해 주세요'), findsNothing);
    expect(find.textContaining('형식이 틀렸어요 (3번째 줄)'), findsOneWidget);
    expect(find.textContaining('고친 뒤 다시 등록해 주세요'), findsOneWidget);
    expect(await repo.listProjects(), isEmpty);
  });

  testWidgets('이미 등록된 폴더면 알리고 그 프로젝트로 이동할 수 있다', (tester) async {
    final existing = await repo.addProject(_folder);
    await pump(tester);
    await pickAndRegister(tester);
    expect(find.textContaining('이미 등록된 폴더예요'), findsOneWidget);
    await tester.tap(find.text('그 프로젝트로 이동'));
    await tester.pumpAndSettle();
    expect(opened, [existing.id]);
  });

  testWidgets('이름을 바꿔서 등록할 수 있다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('폴더 고르기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-project-name')), '쇼핑몰 클론');
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();
    expect((await repo.listProjects()).single.name, '쇼핑몰 클론');
  });
}

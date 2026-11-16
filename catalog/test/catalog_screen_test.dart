import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_catalog/src/catalog_screen.dart';
import 'package:ppoling_catalog/src/run_info.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/ui.dart';

final now = DateTime(2026, 11, 16, 15);

/// 카드에서 다른 화면으로 넘어간 기록.
class Opened {
  String? route;
  Object? arguments;
}

Future<Opened> open(WidgetTester tester, {ProjectRepository? projects, RunInfoSource? runs}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = Opened();
  WidgetBuilder page(String name) => (context) {
        opened
          ..route = name
          ..arguments = ModalRoute.of(context)!.settings.arguments;
        return Scaffold(body: Text('열린 화면 $name'));
      };
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: CatalogScreen(
      projects: projects ?? FakeProjectRepository.withSamples(),
      runs: runs ?? FakeRunInfoSource.samples(clock: () => now),
      clock: () => now,
    ),
    routes: {for (final r in ['/dashboard', '/settings', '/add-project']) r: page(r)},
  ));
  await tester.pumpAndSettle();
  return opened;
}

/// 화면에 보이는 카드의 프로젝트 ID, 보이는 순서대로.
List<String> shownCards(WidgetTester tester) => [
      for (final w in tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('catalog-card-'))))
        (w.key! as ValueKey<String>).value.substring('catalog-card-'.length),
    ];

Finder inCard(String id, Finder matching) => find.descendant(of: find.byKey(ValueKey('catalog-card-$id')), matching: matching);

Future<void> tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AT-13: 카드 5개에 설명·스택·마지막 실행일이 보인다', (tester) async {
    await open(tester);
    expect(find.text('내 프로젝트  5'), findsOneWidget);
    expect(shownCards(tester), hasLength(5));
    expect(inCard('my-team-project', find.text('동아리 행사 예약 웹서비스 (2025 캡스톤)')), findsOneWidget);
    expect(inCard('my-team-project', find.widgetWithText(Tag, 'Spring Boot')), findsOneWidget);
    expect(inCard('my-team-project', find.text('실행 중 3/3')), findsOneWidget);
    expect(inCard('my-team-project', find.text('마지막 실행 오늘 14:00 · 성공')), findsOneWidget);
    expect(inCard('ppoling', find.text('마지막 실행 어제 · 성공')), findsOneWidget);
    expect(inCard('weather-bot', find.text('마지막 실행 2026-03-12 · 실패')), findsOneWidget);
    expect(inCard('weather-bot', find.text('오래됨 · 8개월')), findsOneWidget);
    expect(inCard('algo-study', find.text('실행 기록 없음')), findsOneWidget);
  });

  testWidgets('AT-13: 태그 필터', (tester) async {
    await open(tester);
    await tapChip(tester, 'React');
    expect(shownCards(tester), ['my-team-project']);
  });

  testWidgets('AT-13: 오래 방치된 순 정렬', (tester) async {
    await open(tester);
    expect(shownCards(tester), ['my-team-project', 'ppoling', 'weather-bot', 'shop-clone', 'algo-study']);
    await tester.tap(find.byKey(const Key('catalog-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래 방치된 순').last);
    await tester.pumpAndSettle();
    expect(shownCards(tester), ['shop-clone', 'weather-bot', 'ppoling', 'my-team-project', 'algo-study']);
  });

  testWidgets('검색 결과가 없으면 안내 문구', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('catalog-search')), '없는이름');
    await tester.pumpAndSettle();
    expect(shownCards(tester), isEmpty);
    expect(find.text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.'), findsOneWidget);
  });

  testWidgets('등록한 프로젝트가 없으면 추가 안내', (tester) async {
    final opened = await open(tester, projects: FakeProjectRepository(), runs: FakeRunInfoSource());
    expect(find.text('아직 등록한 프로젝트가 없어요. 프로젝트 폴더를 추가하면 여기에 모여요.'), findsOneWidget);
    expect(find.text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.'), findsNothing);
    await tester.tap(find.text('프로젝트 추가').last);
    await tester.pumpAndSettle();
    expect(opened.route, '/add-project');
  });

  testWidgets('설정을 못 읽은 프로젝트도 카드가 나온다', (tester) async {
    final broken = Project(
      id: 'broken',
      name: 'broken',
      folderPath: '/projects/broken',
      registeredAt: DateTime(2026, 11, 1),
      configIssues: const [ConfigIssue(path: 'services', message: '목록으로 적어 주세요.')],
    );
    final opened = await open(tester, projects: FakeProjectRepository(projects: [broken]), runs: FakeRunInfoSource());
    expect(inCard('broken', find.text('설명이 없어요. README에서 가져오거나 직접 적어 주세요.')), findsOneWidget);
    expect(inCard('broken', find.text('실행 항목이 아직 없어요.')), findsOneWidget);
    await tester.tap(inCard('broken', find.text('실행 방법 설정하기')));
    await tester.pumpAndSettle();
    expect(opened.route, '/settings');
    expect(opened.arguments, 'broken');
  });

  testWidgets('[열기]는 프로젝트 ID 를 넘겨 대시보드로', (tester) async {
    final opened = await open(tester);
    await tester.tap(inCard('ppoling', find.text('열기')));
    await tester.pumpAndSettle();
    expect(opened.route, '/dashboard');
    expect(opened.arguments, 'ppoling');
  });

  testWidgets('고른 태그가 사라지면 전체로 돌아간다', (tester) async {
    final repo = FakeProjectRepository.withSamples();
    await open(tester, projects: repo);
    await tapChip(tester, 'Python');
    expect(shownCards(tester), ['algo-study']);
    await repo.removeProject('algo-study');
    await tester.pumpAndSettle();
    expect(shownCards(tester), hasLength(4));
    expect(find.widgetWithText(ChoiceChip, 'Python'), findsNothing);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '전체')).selected, isTrue);
  });

  testWidgets('실행 정보가 바뀌면 카드가 바로 바뀐다', (tester) async {
    final runs = FakeRunInfoSource.samples(clock: () => now);
    await open(tester, runs: runs);
    expect(inCard('ppoling', find.text('중지')), findsOneWidget);
    runs.update({'ppoling': RunInfo(lastRunAt: now, lastSucceeded: true, running: 1)});
    await tester.pumpAndSettle();
    expect(inCard('ppoling', find.text('실행 중 1/1')), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/src/catalog_screen.dart';
import 'package:popoling_catalog/src/orchestrator_run_info.dart';
import 'package:popoling_catalog/src/run_info.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

final now = DateTime(2026, 11, 16, 15);

/// 카드에서 다른 화면으로 넘어간 기록.
class Opened {
  String? route;
  Object? arguments;
}

Future<Opened> open(WidgetTester tester,
    {ProjectRepository? projects, RunInfoSource? runs, Orchestrator? runner, EnvChecker? env, QaRunner? qa, double width = 1280}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = Opened();
  final repo = projects ?? FakeProjectRepository.withSamples();
  WidgetBuilder page(String name) => (context) {
        opened
          ..route = name
          ..arguments = ModalRoute.of(context)!.settings.arguments;
        return Scaffold(body: Text('열린 화면 $name'));
      };
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: CatalogScreen(
      projects: repo,
      runs: runs ?? FakeRunInfoSource.samples(clock: () => now),
      runner: runner ?? FakeOrchestrator(repo),
      env: env,
      qa: qa,
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
  group('#44 실행 점검(FR-17)', () {
    testWidgets('오래된 카드에는 [실행 점검], 누르면 환경 점검 → 전체 실행 → 헬스체크', (tester) async {
      final repo = FakeProjectRepository.withSamples();
      final qa = FakeQaRunner(repo, clock: () => now);
      await open(tester, projects: repo, env: FakeEnvChecker(installed: {'node': '22.3.0'}), qa: qa);
      expect(inCard('shop-clone', find.text('실행 점검')), findsOneWidget);
      await tester.tap(inCard('shop-clone', find.text('실행 점검')));
      await tester.pumpAndSettle();
      expect(find.text('shop-clone: 지금도 실행돼요. 헬스체크(샘플) 1개 통과.'), findsOneWidget); // 진짜 QaRunner 가 아직 없다
      expect((await qa.history('shop-clone')).single.trigger, QaTrigger.staleCheck);
    });

    testWidgets('환경 점검에서 문제가 나오면 실행하지 않고 카드에 알린다', (tester) async {
      final repo = FakeProjectRepository.withSamples();
      final runner = FakeOrchestrator(repo);
      await open(tester, projects: repo, runner: runner, env: FakeEnvChecker(), qa: FakeQaRunner(repo, clock: () => now));
      await tester.tap(inCard('shop-clone', find.text('실행 점검')));
      await tester.pumpAndSettle();
      expect(inCard('shop-clone', find.text('환경 점검에서 문제 1개가 나와 실행하지 않았어요. 프로젝트 화면의 환경 점검 탭에서 확인해 주세요.')), findsOneWidget);
      expect(runner.stateOf(const ItemRef(projectId: 'shop-clone', serviceId: 'web')), isNot(ItemState.running));
    });

    testWidgets('점검 기능이 없으면 [전체 실행] 그대로', (tester) async {
      await open(tester);
      expect(inCard('shop-clone', find.text('실행 점검')), findsNothing);
      expect(inCard('shop-clone', find.text('전체 실행')), findsOneWidget);
    });
  });

  testWidgets('#99: 창이 좁아도(860) 필터 칩이 한 줄에 여러 개 들어간다', (tester) async {
    await open(tester, width: 860);
    expect(tester.takeException(), isNull);
    final all = tester.getTopLeft(find.widgetWithText(ChoiceChip, '전체'));
    final running = tester.getTopLeft(find.widgetWithText(ChoiceChip, '실행 중'));
    expect(running.dy, all.dy);
    expect(find.byKey(const Key('catalog-sort')), findsOneWidget);
  });

  testWidgets('AT-13: 카드 5개에 설명·스택·마지막 실행일이 보인다', (tester) async {
    await open(tester);
    expect(find.text('내 프로젝트  5'), findsOneWidget);
    expect(shownCards(tester), hasLength(5));
    expect(inCard('my-team-project', find.text('동아리 행사 예약 웹서비스 (2025 캡스톤)')), findsOneWidget);
    expect(inCard('my-team-project', find.widgetWithText(Tag, 'Spring Boot')), findsOneWidget);
    expect(inCard('my-team-project', find.text('실행 중 3/3')), findsOneWidget);
    expect(inCard('my-team-project', find.text('마지막 실행 오늘 14:00 · 성공')), findsOneWidget);
    expect(inCard('popoling', find.text('마지막 실행 어제 · 성공')), findsOneWidget);
    expect(inCard('weather-bot', find.text('마지막 실행 2026-03-12 · 실패')), findsOneWidget);
    expect(inCard('weather-bot', find.text('오래됨 · 8개월')), findsOneWidget);
    expect(inCard('algo-study', find.text('실행 방법 없음')), findsOneWidget);
  });

  testWidgets('AT-13: 태그 필터', (tester) async {
    await open(tester);
    await tapChip(tester, 'React');
    expect(shownCards(tester), ['my-team-project']);
  });

  testWidgets('AT-13: 오래 방치된 순 정렬', (tester) async {
    await open(tester);
    expect(shownCards(tester), ['my-team-project', 'popoling', 'weather-bot', 'shop-clone', 'algo-study']);
    await tester.tap(find.byKey(const Key('catalog-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래 방치된 순').last);
    await tester.pumpAndSettle();
    expect(shownCards(tester), ['shop-clone', 'weather-bot', 'popoling', 'my-team-project', 'algo-study']);
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
    expect(find.text('첫 프로젝트를 등록해 주세요'), findsOneWidget);
    expect(find.text('명령은 처음 실행할 때 목록을 보여주고 확인받은 뒤에만 실행해요.'), findsOneWidget);
    expect(find.text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.'), findsNothing);
    await tester.tap(find.text('프로젝트 폴더 고르기'));
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
    expect(inCard('broken', find.text('설명이 아직 없어요. README에서 가져오거나 직접 적어 주세요.')), findsOneWidget);
    expect(inCard('broken', find.text('실행 방법 없음')), findsOneWidget);
    expect(inCard('broken', find.text('전체 실행')), findsNothing);
    await tester.tap(inCard('broken', find.text('열기')));
    await tester.pumpAndSettle();
    expect(opened.route, '/dashboard');
    expect(opened.arguments, 'broken');
  });

  testWidgets('failed card shows 원인 보기', (tester) async {
    final opened = await open(tester);
    expect(inCard('weather-bot', find.text('전체 실행')), findsNothing);
    await tester.tap(inCard('weather-bot', find.text('원인 보기')));
    await tester.pumpAndSettle();
    expect(opened.route, '/dashboard');
    expect(opened.arguments, 'weather-bot');
  });

  testWidgets('filter running', (tester) async {
    await open(tester);
    await tapChip(tester, '실행 중');
    expect(shownCards(tester), ['my-team-project']);
  });

  testWidgets('search by stack', (tester) async {
    await open(tester);
    expect(find.widgetWithText(TextField, '이름·설명·기술로 찾기'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('catalog-search')), 'Python');
    await tester.pumpAndSettle();
    expect(shownCards(tester), ['algo-study']);
  });

  testWidgets('long name', (tester) async {
    final long = Project(id: 'long', name: '2025-2학기-캡스톤-동아리-행사-예약-웹서비스-최종-진짜최종' * 3, folderPath: '/projects/long', registeredAt: DateTime(2026, 11, 1));
    await open(tester, projects: FakeProjectRepository(projects: [long]), runs: FakeRunInfoSource());
    expect(tester.takeException(), isNull);
  });

  testWidgets('[열기]는 프로젝트 ID 를 넘겨 대시보드로', (tester) async {
    final opened = await open(tester);
    await tester.tap(inCard('popoling', find.text('열기')));
    await tester.pumpAndSettle();
    expect(opened.route, '/dashboard');
    expect(opened.arguments, 'popoling');
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
    expect(inCard('popoling', find.text('중지')), findsOneWidget);
    runs.update({'popoling': RunInfo(lastRunAt: now, lastSucceeded: true, running: 1)});
    await tester.pumpAndSettle();
    expect(inCard('popoling', find.text('실행 중 1/1')), findsOneWidget);
  });

  group('카드의 [전체 실행]·[전체 종료]', () {
    late FakeProjectRepository repo;
    late FakeOrchestrator runner;

    setUp(() {
      repo = FakeProjectRepository.withSamples();
      runner = FakeOrchestrator(repo);
    });

    /// 카드 상태도 같은 Orchestrator 에서 읽게 연다.
    Future<Opened> openLive(WidgetTester tester, {Orchestrator? using}) =>
        open(tester, projects: repo, runs: OrchestratorRunInfoSource(using ?? runner, repo), runner: using ?? runner);

    Future<void> tapInCard(WidgetTester tester, String id, String label) async {
      await tester.tap(inCard(id, find.text(label)));
      await tester.pumpAndSettle();
    }

    testWidgets('[전체 실행]을 누르면 실행하고 카드가 실행 중으로 바뀐다', (tester) async {
      await openLive(tester);
      await tapInCard(tester, 'popoling', '전체 실행');
      expect(inCard('popoling', find.text('실행 중 1/1')), findsOneWidget);
      expect(inCard('popoling', find.text('전체 종료')), findsOneWidget);
      expect(find.text('popoling: 모두 실행됐어요.'), findsOneWidget);
    });

    testWidgets('[전체 종료]를 누르면 멈추고 다시 [전체 실행]이 나온다', (tester) async {
      await runner.runAll('popoling');
      await openLive(tester);
      await tapInCard(tester, 'popoling', '전체 종료');
      expect(inCard('popoling', find.text('중지')), findsOneWidget);
      expect(inCard('popoling', find.text('전체 실행')), findsOneWidget);
      expect(find.text('popoling: 모두 멈췄어요.'), findsOneWidget);
    });

    testWidgets('실패하면 카드에 한 줄 요약', (tester) async {
      runner.failing.add(const ItemRef(projectId: 'my-team-project', serviceId: 'api'));
      final opened = await openLive(tester);
      await tapInCard(tester, 'my-team-project', '전체 실행');
      expect(inCard('my-team-project', find.text('시작하지 못한 항목: api · 건너뜀: web')), findsOneWidget);
      expect(inCard('my-team-project', find.text('실행 중 1/3')), findsOneWidget);
      expect(find.textContaining('모두 실행됐어요'), findsNothing);
      await tapInCard(tester, 'my-team-project', '열기');
      expect(opened.route, '/dashboard');
      expect(opened.arguments, 'my-team-project');
    });

    testWidgets('실행하는 동안에는 버튼을 다시 누를 수 없다', (tester) async {
      final slow = _SlowOrchestrator(repo);
      await openLive(tester, using: slow);
      await tester.tap(inCard('popoling', find.text('전체 실행')));
      await tester.pump();
      final busy = inCard('popoling', find.widgetWithText(Btn, '시작하는 중…'));
      expect(busy, findsOneWidget);
      expect(tester.widget<Btn>(busy).onPressed, isNull);
      slow.gate.complete();
      await tester.pumpAndSettle();
      expect(inCard('popoling', find.text('실행 중 1/1')), findsOneWidget);
    });

    testWidgets('실행 요청이 예외로 끝나도 카드에 알린다', (tester) async {
      await openLive(tester, using: _ThrowingOrchestrator(repo));
      await tapInCard(tester, 'popoling', '전체 실행');
      expect(inCard('popoling', find.text('실행하지 못했어요.')), findsOneWidget);
      expect(inCard('popoling', find.text('전체 실행')), findsOneWidget, reason: '다시 시도할 수 있다');
    });
  });
}

/// [gate] 를 열 때까지 전체 실행이 끝나지 않는다.
class _SlowOrchestrator extends FakeOrchestrator {
  _SlowOrchestrator(super.projects);

  final gate = Completer<void>();

  @override
  Future<RunSummary> runAll(String projectId) async {
    await gate.future;
    return super.runAll(projectId);
  }
}

/// 약속에 없는 오류로 전체 실행이 끝난다.
class _ThrowingOrchestrator extends FakeOrchestrator {
  _ThrowingOrchestrator(super.projects);

  @override
  Future<RunSummary> runAll(String projectId) async => throw StateError('실행기가 멈췄습니다');
}

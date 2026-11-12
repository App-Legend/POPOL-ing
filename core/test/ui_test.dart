import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/ui.dart';

Widget _host(Widget child, {Map<String, WidgetBuilder> routes = const {}}) => MaterialApp(
      theme: buildTheme(),
      routes: routes,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('AppPage: 경로를 보여주고, 로고를 누르면 첫 화면으로 간다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Text('첫 화면'),
      routes: {
        '/second': (_) => const AppPage(crumbs: [('개발', '/home'), ('현재 화면', null)], children: [Text('본문')]),
      },
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/second');
    await tester.pumpAndSettle();

    expect(find.text('포폴링'), findsOneWidget);
    expect(find.text('개발'), findsOneWidget);
    expect(find.text('현재 화면'), findsOneWidget);
    expect(find.text('본문'), findsOneWidget);

    await tester.tap(find.text('포폴링'));
    await tester.pumpAndSettle();
    expect(find.text('첫 화면'), findsOneWidget);
    expect(find.text('본문'), findsNothing);
  });

  testWidgets('PageHead: 제목·설명·버튼이 보이고, 눌 수 없는 버튼은 비활성이다', (tester) async {
    await tester.pumpWidget(_host(const PageHead(title: '제목', sub: '설명', actions: [Btn('저장', onPressed: null)])));
    expect(find.text('제목'), findsOneWidget);
    expect(find.text('설명'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });

  testWidgets('Btn: 기본은 눌리고, onPressed가 null이면 비활성이다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(Column(children: [
      Btn('보통', onPressed: () => taps++),
      const Btn('주요', primary: true),
      const Btn('끔', onPressed: null, primary: true),
    ])));
    await tester.tap(find.text('보통'));
    expect(taps, 1);
    final filled = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(filled[0].onPressed, isNotNull);
    expect(filled[1].onPressed, isNull);
  });

  testWidgets('StatusChip: 색만이 아니라 라벨 텍스트가 보이고, dot 여부를 고른다', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      StatusChip('실행 중', C.ok),
      StatusChip('점 없음', C.bad, dot: false),
    ])));
    expect(find.text('실행 중'), findsOneWidget);
    expect(find.text('점 없음'), findsOneWidget);

    bool hasDot(String label) {
      final chip = find.ancestor(of: find.text(label), matching: find.byType(StatusChip));
      return find
          .descendant(of: chip, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle))
          .evaluate()
          .isNotEmpty;
    }

    expect(hasDot('실행 중'), isTrue);
    expect(hasDot('점 없음'), isFalse);
  });

  testWidgets('Tag: 라벨이 보인다', (tester) async {
    await tester.pumpWidget(_host(const Row(children: [Tag('Flutter'), Tag('원격', tone: C.remote)])));
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('원격'), findsOneWidget);
  });

  testWidgets('Panel: 제목과 본문이 보이고, 제목이 없으면 제목 줄이 없다', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      Panel(title: '패널 제목', titleAction: Text('동작'), child: Text('패널 본문')),
      Panel(child: Text('제목 없음')),
    ])));
    expect(find.text('패널 제목'), findsOneWidget);
    expect(find.text('동작'), findsOneWidget);
    expect(find.text('패널 본문'), findsOneWidget);
    expect(find.text('제목 없음'), findsOneWidget);
  });

  testWidgets('KeyValues: 이름과 값이 함께 보인다', (tester) async {
    await tester.pumpWidget(_host(const KeyValues([('경로', Text('~/projects')), ('스택', Text('Flutter'))])));
    expect(find.text('경로'), findsOneWidget);
    expect(find.text('~/projects'), findsOneWidget);
    expect(find.text('스택'), findsOneWidget);
    expect(find.text('Flutter'), findsOneWidget);
  });

  testWidgets('SimpleTable: 머리행과 내용 행이 보인다', (tester) async {
    await tester.pumpWidget(_host(const SimpleTable(columns: ['이름', '상태'], rows: [
      [Text('api'), Text('실행 중')],
      [Text('web'), Text('멈춤')],
    ])));
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('상태'), findsOneWidget);
    expect(find.text('api'), findsOneWidget);
    expect(find.text('멈춤'), findsOneWidget);
  });

  testWidgets('Notice: 안내 문구와 오른쪽 요소가 보인다', (tester) async {
    await tester.pumpWidget(_host(const Notice(
      bg: Color(0xFFFFF3D6),
      border: Color(0xFFE8D29A),
      icon: Icons.warning_amber,
      trailing: [Text('확인')],
      child: Text('포트가 사용 중이에요'),
    )));
    expect(find.text('포트가 사용 중이에요'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('AutoGrid: 너비에 따라 열 수가 바뀐다', (tester) async {
    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_host(AutoGrid(
        minItemWidth: 200,
        gap: 16,
        children: [for (var i = 0; i < 6; i++) Text('칸$i')],
      )));
    }

    addTearDown(tester.view.reset);
    await pumpAt(1000); // (1000+16)/(216) = 4열
    expect(tester.getTopLeft(find.text('칸0')).dy, tester.getTopLeft(find.text('칸3')).dy);
    expect(tester.getTopLeft(find.text('칸4')).dy, greaterThan(tester.getTopLeft(find.text('칸0')).dy));

    await pumpAt(300); // 1열
    expect(tester.getTopLeft(find.text('칸1')).dy, greaterThan(tester.getTopLeft(find.text('칸0')).dy));
  });

  testWidgets('logLine: 시간·수준·메시지·덧붙임을 한 줄로 만든다', (tester) async {
    final span = logLine('12:00', 'WARN', '느려요', note: '(3초)');
    expect(span.toPlainText(), '12:00  WARN  느려요 (3초)\n');
  });

  testWidgets('field: 라벨·힌트·값이 보인다', (tester) async {
    await tester.pumpWidget(_host(Padding(padding: const EdgeInsets.all(16), child: field('이름', 'my-app', hint: '필수'))));
    expect(find.textContaining('이름'), findsOneWidget);
    expect(find.textContaining('필수'), findsOneWidget);
    expect(find.text('my-app'), findsOneWidget);
  });

  testWidgets('dropdown: 라벨과 첫 항목이 보인다', (tester) async {
    await tester.pumpWidget(_host(Padding(padding: const EdgeInsets.all(16), child: dropdown('종류', ['process', 'compose']))));
    expect(find.text('종류'), findsOneWidget);
    expect(find.text('process'), findsOneWidget);
  });

  test('buildTheme: 배경색과 주 색을 시안 값으로 쓴다', () {
    final theme = buildTheme();
    expect(theme.scaffoldBackgroundColor, C.bg);
    expect(theme.colorScheme.primary, C.primary);
  });
}

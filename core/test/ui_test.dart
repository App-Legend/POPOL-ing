import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/ui.dart';

Widget _host(Widget child, {Map<String, WidgetBuilder> routes = const {}}) => MaterialApp(
      theme: buildTheme(),
      routes: routes,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('DialogBody·closeDialog: 대화상자로 열면 결과를 돌려주며 닫히고, 화면에 박혀 있으면 그대로 있다', (tester) async {
    Widget body(BuildContext context) => DialogBody('제목', [Btn('확인', onPressed: () => closeDialog(context, 'ok'))]);

    String? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(builder: (context) => Scaffold(body: Column(children: [
            Btn('열기', onPressed: () async => result = await showDialog<String>(context: context, builder: (c) => Dialog(child: body(c)))),
            body(context),
          ]))),
    ));

    // 화면에 박힌 본문의 [확인]은 아무것도 닫지 않는다.
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('제목'), findsNWidgets(2));
    await tester.tap(find.text('확인').last);
    await tester.pumpAndSettle();
    expect(find.text('제목'), findsOneWidget);
    expect(result, 'ok');
  });

  testWidgets('AppPage: 상위 화면 링크를 보여주고, 로고를 누르면 첫 화면으로 간다', (tester) async {
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
    expect(find.text('개발'), findsOneWidget, reason: '상위 화면으로 돌아가는 링크');
    expect(find.text('현재 화면'), findsNothing, reason: '현재 화면 이름은 본문 제목이 보여 준다');
    expect(find.text('본문'), findsOneWidget);

    await tester.tap(find.text('포폴링'));
    await tester.pumpAndSettle();
    expect(find.text('첫 화면'), findsOneWidget);
    expect(find.text('본문'), findsNothing);
  });

  Future<NavigatorState> pumpShell(WidgetTester tester, {Widget? status, String crumb = '현재 화면'}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (_, child) => ShellScope(status: status, child: child!),
      home: const Text('첫 화면'),
      routes: {
        '/second': (_) => AppPage(crumbs: [('내 프로젝트', '/home'), (crumb, null)], children: const [Text('본문')]),
        '/home': (_) => const Text('홈 화면'),
      },
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/second');
    await tester.pumpAndSettle();
    return nav;
  }

  testWidgets('AppPage shows side menu', (tester) async {
    await pumpShell(tester);
    expect(find.text('카테고리 · 개발'), findsOneWidget);
    expect(find.text('내 프로젝트'), findsWidgets);
    expect(find.text('AI 검사'), findsOneWidget);
    expect(find.text('앱 설정'), findsOneWidget); // 화면은 ai/ 가 /app-settings 로 등록한다(#105)
  });

  testWidgets('menu navigates', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('menu-/home')));
    await tester.pumpAndSettle();
    expect(find.text('홈 화면'), findsOneWidget);
  });

  testWidgets('status slot', (tester) async {
    await pumpShell(tester, status: const Text('X'));
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets('long status list scrolls instead of overflowing', (tester) async {
    await pumpShell(tester, status: Column(children: [for (var i = 0; i < 40; i++) SizedBox(height: 48, child: Text('항목 $i'))]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long crumb ellipsis', (tester) async {
    await pumpShell(tester, crumb: '2025-2학기-캡스톤-동아리-행사-예약-웹서비스-최종-진짜최종' * 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmStopOther: 취소면 false, 중지면 true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Builder(builder: (c) => Btn('열기', onPressed: () async => result = await confirmStopOther(c, project: 'shop-clone', service: 'web')))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('다른 프로젝트의 shop-clone / web을 중지할까요?'), findsOneWidget);
    expect(find.textContaining('포폴링이 시작한 항목이라 중지할 수 있어요'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isFalse, reason: 'Enter 기본값은 취소');
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '중지'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
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

  testWidgets('Panel: danger 면 제목 앞에 경고 아이콘을 붙인다', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      Panel(title: 'web이 실패한 이유', danger: true, child: Text('본문')),
    ])));
    expect(find.text('web이 실패한 이유'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
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

  testWidgets('field: obscure 면 값을 가린다', (tester) async {
    await tester.pumpWidget(_host(Padding(padding: const EdgeInsets.all(16), child: field('API 키', 'AIza-secret', obscure: true))));
    expect(tester.widget<EditableText>(find.byType(EditableText)).obscureText, isTrue);
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

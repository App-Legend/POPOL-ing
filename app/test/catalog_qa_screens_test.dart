import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling/main.dart';
import 'package:ppoling/ui/common.dart';

const _names = ['my-team-project', 'ppoling', 'weather-bot', 'shop-clone', 'algo-study'];

Future<void> _open(WidgetTester tester, String route) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PpolingApp(registry: buildRegistry()));
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
  await tester.pumpAndSettle();
}

/// 화면에 보이는 프로젝트 카드 이름, 보이는 순서대로.
List<String> _shown(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (_names.contains(t.data)) t.data!,
    ];

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

Future<void> _sort(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('화면 2 개발 홈', () {
    testWidgets('처음에는 다섯 개 모두 최근 실행순으로 보인다', (tester) async {
      await _open(tester, '/home');
      expect(_shown(tester), _names);
    });

    testWidgets('실행 중 · 오래됨 · 기술 스택 필터', (tester) async {
      await _open(tester, '/home');
      await _filter(tester, '실행 중');
      expect(_shown(tester), ['my-team-project']);
      await _filter(tester, '오래됨');
      expect(_shown(tester), ['weather-bot', 'shop-clone']);
      await _filter(tester, 'React');
      expect(_shown(tester), ['my-team-project']);
      await _filter(tester, '전체');
      expect(_shown(tester), _names);
    });

    testWidgets('검색은 이름·설명·기술 스택에서 대소문자 구분 없이 찾는다', (tester) async {
      await _open(tester, '/home');
      await _search(tester, 'node');
      expect(_shown(tester), ['weather-bot']);
      await _search(tester, '디스코드');
      expect(_shown(tester), ['weather-bot']);
      await _search(tester, 'SHOP');
      expect(_shown(tester), ['shop-clone']);
    });

    testWidgets('검색과 필터를 함께 쓴다', (tester) async {
      await _open(tester, '/home');
      await _filter(tester, '오래됨');
      await _search(tester, 'next');
      expect(_shown(tester), ['shop-clone']);
    });

    testWidgets('맞는 프로젝트가 없으면 안내 문구를 보여준다', (tester) async {
      await _open(tester, '/home');
      await _search(tester, 'zzz');
      expect(_shown(tester), isEmpty);
      expect(find.text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.'), findsOneWidget);
    });

    testWidgets('정렬: 이름순, 오래 방치된 순(실행 기록 없음은 맨 뒤)', (tester) async {
      await _open(tester, '/home');
      await _sort(tester, '이름순');
      expect(_shown(tester), ['algo-study', 'my-team-project', 'ppoling', 'shop-clone', 'weather-bot']);
      await _sort(tester, '오래 방치된 순');
      expect(_shown(tester), ['shop-clone', 'weather-bot', 'ppoling', 'my-team-project', 'algo-study']);
      await _sort(tester, '최근 실행순');
      expect(_shown(tester), _names);
    });
  });

  group('화면 6 QA 결과', () {
    testWidgets('상태 라벨이 잘리지 않는다', (tester) async {
      await _open(tester, '/qa');
      for (final label in ['통과', '실패', '설정 필요']) {
        final text = find.descendant(of: find.byType(StatusChip), matching: find.text(label));
        expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$label 라벨이 잘렸어요');
      }
    });
  });
}

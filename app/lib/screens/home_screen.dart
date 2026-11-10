import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/theme.dart';
import 'dialogs_screen.dart';

/// 1. 개발 홈 — 프로젝트 카탈로그
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// shortcut: 목업용 고정 데이터, 프로젝트 모듈이 생기면 그 인터페이스에서 받아온다.
const _projects = [
  (name: 'my-team-project', desc: '동아리 행사 예약 웹서비스 (2025 캡스톤)', status: ('실행 중 3/3', C.ok, true), stack: ['Spring Boot', 'React', 'MySQL'], last: '마지막 실행 오늘 14:02 · ', ok: true, actions: ['전체 종료'], focus: true),
  (name: 'ppoling', desc: '포폴링 데스크톱 앱', status: ('중지', C.idle, true), stack: ['Flutter'], last: '마지막 실행 어제 · ', ok: true, actions: ['전체 실행'], focus: false),
  (name: 'weather-bot', desc: '날씨 알림 디스코드 봇', status: ('오래됨 · 8개월', C.warn, false), stack: ['Node.js'], last: '마지막 실행 2026-03-12 · ', ok: false, actions: ['실행 점검'], focus: false),
  (name: 'shop-clone', desc: '쇼핑몰 클론 코딩', status: ('오래됨 · 11개월', C.warn, false), stack: ['Next.js', 'PostgreSQL'], last: '마지막 실행 2025-12-02 · ', ok: true, actions: ['실행 점검'], focus: false),
  (name: 'algo-study', desc: '설명이 없어요 — README에서 가져오거나 직접 적어 주세요.', status: ('실행 기록 없음', C.idle, false), stack: ['Python'], last: null, ok: true, actions: <String>[], focus: false),
];

const _filters = ['전체', '실행 중', '오래됨', 'Spring Boot', 'React'];

class _HomeScreenState extends State<HomeScreen> {
  var _filter = 0;
  var _sort = '최근 실행순';

  @override
  Widget build(BuildContext context) {
    return AppPage(
      crumbs: const [('개발', null)],
      trailing: const StatusChip('Docker 연결됨', C.ok),
      children: [
        PageHead(
          title: '내 프로젝트  5',
          sub: "오래 실행하지 않은 프로젝트는 '오래됨'으로 표시돼요.",
          actions: [
            Btn('프로젝트 추가', primary: true, icon: Icons.add, onPressed: () => showDialog(context: context, builder: (_) => const Dialog(child: AddProjectDialog()))),
          ],
        ),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const SizedBox(
            width: 320,
            child: TextField(
              decoration: InputDecoration(
                hintText: '이름, 설명, 기술 스택으로 검색',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
              ),
            ),
          ),
          for (final (i, f) in _filters.indexed)
            ChoiceChip(
              label: Text(f),
              selected: _filter == i,
              showCheckmark: false,
              selectedColor: C.dark,
              labelStyle: TextStyle(color: _filter == i ? Colors.white : C.text2, fontSize: 13),
              shape: const StadiumBorder(side: BorderSide(color: C.borderStrong)),
              onSelected: (_) => setState(() => _filter = i),
            ),
          Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            const Text('정렬', style: TextStyle(fontSize: 13, color: C.muted)),
            DropdownButton<String>(
              value: _sort,
              items: [for (final s in ['최근 실행순', '오래 방치된 순', '이름순']) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => _sort = v!),
            ),
          ]),
        ]),
        AutoGrid(minItemWidth: 340, children: [for (final p in _projects) _card(context, p)]),
      ],
    );
  }

  Widget _card(BuildContext context, ({String name, String desc, (String, (Color, Color), bool) status, List<String> stack, String? last, bool ok, List<String> actions, bool focus}) p) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border.all(color: p.focus ? C.primary : C.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(p.desc, style: const TextStyle(fontSize: 14, color: C.muted)),
            ]),
          ),
          StatusChip(p.status.$1, p.status.$2, dot: p.status.$3),
        ]),
        Wrap(spacing: 6, children: [for (final s in p.stack) Tag(s)]),
        p.last == null
            ? const Text('실행 항목이 아직 없어요', style: TextStyle(fontSize: 13, color: C.muted))
            : Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: C.muted), children: [
                TextSpan(text: p.last),
                TextSpan(text: p.ok ? '성공' : '실패', style: TextStyle(color: p.ok ? C.ok.$2 : C.bad.$2)),
              ])),
        const SizedBox(height: 4),
        Row(spacing: 8, children: [
          if (p.last == null)
            Expanded(child: Btn('실행 방법 설정하기', onPressed: () => Navigator.pushNamed(context, '/settings')))
          else ...[
            Expanded(child: Btn('열기', primary: p.focus, onPressed: () => Navigator.pushNamed(context, '/dashboard'))),
            for (final a in p.actions)
              Expanded(child: Btn(a, onPressed: a == '실행 점검' ? () => Navigator.pushNamed(context, '/env') : () {})),
          ],
        ]),
      ]),
    );
  }
}

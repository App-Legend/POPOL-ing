import 'package:flutter/material.dart';

import 'package:ppoling_core/ui.dart';

/// 8. AI 검사 (MVP 직후)
class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(String r) => Navigator.pushNamed(context, r);
    const k = TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500);

    Widget item(String label, Widget body) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [Text(label, style: k), body]);
    Widget finding(String level, (Color, Color) tone, String msg, String where) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            StatusChip(level, tone, dot: false),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(msg, style: const TextStyle(fontSize: 14)),
                Text(where, style: mono.copyWith(fontSize: 12, color: C.muted)),
              ]),
            ),
          ]),
        );

    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', '/dashboard'), ('AI 검사', null)],
      children: [
        Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            Text('AI 검사', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip('로컬 모델 준비됨', C.ok),
              Text('[모델 이름] · 메모리 약 6GB 사용', style: TextStyle(fontSize: 13, color: C.text2)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Icon(Icons.lock_outline, size: 14, color: C.muted),
              Text('모든 분석은 이 컴퓨터 안에서 해요. 코드와 로그는 밖으로 나가지 않아요.', style: TextStyle(fontSize: 13, color: C.muted)),
            ]),
          ]),
          const Wrap(spacing: 8, children: [Btn('모델 설정'), Btn('전체 다시 분석', primary: true)]),
        ]),
        AutoGrid(minItemWidth: 460, children: [
          _card('프로젝트 파악', const StatusChip('2분 전', C.idle, dot: false), [
            item('한 줄 설명 제안', const Text('동아리 행사 예약 웹서비스 — Spring Boot API, React 프론트, MySQL 로 구성', style: TextStyle(fontSize: 14))),
            item('감지한 기술 스택', const Wrap(spacing: 6, runSpacing: 6, children: [Tag('Spring Boot 2.7'), Tag('React 18'), Tag('Vite'), Tag('MySQL 8')])),
            item('실행 방법', const Text('실행 항목 3개를 찾았어요. 지금 ppoling.yaml 과 같아요.', style: TextStyle(fontSize: 13, color: C.text2))),
            const Wrap(spacing: 8, children: [Btn('설명·스택에 적용', primary: true, small: true), Btn('다시 분석', small: true)]),
          ]),
          _card('실행 실패 원인 분석', const StatusChip('web · 어제 실패', C.bad, dot: false), [
            item('원인 후보 · 가능성 높음', const Text('Node 버전이 20 → 22 로 바뀐 뒤, 프론트 의존성 하나가 Node 22 를 지원하지 않아 실행이 멈췄어요.', style: TextStyle(fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                const Text('근거 로그', style: TextStyle(fontSize: 12, color: Color(0xFF9AA1AD), fontWeight: FontWeight.w500)),
                Text('error: The engine "node" is incompatible with this module.\nExpected version ">=18 <21". Got "22.3.0"',
                    style: mono.copyWith(fontSize: 12, color: C.logText)),
              ]),
            ),
            item('해결 방법', const Text('1. Node 20.x 로 바꿔서 실행하기 (마지막 성공 환경)\n2. 또는 해당 의존성을 Node 22 지원 버전으로 올리기',
                style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFF2C3038)))),
            Wrap(spacing: 8, children: [Btn('환경 점검 보기', small: true, onPressed: () => open('/env')), Btn('전체 로그', small: true, onPressed: () => open('/detail'))]),
          ]),
          _card('QA 결과 요약', const StatusChip('오늘 14:05 검사 기준', C.idle, dot: false), [
            const Text('API 는 정상이에요 (84ms). 프론트는 web 이 시작되지 않아 실패했는데, 포트 5173 을 shop-clone 이 쓰고 있기 때문이에요. 관리자 페이지는 검사할 주소가 아직 없어요.',
                style: TextStyle(fontSize: 14, height: 1.75)),
            Wrap(children: [Btn('QA 결과 보기', small: true, onPressed: () => open('/qa'))]),
          ]),
          _card('코드 점검', const StatusChip('./backend · 10분 전', C.idle, dot: false), [
            item('점검할 폴더', Row(children: [
              Checkbox(value: true, onChanged: (_) {}), Text('./backend', style: mono.copyWith(fontSize: 13)),
              const SizedBox(width: 12),
              Checkbox(value: false, onChanged: (_) {}), Text('./frontend', style: mono.copyWith(fontSize: 13)),
              const Spacer(),
              const Btn('점검 시작', small: true),
            ])),
            Column(children: [
              finding('높음', C.bad, '설정 파일에 DB 비밀번호가 그대로 적혀 있어요', 'backend/src/main/resources/application.yml:12'),
              finding('보통', C.warn, 'Spring Boot 2.7 은 지원이 끝난 버전이에요', 'backend/build.gradle:3'),
              finding('낮음', C.idle, '사용하지 않는 import 가 여러 파일에 있어요', '파일 4개'),
            ]),
          ]),
        ]),
        const Text('AI 결과는 틀릴 수 있어요. 근거를 확인한 뒤 반영해 주세요. AI 가 제안한 내용은 [적용] 을 누르기 전에는 저장되지 않아요.',
            style: TextStyle(fontSize: 12, color: C.muted)),
        Panel(
          title: '분석 기록',
          padding: const EdgeInsets.only(top: 14),
          child: SimpleTable(columns: const ['시각', '분석', '대상', '걸린 시간'], minWidth: 600, rows: [
            const [Text('오늘 14:20'), Text('프로젝트 파악'), Text('my-team-project'), Text('38초')],
            [const Text('오늘 14:12'), const Text('코드 점검'), Text('./backend', style: mono.copyWith(fontSize: 13)), const Text('2분 10초')],
            const [Text('어제 21:16'), Text('실행 실패 원인 분석'), Text('web'), Text('24초')],
          ]),
        ),
      ],
    );
  }

  static Widget _card(String title, Widget badge, List<Widget> children) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), badge]),
          ...children,
        ]),
      );
}

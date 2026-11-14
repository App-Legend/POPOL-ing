import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/theme.dart';

/// 8. AI 검사 (Gemini API · MVP: AI-02·03)
class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(String r) => Navigator.pushNamed(context, r);
    const k = TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500);

    Widget item(String label, Widget body) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [Text(label, style: k), body]);
    // 요약 문장 하나와 그 근거(검사 항목·값·시각).
    Widget sentence(String text, String evidence) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Text('•  $text', style: const TextStyle(fontSize: 14, height: 1.6)),
          Container(
            margin: const EdgeInsets.only(left: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF3F5F8), borderRadius: BorderRadius.circular(6)),
            child: Text(evidence, style: mono.copyWith(fontSize: 12, color: C.text2)),
          ),
        ]);
    Widget dashedBox(List<Widget> children, {Color bg = C.surface}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(color: bg, border: Border.all(color: const Color(0xFFC9CED6)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children),
        );

    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', '/dashboard'), ('AI 검사', null)],
      children: [
        Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            const Text('AI 검사', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const StatusChip('Gemini API 키 입력됨', C.ok),
              Text('키 ••••3fA2 · [모델 이름]', style: mono.copyWith(fontSize: 13, color: C.text2)),
            ]),
          ]),
          Btn('키 관리', onPressed: () => open('/dialogs')),
        ]),
        Notice(
          bg: C.remote.$1,
          border: const Color(0xFFB9C8F5),
          icon: Icons.send_outlined,
          iconColor: C.remote.$2,
          child: const Text.rich(TextSpan(style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF1F2F66)), children: [
            TextSpan(text: '분석할 내용은 '),
            TextSpan(text: 'Google 서버로 전송', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '돼요. 보내기 전에 보낼 내용을 보여주고, [보내기]를 눌러야 전송해요. .env 값과 API 키는 보내지 않아요.'),
          ])),
        ),
        AutoGrid(minItemWidth: 460, children: [
          _card('실행 실패 원인 분석', const StatusChip('web · 어제 실패', C.bad, dot: false), [
            item('원인 후보 · 가능성 높음', const Text('Node 버전이 20 → 22 로 바뀐 뒤, 프론트 의존성 하나가 Node 22 를 지원하지 않아 실행이 멈췄어요.', style: TextStyle(fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                const Text('근거 · 실패 로그', style: TextStyle(fontSize: 12, color: Color(0xFF9AA1AD), fontWeight: FontWeight.w500)),
                Text('error: The engine "node" is incompatible with this module.\nExpected version ">=18 <21". Got "22.3.0"',
                    style: mono.copyWith(fontSize: 12, color: C.logText)),
              ]),
            ),
            item('근거 · 마지막 성공 환경과 비교', Text.rich(TextSpan(children: [
              TextSpan(text: 'node 20.11.1 → 22.3.0 ', style: mono.copyWith(fontSize: 13)),
              const TextSpan(text: '(마지막 성공 2026-10-02)', style: TextStyle(fontSize: 13, color: C.muted)),
            ]))),
            item('해결 방법', const Text('1. Node 20.x 로 바꿔서 실행하기 (마지막 성공 환경)\n2. 또는 해당 의존성을 Node 22 지원 버전으로 올리기',
                style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFF2C3038)))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Btn('환경 점검 보기', small: true, onPressed: () => open('/env')),
              Btn('전체 로그', small: true, onPressed: () => open('/detail')),
              Btn('다시 분석', small: true, onPressed: () => open('/dialogs')),
            ]),
          ]),
          _card('QA 결과 요약', const StatusChip('오늘 14:05 검사 기준', C.idle, dot: false), [
            sentence('API 는 정상 응답했어요.', 'API 헬스 · 200 · 84ms · 14:05'),
            sentence('프론트는 web 항목이 시작되지 않아 연결이 거부됐어요. 포트 5173 을 shop-clone 이 쓰고 있었어요.', '프론트 메인 · 연결 거부 · 14:05'),
            sentence('관리자 페이지는 검사할 주소가 아직 없어요.', '관리자 페이지 · 설정 필요'),
            item('실패한 항목', Row(spacing: 10, children: [
              const StatusChip('실패', C.bad),
              const Expanded(child: Text('프론트 메인', style: TextStyle(fontSize: 13))),
              Btn('원인 분석', small: true, onPressed: () => open('/dialogs')),
            ])),
            const Text('통과·실패 판정은 QA 규칙으로 정해요. AI 요약은 설명만 붙이고 판정을 바꾸지 않아요.', style: TextStyle(fontSize: 12, color: C.muted)),
            Wrap(children: [Btn('QA 결과 보기', small: true, onPressed: () => open('/qa'))]),
          ]),
        ]),
        dashedBox([
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const SizedBox(
              width: 520,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                Text('키가 없을 때 이 화면', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('분석 카드 대신 아래 한 줄만 보여요. 실행·종료·헬스체크 같은 다른 기능은 그대로 써요.', style: TextStyle(fontSize: 13, color: C.text2)),
              ]),
            ),
            const StatusChip('API 키 필요', C.idle),
            Btn('키 입력', primary: true, small: true, onPressed: () => open('/dialogs')),
          ]),
        ]),
        dashedBox(bg: C.headBg, [
          const Row(spacing: 10, children: [
            Expanded(child: Text('MVP 직후에 추가', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            StatusChip('이번 버전 화면에는 없음', C.idle, dot: false),
          ]),
          const AutoGrid(minItemWidth: 320, gap: 12, children: [
            _Later('프로젝트 파악', 'AI-01', '폴더를 읽고 한 줄 설명·기술 스택·실행 방법 초안을 만들어요. [적용] 전에는 저장하지 않아요.'),
            _Later('코드 점검', 'AI-04', '고른 폴더에서 보안 취약점, 오래된 의존성, 눈에 띄는 코드 문제를 찾아요.'),
          ]),
        ]),
        const Text('AI 결과는 틀릴 수 있어요. 근거를 확인한 뒤 반영해 주세요. 분석 중에도 실행·종료는 그대로 쓸 수 있고, 언제든 취소할 수 있어요.',
            style: TextStyle(fontSize: 12, color: C.muted)),
        Panel(
          title: '분석 기록',
          padding: const EdgeInsets.only(top: 14),
          child: SimpleTable(columns: const ['시각', '분석', '대상', '결과', '보낸 내용'], minWidth: 720, rows: [
            [const Text('오늘 14:21'), const Text('QA 결과 요약'), const Text('14:05 검사'), const Text('완료 · 6초'), LinkText('보기', onTap: () => open('/dialogs'))],
            [const Text('어제 21:16'), const Text('실행 실패 원인 분석'), const Text('web'), const Text('완료 · 9초'), LinkText('보기', onTap: () => open('/dialogs'))],
            [const Text('어제 21:12'), const Text('실행 실패 원인 분석'), const Text('web'), Text('실패 · 사용량 초과 (잠시 뒤 다시)', style: TextStyle(color: C.bad.$2)), LinkText('보기', onTap: () => open('/dialogs'))],
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

/// MVP 직후에 들어갈 분석 한 칸.
class _Later extends StatelessWidget {
  const _Later(this.title, this.id, this.desc);
  final String title, id, desc;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(style: const TextStyle(fontSize: 13, height: 1.6, color: C.text2), children: [
        TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w700, color: C.text)),
        TextSpan(text: '  $id\n', style: mono.copyWith(fontSize: 11)),
        TextSpan(text: desc),
      ]));
}

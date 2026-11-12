import 'package:flutter/material.dart';

import 'package:ppoling_core/ui.dart';

/// 5. QA 결과 (헬스체크)
class QaScreen extends StatelessWidget {
  const QaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const m = TextStyle(fontFamily: 'Menlo', fontSize: 12, color: C.muted);
    Widget meta(List<String> items) => Wrap(spacing: 20, children: [for (final t in items) Text(t, style: const TextStyle(fontSize: 13, color: C.text2))]);

    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', '/dashboard'), ('QA 결과', null)],
      children: [
        const PageHead(
          title: '헬스체크',
          sub: '마지막 검사 오늘 14:05:02 · 통과 1 · 실패 1 · 설정 필요 1',
          actions: [Btn('다시 검사', primary: true)],
        ),
        _check(
          const StatusChip('통과', C.ok),
          'API 헬스',
          const Text('GET http://localhost:8080/actuator/health · 기대 200', style: m),
          meta(['응답 200', '시간 84ms', '14:05:02']),
        ),
        _check(
          const StatusChip('실패', C.bad),
          '프론트 메인',
          const Text('GET http://localhost:5173 · 기대 2xx~3xx', style: m),
          meta(['연결 거부', '14:05:02']),
          extra: Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.headBg, borderRadius: BorderRadius.circular(8)),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('원인 후보: web 항목이 시작되지 않았어요 (포트 5173 을 내 프로젝트 shop-clone / web 이 사용 중). ', style: TextStyle(fontSize: 13, color: C.text2)),
              LinkText('대시보드에서 확인', size: 13, onTap: () => go(context, '/dashboard')),
            ]),
          ),
        ),
        _check(
          const StatusChip('설정 필요', C.idle),
          '관리자 페이지',
          const Text('검사할 주소가 없어요.', style: TextStyle(fontSize: 13, color: C.muted)),
          Btn('주소 설정', onPressed: () => Navigator.pushNamed(context, '/settings')),
        ),
        const Panel(
          title: '검사 이력',
          padding: EdgeInsets.only(top: 16),
          child: SimpleTable(columns: ['검사 시각', '통과', '실패', '설정 필요', '계기'], minWidth: 600, rows: [
            [Text('오늘 14:05:02'), Text('1'), Text('1'), Text('1'), Text('수동 검사', style: TextStyle(color: C.text2))],
            [Text('2026-10-02 18:41'), Text('2'), Text('0'), Text('1'), Text('전체 실행 후 자동', style: TextStyle(color: C.text2))],
            [Text('2026-09-28 21:10'), Text('1'), Text('1'), Text('1'), Text('수동 검사', style: TextStyle(color: C.text2))],
          ]),
        ),
      ],
    );
  }

  static Widget _check(Widget chip, String title, Widget sub, Widget right, {Widget? extra}) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(spacing: 16, children: [
            SizedBox(width: 100, child: Align(alignment: Alignment.centerLeft, child: chip)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                sub,
              ]),
            ),
            right,
          ]),
          ?extra,
        ]),
      );
}

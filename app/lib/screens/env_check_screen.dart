import 'package:flutter/material.dart';

import 'package:ppoling_core/ui.dart';

/// 4. 환경 점검
class EnvCheckScreen extends StatelessWidget {
  const EnvCheckScreen({super.key});

  static const _m = TextStyle(fontFamily: 'Menlo', fontSize: 13);

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String n, Color color) => Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: C.muted)),
            Text(n, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    Widget problem(String label, String desc) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          StatusChip(label, C.bad),
          Text(desc, style: const TextStyle(fontSize: 13, color: C.text2)),
        ]);

    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', '/dashboard'), ('환경 점검', null)],
      children: [
        const PageHead(
          title: '환경 점검',
          sub: 'ppoling.yaml 의 requires 항목을 검사하고, 마지막으로 성공한 실행(2026-10-02 18:40)의 환경과 비교해요.',
          actions: [Btn('다시 점검'), Btn('점검 + 전체 실행 + 헬스체크', primary: true)],
        ),
        AutoGrid(minItemWidth: 220, gap: 12, children: [
          stat('통과', '3', C.ok.$2),
          stat('마지막 성공 이후 바뀜', '3', C.warn.$2),
          stat('문제', '0', C.text),
        ]),
        Panel(
          title: '도구와 런타임',
          padding: const EdgeInsets.only(top: 16),
          child: SimpleTable(columns: const ['항목', '요구', '지금', '마지막 성공 때', '상태'], rows: [
            [_b('node'), const Text('>=20', style: _m), const Text('22.3.0', style: _m), const Text('20.11.1', style: _m),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                StatusChip('통과 · 버전 바뀜', C.warn),
                Text('실행이 실패하면 20.x 로 바꿔 보세요.', style: TextStyle(fontSize: 12, color: C.muted)),
              ])],
            [_b('java'), const Text('>=17', style: _m), const Text('17.0.9', style: _m), const Text('17.0.9', style: _m), const StatusChip('통과', C.ok)],
            [_b('Docker 데몬'), const Text('실행 중이어야 함'),
              const Text.rich(TextSpan(children: [TextSpan(text: '실행 중 '), TextSpan(text: '27.1', style: _m)])),
              const Text('26.0', style: _m), const StatusChip('통과', C.ok)],
          ]),
        ),
        Panel(
          title: '프로젝트 변화',
          padding: const EdgeInsets.only(top: 16),
          child: SimpleTable(columns: const ['항목', '지금', '마지막 성공 때', '메모'], rows: [
            [_b('Git 커밋'), const Text('f9e8d7c', style: _m), const Text('a1b2c3d', style: _m), const Text('그 뒤로 커밋 12개', style: TextStyle(color: C.text2))],
            [_b('db 이미지'), const Text('mysql:8.4', style: _m), const Text('mysql:8.0', style: _m), const Text('docker-compose.yml 에서 태그가 바뀜', style: TextStyle(color: C.text2))],
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          // shortcut: 시안은 점선 테두리지만 Flutter 기본 위젯엔 없어서 실선으로 대체.
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: const Color(0xFFC9CED6)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            const Text('문제가 있을 때는 이렇게 나눠서 안내해요', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            AutoGrid(minItemWidth: 240, gap: 12, children: [
              problem('미설치', '명령을 찾을 수 없어요. 설치 방법 링크와 PATH 확인 방법을 보여줘요.'),
              problem('버전 불일치', '설치는 됐지만 요구 버전과 달라요. 요구 버전과 지금 버전을 나란히 보여줘요.'),
              problem('데몬 미실행', 'Docker 가 꺼져 있어요. Compose 항목의 시작 버튼을 막고 Docker Desktop 실행을 안내해요.'),
            ]),
          ]),
        ),
      ],
    );
  }

  static Widget _b(String s) => Text(s, style: const TextStyle(fontWeight: FontWeight.w500));
}

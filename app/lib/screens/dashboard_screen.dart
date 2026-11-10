import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/theme.dart';

/// 2. 프로젝트 대시보드
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(String r) => Navigator.pushNamed(context, r);
    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', null)],
      children: [
        Wrap(spacing: 20, runSpacing: 16, alignment: WrapAlignment.spaceBetween, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              const Text('my-team-project', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const Text('동아리 행사 예약 웹서비스 (2025 캡스톤)', style: TextStyle(fontSize: 15, color: C.text2)),
              const Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Tag('Spring Boot'), Tag('React'), Tag('MySQL'),
                SizedBox(width: 2),
                LinkText('저장소 열기', size: 13),
              ]),
              const Text('메모: 관리자 계정은 .env 의 ADMIN_* 참고', style: TextStyle(fontSize: 13, color: C.muted)),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            const Btn('전체 실행', primary: true, icon: Icons.play_arrow),
            const Btn('전체 종료', icon: Icons.stop),
            Btn('헬스체크', onPressed: () => open('/qa')),
            Btn('AI 검사', onPressed: () => open('/ai')),
            Tooltip(
              message: '프로젝트 설정',
              child: OutlinedButton(
                onPressed: () => open('/settings'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), side: const BorderSide(color: C.borderStrong)),
                child: const Icon(Icons.settings_outlined, size: 18, color: C.text, semanticLabel: '프로젝트 설정'),
              ),
            ),
          ]),
        ]),
        Notice(
          bg: const Color(0xFFFFF8E6),
          border: const Color(0xFFF1D79A),
          icon: Icons.warning_amber_rounded,
          iconColor: C.warn.$2,
          trailing: [LinkText('환경 점검 보기', onTap: () => open('/env'))],
          child: const Text.rich(TextSpan(style: TextStyle(fontSize: 14, color: Color(0xFF5A3B00)), children: [
            TextSpan(text: '마지막으로 성공한 실행(2026-10-02) 이후 환경이 바뀌었어요: '),
            TextSpan(text: 'Node 20.11 → 22.3', style: TextStyle(fontFamily: 'Menlo', fontWeight: FontWeight.w500)),
          ])),
        ),
        Panel(
          title: '실행 항목',
          titleAction: const Text('실행 순서 db → api → web · storage 는 원격', style: TextStyle(fontSize: 13, color: C.muted)),
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _row(const [Text('항목'), Text('포트'), Text('준비 조건'), Text('상태'), SizedBox()], head: true),
            _row([
              _name(context, 'db', 'Compose', null, 'docker-compose.yml · mysql'),
              _port('3306'),
              const Text('Compose healthcheck'),
              const StatusChip('준비 완료', C.ok),
              const Btn('중지'),
            ]),
            _row([
              _name(context, 'api', '프로세스', 'db', './backend · ./gradlew bootRun'),
              _port('8080'),
              const Text('HTTP 응답 대기 34초 / 120초'),
              const StatusChip('실행 중 · 준비 대기', C.warn),
              const Btn('중지'),
            ]),
            _row([
              _name(context, 'web', '프로세스', 'api', './frontend · npm run dev'),
              _port('5173', color: C.port.$2),
              const Text('포트 열림'),
              const StatusChip('포트 사용 중', C.port),
              const Btn('시작', onPressed: null),
            ], extra: Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFFF6EF), border: Border.all(color: const Color(0xFFF5CDB0)), borderRadius: BorderRadius.circular(8)),
              child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const SizedBox(
                  width: 520,
                  child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: Color(0xFF5A2A08)), children: [
                    TextSpan(text: '포트 '),
                    TextSpan(text: '5173', style: TextStyle(fontFamily: 'Menlo', fontWeight: FontWeight.w500)),
                    TextSpan(text: ' 을 내 프로젝트 '),
                    TextSpan(text: 'shop-clone / web', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' 이 사용 중이에요.'),
                  ])),
                ),
                Btn('shop-clone 으로 이동', small: true, onPressed: () => go(context, '/home')),
                const Btn('shop-clone / web 중지', small: true),
              ]),
            )),
            _row([
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(spacing: 8, children: [Text('storage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), Tag('원격 연결', tone: C.remote)]),
                SizedBox(height: 4),
                Text('https://storage.my-team.dev', style: TextStyle(fontFamily: 'Menlo', fontSize: 12, color: C.muted)),
              ]),
              _port('443'),
              const Text('HTTP 응답 · 120ms'),
              const StatusChip('연결됨', C.ok),
              const Btn('다시 확인', small: true),
            ]),
          ]),
        ),
        AutoGrid(minItemWidth: 320, children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              const Text('이번 전체 실행', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              for (final (label, tone, msg) in [
                ('성공', C.ok, 'db — 12초 만에 준비 완료'),
                ('진행 중', C.warn, 'api — 준비 대기 중'),
                ('건너뜀', C.idle, 'web — 포트 5173 을 shop-clone 이 사용 중'),
              ])
                Row(spacing: 8, children: [SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: StatusChip(label, tone, dot: false))), Expanded(child: Text(msg, style: const TextStyle(fontSize: 14)))]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              Row(children: [
                const Expanded(child: Text('최근 로그 · api', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE6E8EC)))),
                LinkText('전체 로그', size: 13, color: const Color(0xFF9DB6FF), onTap: () => open('/detail')),
              ]),
              Text.rich(
                TextSpan(children: [
                  logLine('14:02:11', '', 'Starting Application using Java 17.0.9'),
                  logLine('14:02:13', '', 'HikariPool-1 - Starting...'),
                  logLine('14:02:15', '', 'DB_PASSWORD=•••••• (마스킹됨)'),
                  logLine('14:02:19', '', 'Tomcat initialized with port 8080'),
                ]),
                style: mono.copyWith(fontSize: 12, height: 1.7, color: C.logText),
              ),
            ]),
          ),
        ]),
      ],
    );
  }

  static Widget _row(List<Widget> cells, {bool head = false, Widget? extra}) {
    const widths = [null, 110.0, 210.0, 150.0, 96.0];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: head ? 8 : 16),
      decoration: BoxDecoration(color: head ? C.headBg : null, border: const Border(top: BorderSide(color: C.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DefaultTextStyle.merge(
          style: head ? const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500) : const TextStyle(fontSize: 13, color: C.text2),
          child: Row(spacing: 16, children: [
            for (final (i, c) in cells.indexed)
              widths[i] == null ? Expanded(child: c) : SizedBox(width: widths[i], child: Align(alignment: Alignment.centerLeft, child: c)),
          ]),
        ),
        ?extra,
      ]),
    );
  }

  static Widget _name(BuildContext context, String name, String kind, String? dep, String cmd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
      Row(spacing: 8, children: [
        InkWell(onTap: () => Navigator.pushNamed(context, '/detail'), child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text))),
        Tag(kind),
        if (dep != null) Text('의존: $dep', style: const TextStyle(fontSize: 12, color: C.muted)),
      ]),
      Text(cmd, style: mono.copyWith(fontSize: 12, color: C.muted)),
    ]);
  }

  static Widget _port(String p, {Color color = C.text2}) => Text(p, style: mono.copyWith(fontSize: 13, color: color));
}

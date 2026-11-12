import 'package:flutter/material.dart';

import 'package:ppoling_core/ui.dart';

/// 3. 실행 항목 상세 · 로그
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  var _tab = 0;
  var _autoScroll = true;

  static const _m = TextStyle(fontFamily: 'Menlo', fontSize: 13);

  @override
  Widget build(BuildContext context) {
    return AppPage(
      crumbs: const [('개발', '/home'), ('my-team-project', '/dashboard'), ('api', null)],
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
          SizedBox(
            width: 380,
            child: Column(spacing: 16, children: [
              const Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                  Row(children: [
                    Expanded(child: Text('api', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
                    StatusChip('준비 완료', C.ok),
                  ]),
                  KeyValues([
                    ('시작 시각', Text('오늘 14:02:11')),
                    ('PID', Text('52310', style: _m)),
                    ('소유권', Text('앱이 시작함 · 확인됨', style: TextStyle(color: Color(0xFF1E6B36)))),
                    ('준비까지', Text('41초')),
                  ]),
                  Row(spacing: 8, children: [Expanded(child: Btn('중지')), Expanded(child: Btn('재시작'))]),
                ]),
              ),
              Panel(
                title: '실행 설정',
                titleAction: LinkText('편집', size: 13, onTap: () => Navigator.pushNamed(context, '/settings')),
                child: const KeyValues([
                  ('유형', Text('프로세스')),
                  ('작업 폴더', Text('./backend', style: _m)),
                  ('명령', Text('["./gradlew", "bootRun"]', style: _m)),
                  ('환경변수', Text('SPRING_PROFILES_ACTIVE=local', style: _m)),
                  ('env 파일', Text.rich(TextSpan(children: [
                    TextSpan(text: './backend/.env ', style: _m),
                    TextSpan(text: '(값은 표시하지 않음)', style: TextStyle(color: C.muted)),
                  ]))),
                  ('포트', Text('8080', style: _m)),
                  ('의존 항목', Text('db')),
                  ('준비 조건', Text.rich(TextSpan(children: [TextSpan(text: 'HTTP '), TextSpan(text: '/actuator/health', style: _m), TextSpan(text: ' · 최대 120초')]))),
                  ('종료 유예', Text('15초 후 강제 종료')),
                ]),
              ),
            ]),
          ),
          Expanded(child: _logBox()),
        ]),
      ],
    );
  }

  Widget _logBox() {
    Widget tab(String label, int i) => TextButton(
          onPressed: () => setState(() => _tab = i),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            backgroundColor: _tab == i ? C.darkLine : null,
            foregroundColor: _tab == i ? Colors.white : const Color(0xFF9AA1AD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(label),
        );
    Widget plain(String label) => TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(minimumSize: const Size(0, 36), foregroundColor: const Color(0xFF9AA1AD)),
          child: Text(label),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.darkLine))),
          child: Wrap(spacing: 4, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            tab('전체', 0), tab('stdout', 1), tab('stderr', 2),
            const SizedBox(width: 16),
            const SizedBox(
              width: 170,
              child: TextField(
                style: TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '검색',
                  hintStyle: TextStyle(color: Color(0xFF9AA1AD)),
                  prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF9AA1AD)),
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFF22252C),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ),
            Checkbox(value: _autoScroll, onChanged: (v) => setState(() => _autoScroll = v!)),
            const Text('자동 스크롤', style: TextStyle(fontSize: 13, color: C.logText)),
            plain('복사'),
            plain('파일 열기'),
          ]),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 520),
          padding: const EdgeInsets.all(16),
          child: SelectableText.rich(
            TextSpan(children: [
              logLine('14:02:11', 'INFO', 'Starting Application using Java 17.0.9'),
              logLine('14:02:11', 'INFO', 'The following 1 profile is active: "local"'),
              logLine('14:02:13', 'INFO', 'HikariPool-1 - Starting...'),
              logLine('14:02:13', 'INFO', 'spring.datasource.password=••••••', note: '(비밀값 마스킹)'),
              logLine('14:02:15', 'WARN', 'HikariPool-1 - Connection is not available, retrying (1/5)'),
              logLine('14:02:17', 'INFO', 'HikariPool-1 - Start completed.'),
              logLine('14:02:19', 'INFO', 'Tomcat initialized with port 8080 (http)'),
              logLine('14:02:31', 'INFO', 'Started Application in 20.4 seconds'),
              logLine('14:02:52', '포폴링', '준비 조건 충족 — GET /actuator/health → 200'),
              logLine('14:05:02', 'INFO', 'GET /api/events 200 (84ms)'),
            ]),
            style: mono.copyWith(fontSize: 12.5, height: 1.8, color: C.logText),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.darkLine))),
          child: const Text('화면에는 최근 5,000줄까지 보여요. 전체 로그는 파일로 저장돼요 (10MB × 3개 회전).', style: TextStyle(fontSize: 12, color: Color(0xFF8A909C))),
        ),
      ]),
    );
  }
}

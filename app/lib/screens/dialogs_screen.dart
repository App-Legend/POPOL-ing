import 'package:flutter/material.dart';

import 'package:ppoling_core/ui.dart';

/// 7. 확인 대화상자 — 여섯 대화상자를 나란히 보여주는 시안 화면.
class DialogsScreen extends StatelessWidget {
  const DialogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget labeled(String label, Widget dlg) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFFDDE1E8), fontWeight: FontWeight.w500)),
          Material(color: C.surface, borderRadius: BorderRadius.circular(14), child: dlg),
        ]);

    return Scaffold(
      backgroundColor: const Color(0xFF3A3E48),
      appBar: AppBar(title: const Text('확인 대화상자'), backgroundColor: const Color(0xFF3A3E48), foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: AutoGrid(minItemWidth: 340, gap: 24, children: [
              labeled('A. 프로젝트 추가 · FR-01, FR-15', const AddProjectDialog()),
              labeled('B. 처음 여는 설정 파일 실행 확인 · §8 안전성', const ConfirmCommandsDialog()),
              labeled('C. 앱 종료 확인 · FR-12', const QuitDialog()),
              labeled('D. pull 뒤 바뀐 실행 명령 확인 · FR-19, §6', const ChangedCommandsDialog()),
              labeled('E. Gemini API 키 입력 · 앱 설정 · AI', const ApiKeyDialog()),
              labeled('F. AI 전송 확인 · AI-02·03, AT-21', const AiSendDialog()),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ...children,
          ]),
        ),
      );
}

void _close(BuildContext context) {
  // 시안 화면에 박혀 있을 땐 닫을 대화상자가 없다.
  if (ModalRoute.of(context) is DialogRoute) Navigator.pop(context);
}

class AddProjectDialog extends StatelessWidget {
  const AddProjectDialog({super.key});

  @override
  Widget build(BuildContext context) => _DialogBody('프로젝트 추가', [
        Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
          Expanded(child: field('폴더', '~/projects/my-team-project', isMono: true)),
          const Btn('찾기'),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: C.ok.$1, borderRadius: BorderRadius.circular(8)),
          child: Text('ppoling.yaml 을 찾았어요. 실행 항목 3개를 불러올게요.', style: TextStyle(fontSize: 13, color: C.ok.$2)),
        ),
        field('이름', 'my-team-project'),
        field('한 줄 설명', '동아리 행사 예약 웹서비스 (2025 캡스톤)', hint: 'README 에서 가져옴'),
        field('저장소', 'github.com/example/my-team-project', isMono: true, hint: 'Git 원격에서 가져옴'),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
          Btn('취소', onPressed: () => _close(context)),
          Btn('추가', primary: true, onPressed: () => _close(context)),
        ]),
      ]);
}

class ConfirmCommandsDialog extends StatelessWidget {
  const ConfirmCommandsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    Widget cmd(String name, String c, [String? dir]) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: C.headBg, border: Border.all(color: C.divider), borderRadius: BorderRadius.circular(8)),
          child: Row(spacing: 8, children: [
            SizedBox(width: 36, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Flexible(child: Text(c, style: mono.copyWith(fontSize: 12.5))),
            if (dir != null) Text(dir, style: const TextStyle(fontSize: 13, color: C.muted)),
          ]),
        );
    return _DialogBody('이 명령들을 실행할까요?', [
      const Text('이 프로젝트의 ppoling.yaml 을 처음 실행해요. 다른 사람이 만든 설정이라면 아래 명령이 믿을 만한지 확인해 주세요.',
          style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
      Column(spacing: 6, children: [
        cmd('db', 'docker compose -p ppoling-my-team-project up -d mysql'),
        cmd('api', './gradlew bootRun', 'in ./backend'),
        cmd('web', 'npm run dev', 'in ./frontend'),
      ]),
      _box(const Text('명령은 셸을 거치지 않고 적힌 그대로 실행해요.', style: TextStyle(fontSize: 13, color: C.text2))),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
        Btn('취소', onPressed: () => _close(context)),
        Btn('확인하고 실행', primary: true, onPressed: () => _close(context)),
      ]),
    ]);
  }
}

class QuitDialog extends StatelessWidget {
  const QuitDialog({super.key});

  @override
  Widget build(BuildContext context) => _DialogBody('실행 중인 항목이 있어요', [
        const Text('포폴링을 닫기 전에 어떻게 할까요?', style: TextStyle(fontSize: 14, color: C.text2)),
        const Text('•  my-team-project — db, api\n•  ppoling — app', style: TextStyle(fontSize: 14, height: 1.8)),
        Btn('모두 종료하고 닫기', primary: true, onPressed: () => _close(context)),
        Btn('그대로 두고 닫기', onPressed: () => _close(context)),
        Btn('취소', ghost: true, onPressed: () => _close(context)),
        const Text('그대로 두면 다음에 앱을 열 때 실행 기록을 확인해 다시 연결해요.', style: TextStyle(fontSize: 12, color: C.muted)),
      ]);
}

/// 회색(기본) 또는 노란 안내 상자.
Widget _box(Widget child, {bool warn = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF8E6) : C.bg,
        border: warn ? Border.all(color: const Color(0xFFF1D79A)) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );

Widget _cancelOk(BuildContext context, String ok) => Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
      Btn('취소', onPressed: () => _close(context)),
      Btn(ok, primary: true, onPressed: () => _close(context)),
    ]);

class ChangedCommandsDialog extends StatelessWidget {
  const ChangedCommandsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // 색이 아니라 '이전 / 지금' 글자로 구분한다.
    Widget line(String label, String cmd, {bool now = false}) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          SizedBox(width: 32, child: Text(label, style: const TextStyle(fontSize: 13, color: C.muted))),
          Expanded(child: Text(cmd, style: mono.copyWith(fontSize: 12.5, fontWeight: now ? FontWeight.w500 : null))),
        ]);
    return _DialogBody('실행 명령이 바뀌었어요', [
      const Text('전체 실행 전에 최신 코드를 받았더니 ppoling.yaml 의 실행 명령이 바뀌었어요. 바뀐 명령을 확인한 뒤 실행해 주세요.',
          style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
      _box(Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        const Text('api', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        line('이전', './gradlew bootRun'),
        line('지금', './gradlew bootRun --args=--spring.profiles.active=dev', now: true),
      ])),
      const Text('취소하면 받은 코드는 그대로 두고 실행만 멈춰요.', style: TextStyle(fontSize: 12, color: C.muted)),
      _cancelOk(context, '확인하고 실행'),
    ]);
  }
}

class ApiKeyDialog extends StatelessWidget {
  const ApiKeyDialog({super.key});

  @override
  Widget build(BuildContext context) => _DialogBody('Gemini API 키', [
        const Text('AI 검사에 쓸 내 API 키를 넣어 주세요. 키가 없어도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.',
            style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
        field('API 키', 'xxxxxxxxxxxxxxxxxxxx', isMono: true, obscure: true),
        _box(const Text('키는 이 컴퓨터의 앱 설정에만 저장해요. ppoling.yaml·로그·화면에는 그대로 남기지 않아요.',
            style: TextStyle(fontSize: 13, color: C.text2, height: 1.6))),
        _box(warn: true, const Text('무료 등급은 사용량 제한이 있고, 보낸 내용이 Google 서비스 개선에 쓰일 수 있어요. [착수 전 최신 약관을 확인해 문구 확정]',
            style: TextStyle(fontSize: 13, color: Color(0xFF5A3B00), height: 1.6))),
        const Align(alignment: Alignment.centerLeft, child: LinkText('키 발급 방법 보기', size: 13)),
        _cancelOk(context, '저장'),
      ]);
}

class AiSendDialog extends StatelessWidget {
  const AiSendDialog({super.key});

  @override
  Widget build(BuildContext context) => _DialogBody('이 내용이 Google 로 전송돼요', [
        const Text('실행 실패 원인 분석 · web. 아래 내용만 Gemini API 로 보내요. [보내기]를 누르기 전에는 아무것도 보내지 않아요.',
            style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
        const Text('보낼 내용', style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
        _box(Text(
          '[실패 로그 · 마지막 40줄, 비밀값 가림]\n'
          'error: The engine "node" is incompatible with this module.\n'
          'Expected version ">=18 <21". Got "22.3.0"\n'
          '…\n'
          '[마지막 성공 환경과 비교]\n'
          'node   20.11.1 → 22.3.0\n'
          'mysql  8.0 → 8.4',
          style: mono.copyWith(fontSize: 12, height: 1.6),
        )),
        const Text('보내지 않는 것: .env 값, API 키, 소스 코드', style: TextStyle(fontSize: 13, color: C.text2)),
        _cancelOk(context, '보내기'),
      ]);
}

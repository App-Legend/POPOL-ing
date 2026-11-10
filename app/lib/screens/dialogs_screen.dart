import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/theme.dart';
import 'settings_screen.dart';

/// 7. 확인 대화상자 — 세 대화상자를 나란히 보여주는 시안 화면.
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
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFFFF8E6), border: Border.all(color: const Color(0xFFF1D79A)), borderRadius: BorderRadius.circular(8)),
        child: const Text('셸 모드(shell: true)를 쓰는 항목은 없어요.', style: TextStyle(fontSize: 13, color: Color(0xFF5A3B00))),
      ),
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

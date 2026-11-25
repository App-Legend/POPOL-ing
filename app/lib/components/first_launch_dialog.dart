import 'package:flutter/material.dart';

import 'package:popoling_core/models.dart';
import 'package:popoling_core/ui.dart';
import 'package:popoling_project/project.dart';

/// 처음 열 때 실행할 명령을 확인받는 다이얼로그(FR-13).
///
/// B 역할이 위젯만 만들고, 띄우는 흐름(라우트·호출)은 A 역할이 `app/` 에서 연결한다.
class FirstLaunchDialog extends StatelessWidget {
  const FirstLaunchDialog({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final commands = project.config?.services.isEmpty ?? true
        ? '실행할 항목이 없어요.'
        : summarizeCommands(project.config!.services);

    return Dialog(
      child: DialogBody(
        '‘${project.name}’ 를 처음 열어 실행할까요?',
        [
          const Text(
            '아래 명령이 실행돼요. 계속하려면 [실행] 을 눌러 주세요.',
            style: TextStyle(fontSize: 14, color: C.muted),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              border: Border.all(color: C.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              commands,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Btn('취소', onPressed: () => Navigator.pop(context, false)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Btn('실행', primary: true, onPressed: () => Navigator.pop(context, true)),
            ),
          ]),
        ],
      ),
    );
  }
}

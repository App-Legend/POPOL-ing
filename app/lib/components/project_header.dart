import 'package:flutter/material.dart';

import 'package:popoling_core/models.dart';
import 'package:popoling_core/ui.dart';

/// 프로젝트 이름·등록일·메모 요약을 보여주는 공통 헤더(FR-15).
/// 여러 화면에서 재사용된다.
class ProjectHeader extends StatelessWidget {
  const ProjectHeader({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final memo = project.about.memo;
    return Panel(
      title: project.name,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Row(children: [
          const Text('등록일: ', style: TextStyle(fontSize: 13, color: C.muted)),
          Text(_formatDate(project.registeredAt), style: const TextStyle(fontSize: 13)),
        ]),
        if (memo != null && memo.isNotEmpty) ...[
          const Text('메모: ', style: TextStyle(fontSize: 13, color: C.muted)),
          Text(memo, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
        ] else ...[
          Notice(
            bg: C.headBg,
            border: const Color(0xFFE5E8F0),
            child: const Text(
              '메모가 없어요. 설정 화면에서 메모를 추가해 주세요.',
              style: TextStyle(fontSize: 13, color: C.muted),
            ),
          ),
        ],
      ]),
    );
  }

  static String _formatDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';
}

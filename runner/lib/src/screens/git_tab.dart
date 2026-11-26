import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../git/git_adapter.dart';

/// 프로젝트 화면 Git 탭(FR-19, 목업 v2 G 위쪽 "원격과 비교"). 버튼 없이 상태만 보여 준다.
class GitTab extends StatefulWidget {
  const GitTab({super.key, required this.projectId, required this.projects, required this.git});

  final String projectId;
  final ProjectRepository projects;
  final GitAdapter git;

  @override
  State<GitTab> createState() => _GitTabState();
}

class _GitTabState extends State<GitTab> {
  GitStatus? _status;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final p = await widget.projects.getProject(widget.projectId);
        final s = await widget.git.status(p.folderPath);
        if (mounted) setState(() => _status = s);
      } catch (_) {
        // 읽지 못하면 저장소가 아닌 것처럼 보인다
      }
      if (mounted) setState(() => _loaded = true);
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    final s = _status;
    if (s == null) return const Text('이 폴더는 Git 저장소가 아니에요', style: TextStyle(color: C.muted));
    return Panel(
      title: '원격과 비교',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Row(spacing: 6, children: [
          const Icon(Icons.call_split, size: 16, color: C.text2, semanticLabel: 'Git 브랜치'),
          Text(s.branch ?? '브랜치 없음', style: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
          if (s.upstream != null) Text('· 원격 ${s.upstream}', style: const TextStyle(fontSize: 13, color: C.muted)),
        ]),
        if (s.upstream == null)
          const Text('비교할 원격 브랜치가 없어요.', style: TextStyle(fontSize: 14))
        else if (s.behind > 0)
          Text('${s.behind}커밋 뒤처져 있어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.warn.$2))
        else
          const Text('최신이에요', style: TextStyle(fontSize: 14)),
        if (s.changed > 0) Text('커밋 안 한 변경 ${s.changed}개', style: const TextStyle(fontSize: 14, color: C.text2)),
      ]),
    );
  }
}

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
    const strong = TextStyle(fontWeight: FontWeight.w700, color: C.text);
    final compare = s.upstream == null
        ? const TextSpan(text: '비교할 원격 브랜치가 없어요.')
        : s.behind > 0
            ? TextSpan(children: [TextSpan(text: '원격(${s.upstream})보다 '), TextSpan(text: '${s.behind}커밋 뒤처져 있어요', style: strong)])
            : TextSpan(text: '원격(${s.upstream})과 같아요 · 최신이에요');
    return Panel(
      title: '원격과 비교',
      titleAction: Tag(s.branch ?? '브랜치 없음'),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Text.rich(compare, style: const TextStyle(fontSize: 14, color: C.text2)),
        ),
        if (s.changed > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: '커밋 안 한 변경 '),
                TextSpan(text: '${s.changed}개', style: strong),
                const TextSpan(text: ' · 최신 코드를 받아도 내 변경은 그대로 둬요.'),
              ]),
              style: const TextStyle(fontSize: 13.5, color: C.text2),
            ),
          ),
      ]),
    );
  }
}

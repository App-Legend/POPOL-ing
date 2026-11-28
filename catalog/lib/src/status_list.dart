import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'catalog_view.dart';
import 'run_info.dart';

/// 왼쪽 메뉴 "지금 상태": 마지막 실행이 실패한 프로젝트와 오래된 프로젝트. 누르면 그 프로젝트 화면으로 간다.
class StatusList extends StatefulWidget {
  const StatusList({super.key, required this.projects, required this.runs, this.clock = DateTime.now});

  final ProjectRepository projects;
  final RunInfoSource runs;
  final DateTime Function() clock;

  @override
  State<StatusList> createState() => _StatusListState();
}

class _StatusListState extends State<StatusList> {
  List<Project> _projects = const [];
  Map<String, RunInfo> _runs = const {};
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(widget.projects.watchProjects().listen((p) => setState(() => _projects = p), onError: (_) {}))
      ..add(widget.runs.watchRunInfo().listen((r) => setState(() => _runs = r), onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final rows = <(Project, String, Color, MascotPose)>[];
    for (final p in _projects) {
      final e = CatalogEntry(p, _runs[p.id] ?? RunInfo.none);
      if (!e.isRunning && e.run.lastSucceeded == false) {
        rows.add((p, '실패 · 눌러서 원인 보기', const Color(0xFFFF8A80), MascotPose.fallen));
      } else if (e.isStale(now)) {
        rows.add((p, cardStateLabel(e, now), const Color(0xFFE0B36A), MascotPose.sleeping));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Text('지금 상태', style: TextStyle(fontSize: 12, color: C.navMuted, fontWeight: FontWeight.w600)),
      ),
      for (final (p, label, color, pose) in rows)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.pushNamed(context, '/dashboard', arguments: p.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(spacing: 10, children: [
              Mascot(pose, size: 40, dark: true),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

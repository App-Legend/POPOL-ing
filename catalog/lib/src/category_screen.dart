import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'run_info.dart';

/// 1. 카테고리 선택. 앱을 열면 항상 이 화면부터 보인다(AT-16). MVP 는 개발 카테고리 하나.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.projects, required this.runs});

  final ProjectRepository projects;
  final RunInfoSource runs;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Project>? _projects;
  Map<String, RunInfo> _runs = const {};
  late final StreamSubscription<List<Project>> _projectSub;
  late final StreamSubscription<Map<String, RunInfo>> _runSub;

  @override
  void initState() {
    super.initState();
    // 숫자를 못 읽어도 카드는 눌러 들어갈 수 있어야 해서, 오류는 숫자만 빼고 넘어간다.
    _projectSub = widget.projects.watchProjects().listen((p) => setState(() => _projects = p), onError: (Object _) {});
    _runSub = widget.runs.watchRunInfo().listen((r) => setState(() => _runs = r), onError: (Object _) {});
  }

  @override
  void dispose() {
    _projectSub.cancel();
    _runSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final running = projects?.where((p) => (_runs[p.id]?.running ?? 0) > 0).length ?? 0;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
              Logo(size: 44),
              Text('포폴링', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              Padding(padding: EdgeInsets.only(top: 8), child: Text('POPOL-ing', style: TextStyle(fontFamily: 'Menlo', fontSize: 14, color: C.muted))),
            ]),
            const SizedBox(height: 28),
            const Text('어떤 포트폴리오를 관리할까요?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('카테고리를 고르면 그 분야의 포트폴리오를 한곳에서 볼 수 있어요.', style: TextStyle(fontSize: 15, color: C.muted)),
            const SizedBox(height: 40),
            SizedBox(
              width: 360,
              child: Material(
                color: C.surface,
                shape: RoundedRectangleBorder(side: const BorderSide(color: C.border), borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  key: const Key('category-dev'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pushNamed(context, '/home'),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: C.primarySoft, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.code, color: C.primary, size: 28),
                      ),
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                        Text('개발', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        Text('내 컴퓨터의 프로젝트를 한눈에 보고, 바로 실행하고, 계속 실행되는 상태로 관리해요.',
                            style: TextStyle(fontSize: 14, color: C.muted, height: 1.6)),
                      ]),
                      if (projects != null)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          StatusChip('프로젝트 ${projects.length}개', C.idle, dot: false),
                          if (running > 0) StatusChip('실행 중 $running개', C.ok, dot: false),
                        ]),
                      const Row(spacing: 6, children: [
                        Text('열기', style: TextStyle(color: C.primary, fontSize: 14, fontWeight: FontWeight.w500)),
                        Icon(Icons.arrow_forward, size: 16, color: C.primary),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

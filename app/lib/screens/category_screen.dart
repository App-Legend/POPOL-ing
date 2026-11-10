import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/theme.dart';

/// 0. 카테고리 선택
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
              Logo(size: 44),
              Text('포폴링', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              Padding(padding: EdgeInsets.only(top: 8), child: Text('PPOL-ing', style: TextStyle(fontFamily: 'Menlo', fontSize: 14, color: C.muted))),
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
                        Text('로컬 프로젝트를 한눈에 보고, 바로 실행하고, 계속 실행 가능한 상태로 관리해요.',
                            style: TextStyle(fontSize: 14, color: C.muted, height: 1.6)),
                      ]),
                      const Wrap(spacing: 8, children: [
                        StatusChip('프로젝트 5개', C.idle, dot: false),
                        StatusChip('실행 중 1개', C.ok, dot: false),
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

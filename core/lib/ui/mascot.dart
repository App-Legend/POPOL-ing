import 'package:flutter/material.dart';

import 'theme.dart';

/// 프로젝트 상태를 보여 주는 캐릭터(목업 v2 마스코트). 상태 글자와 함께 쓴다(색·그림만으로 구분하지 않는다).
enum MascotPose {
  /// 모두 준비 완료.
  running,

  /// 일부만 떠 있음.
  running2,

  /// 시작 중.
  warmup,

  /// 실패.
  fallen,

  /// 중지(실행 기록 있음).
  resting,

  /// 오래됨.
  sleeping,

  /// 실행 방법 없음.
  empty,

  /// 기다림(Docker 꺼짐 등 도움이 필요함).
  waving,
}

/// 둥근 네모 안에 캐릭터. [dark] 는 어두운 왼쪽 메뉴용 배경.
class Mascot extends StatelessWidget {
  const Mascot(this.pose, {super.key, this.size = 72, this.dark = false});

  final MascotPose pose;
  final double size;
  final bool dark;

  static Color _tint(MascotPose p) => switch (p) {
        MascotPose.running || MascotPose.running2 => const Color(0xFFE5F4EA),
        MascotPose.warmup => const Color(0xFFECF1FF),
        MascotPose.fallen => const Color(0xFFFDECEA),
        MascotPose.sleeping => const Color(0xFFF4EDE9),
        MascotPose.waving => const Color(0xFFFFF3D6),
        MascotPose.resting || MascotPose.empty => const Color(0xFFEEF0F3),
      };

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.1),
        decoration: BoxDecoration(color: dark ? C.navActive : _tint(pose), borderRadius: BorderRadius.circular(size * 0.22)),
        child: Image.asset('assets/mascot/${pose.name}.png', package: 'popoling_core', filterQuality: FilterQuality.medium),
      );
}

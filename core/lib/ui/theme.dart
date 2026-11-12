import 'package:flutter/material.dart';

/// 시안(포폴링 화면 설계)의 색상 값.
class C {
  static const bg = Color(0xFFF6F7F9);
  static const surface = Colors.white;
  static const border = Color(0xFFE3E6EB);
  static const borderStrong = Color(0xFFD5D9E0);
  static const divider = Color(0xFFEEF0F3);
  static const headBg = Color(0xFFFAFBFC);
  static const text = Color(0xFF16181D);
  static const text2 = Color(0xFF4A505C);
  static const muted = Color(0xFF5B6270);
  static const primary = Color(0xFF2F5BEA);
  static const primarySoft = Color(0xFFEAF0FF);
  static const dark = Color(0xFF16181D);
  static const darkLine = Color(0xFF2A2D35);
  static const logText = Color(0xFFC9CDD4);

  // 상태 칩: (배경, 글자)
  static const ok = (Color(0xFFE5F4EA), Color(0xFF1E6B36));
  static const warn = (Color(0xFFFFF3D6), Color(0xFF7A4F00));
  static const bad = (Color(0xFFFDECEA), Color(0xFFA8261C));
  static const idle = (Color(0xFFEEF0F3), Color(0xFF4A505C));
  static const port = (Color(0xFFFDEBDD), Color(0xFF94400C));
  static const remote = (Color(0xFFF2F5FF), Color(0xFF1F44C4));
}

const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['Consolas', 'monospace']);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: C.surface),
      textTheme: const TextTheme().apply(bodyColor: C.text, displayColor: C.text),
      dividerColor: C.divider,
    );

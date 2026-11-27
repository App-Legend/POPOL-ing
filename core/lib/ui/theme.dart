import 'package:flutter/material.dart';

/// 시안(포폴링 화면 설계)의 색상 값.
class C {
  static const bg = Color(0xFFF4F5F7);
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

  // 왼쪽 메뉴(목업 v2): 어두운 배경, 고른 항목은 한 단계 밝게.
  static const nav = Color(0xFF1C1E24);
  static const navActive = Color(0xFF2E323C);
  static const navText = Color(0xFFC9CDD4);
  static const navMuted = Color(0xFF9AA1AD);
  static const logo = Color(0xFFE4572E);

  // 상태 칩: (배경, 글자)
  static const ok = (Color(0xFFE5F4EA), Color(0xFF1E6B36));
  static const warn = (Color(0xFFFFF3D6), Color(0xFF7A4F00));
  static const bad = (Color(0xFFFDECEA), Color(0xFFA8261C));
  static const idle = (Color(0xFFEEF0F3), Color(0xFF4A505C));
  static const port = (Color(0xFFFDEBDD), Color(0xFF94400C));
  static const remote = (Color(0xFFF2F5FF), Color(0xFF1F44C4));
}

/// 코드·숫자 글꼴(JetBrains Mono). 앱에 넣은 글꼴이라 OS 와 상관없이 같다.
const mono = TextStyle(fontFamily: 'JetBrainsMono', package: 'popoling_core', fontFamilyFallback: ['IBMPlexSansKR']); // package 를 주면 대체 글꼴 이름에도 packages/popoling_core/ 가 붙는다

/// 본문 글꼴(IBM Plex Sans KR).
const bodyFont = 'packages/popoling_core/IBMPlexSansKR';

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: bodyFont,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: C.surface),
      textTheme: const TextTheme().apply(bodyColor: C.text, displayColor: C.text),
      dividerColor: C.divider,
      // 목업 v2 확인 창: 흰 바탕, 모서리 14, 버튼은 높이 38·모서리 8(공통 Btn 과 같은 모양).
      dialogTheme: DialogThemeData(
        backgroundColor: C.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _buttonShape),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonShape.copyWith(
          foregroundColor: const WidgetStatePropertyAll(C.text),
          side: const WidgetStatePropertyAll(BorderSide(color: C.borderStrong)),
        ),
      ),
    );

final _buttonShape = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: bodyFont, fontSize: 14, fontWeight: FontWeight.w600)),
);

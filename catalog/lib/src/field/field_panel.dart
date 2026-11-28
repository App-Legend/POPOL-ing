import 'package:flutter/material.dart';
import 'package:popoling_core/ui.dart';

import 'field_data.dart';
import 'field_lineup.dart';

/// 운동장 레인 하나에 세울 프로젝트(목업 v2 홈 오른쪽).
enum FieldPose {
  /// 달리는 중: 실행 중.
  run,

  /// 넘어짐: 마지막 실행 실패.
  fallen,

  /// 출발선 대기: 중지.
  wait,

  /// 빈 레인: 실행 방법 없음.
  empty,
}

class FieldRunner {
  const FieldRunner({required this.name, required this.status, required this.pose});

  final String name;

  /// 이름표 둘째 줄. 예: `실행 중 · 1/1`, `실패 · 원인 보기`
  final String status;
  final FieldPose pose;
}

/// 홈 오른쪽 "운동장": 프로젝트 상태를 픽셀 캐릭터로 보여 준다. 레인 4개 + 벤치(오래된 프로젝트).
///
/// 그림만으로 구분하지 않게 이름표에 상태 글자를 함께 쓴다.
class FieldPanel extends StatefulWidget {
  const FieldPanel({super.key, required this.lineup});

  /// 레인(앞의 4개만 그린다)·벤치·전광판 숫자.
  final FieldLineup lineup;

  @override
  State<FieldPanel> createState() => _FieldPanelState();
}

class _FieldPanelState extends State<FieldPanel> {
  var _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) {
      return Container(
        width: 40,
        color: const Color(0xFF1C1E24),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 6),
        child: IconButton(
          tooltip: '운동장 보기',
          onPressed: () => setState(() => _hidden = false),
          icon: const Icon(Icons.chevron_left, size: 18, color: C.navMuted),
        ),
      );
    }
    final lanes = widget.lineup.lanes.take(4).toList();
    final bench = widget.lineup.bench;
    final score = widget.lineup.score;
    return Container(
      width: 300,
      color: const Color(0xFF1C1E24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 44,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2E323C)))),
          child: Row(children: [
            const Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '운동장 ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '· 실시간', style: TextStyle(color: C.navMuted)),
              ]), style: TextStyle(fontSize: 13, color: Color(0xFFE6E8EC))),
            ),
            IconButton(
              tooltip: '운동장 숨기기',
              onPressed: () => setState(() => _hidden = true),
              icon: const Icon(Icons.chevron_right, size: 18, color: C.navMuted),
            ),
          ]),
        ),
        // 창이 낮아도 넘치지 않게 남은 높이에 맞춰 줄인다(1280×720 에서 24px 넘쳤다).
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Semantics(
              label: '운동장 $score: ${[for (final l in widget.lineup.lanes) '${l.name} ${l.status}', if (bench case (final n, final s)?) '$n $s'].join(', ')}',
              child: AspectRatio(
                aspectRatio: 90 / 200,
                child: CustomPaint(painter: _FieldPainter(lanes, bench, score)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.lanes, this.bench, this.score);

  final List<FieldRunner> lanes;
  final (String, String)? bench;
  final String score;

  static const _laneTop = 54.0; // 1레인 이름표 y
  static const _laneGap = 24.0;

  static const _origin = {FieldPose.run: 0, FieldPose.fallen: 1, FieldPose.wait: 2, FieldPose.empty: 3};
  static const _sprites = {FieldPose.run: spriteRun, FieldPose.fallen: spriteFallen, FieldPose.wait: spriteWait, FieldPose.empty: spriteEmpty};
  static const _barColor = {
    FieldPose.run: Color(0xFF3DBE6B),
    FieldPose.fallen: Color(0xFFE5484D),
    FieldPose.wait: Color(0xFF9AA1AD),
    FieldPose.empty: Color(0xFF5B6270),
  };
  static const _statusColor = {
    FieldPose.run: Color(0xFF7FD69B),
    FieldPose.fallen: Color(0xFFFF8A80),
    FieldPose.wait: Color(0xFFC9CDD4),
    FieldPose.empty: Color(0xFF9AA1AD),
  };

  void _rects(Canvas canvas, List<PixelRect> rects, {double dy = 0}) {
    final paint = Paint()..isAntiAlias = false;
    for (final (x, y, w, h, c) in rects) {
      canvas.drawRect(Rect.fromLTWH(x, y + dy, w, h), paint..color = Color(c));
    }
  }

  /// 격자 단위 글자. [maxWidth] 를 넘으면 말줄임.
  double _text(Canvas canvas, String text, Offset at, double size, Color color, {FontWeight weight = FontWeight.w700, double maxWidth = 40, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: weight, color: color, height: 1)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
    return tp.width;
  }

  void _label(Canvas canvas, double x, double y, String name, String status, Color bar, Color statusColor) {
    final nameW = TextPainter(
      text: TextSpan(text: name, style: const TextStyle(fontFamily: bodyFont, fontSize: 3.1, fontWeight: FontWeight.w700, height: 1)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 30);
    final w = (nameW.width + 3.6).clamp(14.0, 32.0);
    canvas.drawRect(Rect.fromLTWH(x, y, w, 8.5), Paint()..color = const Color(0xE016181D));
    canvas.drawRect(Rect.fromLTWH(x, y, 0.8, 8.5), Paint()..color = bar);
    _text(canvas, name, Offset(x + 1.8, y + 0.9), 3.1, Colors.white, maxWidth: w - 2.4);
    _text(canvas, status, Offset(x + 1.8, y + 4.8), 2.7, statusColor, weight: FontWeight.w600, maxWidth: 34);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 90);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 90, 200));
    _rects(canvas, fieldBackground);
    _text(canvas, '포폴링 운동장', const Offset(45, 4.6), 3, const Color(0xFFFFD27A), center: true);
    _text(canvas, score, const Offset(45, 8.9), 2.6, const Color(0xFF7FD69B), weight: FontWeight.w600, center: true, maxWidth: 32);
    _text(canvas, '포폴링 코치', const Offset(18.8, 44.2), 3.1, Colors.white);
    _text(canvas, '지켜보는 중', const Offset(18.8, 48.1), 2.7, C.navMuted, weight: FontWeight.w600);
    for (final (i, n) in ['1', '2', '3', '4'].indexed) {
      _text(canvas, n, Offset(4.6, 61.5 + i * _laneGap), 5, const Color(0xB3F4E9E2), center: false);
    }
    for (final (i, lane) in lanes.indexed) {
      _rects(canvas, _sprites[lane.pose]!, dy: (i - _origin[lane.pose]!) * _laneGap);
      _label(canvas, 56, _laneTop + i * _laneGap, lane.name, lane.status, _barColor[lane.pose]!, _statusColor[lane.pose]!);
    }
    if (bench case (final name, final status)?) {
      _rects(canvas, spriteSleep);
      _text(canvas, 'z', const Offset(32, 160.5), 4, Colors.white);
      _text(canvas, 'z', const Offset(36, 157.3), 3, Colors.white);
      _label(canvas, 52, 156, name, status, const Color(0xFFB7791F), const Color(0xFFE0B36A));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.lanes != lanes || old.bench != bench || old.score != score;
}

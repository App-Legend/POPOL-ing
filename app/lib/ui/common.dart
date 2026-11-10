import 'package:flutter/material.dart';

import 'theme.dart';

/// 상단 바(로고 + 경로) + 가운데 정렬된 본문. 모든 내부 화면이 공유한다.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.crumbs, required this.children, this.trailing});

  /// 경로. 마지막 항목은 현재 화면, 나머지는 (이름, 라우트).
  final List<(String, String?)> crumbs;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
          child: Row(children: [
            InkWell(
              onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Row(children: [Logo(size: 28), SizedBox(width: 8), Text('포폴링', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]),
            ),
            const SizedBox(width: 16),
            for (final (i, (label, route)) in crumbs.indexed) ...[
              const Text(' / ', style: TextStyle(color: C.muted, fontSize: 14)),
              i == crumbs.length - 1
                  ? Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
                  : LinkText(label, onTap: () => go(context, route!)),
            ],
            const Spacer(),
            ?trailing,
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: children),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 같은 화면이 스택에 있으면 거기로 돌아가고, 없으면 새로 연다.
void go(BuildContext context, String route) {
  final nav = Navigator.of(context);
  var found = false;
  nav.popUntil((r) {
    if (r.settings.name == route) found = true;
    return found || r.isFirst;
  });
  if (!found) nav.pushNamed(route);
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Text('P', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.48)),
      );
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, this.onTap, this.size = 14, this.color = C.primary});
  final String text;
  final VoidCallback? onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap ?? () {},
        child: Text(text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w500)),
      );
}

/// 제목 + 설명 + 오른쪽 버튼들.
class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.sub, this.subMono = false, this.actions = const []});
  final String title;
  final String? sub;
  final bool subMono;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if (sub != null) ...[
              const SizedBox(height: 6),
              Text(sub!, style: (subMono ? mono : const TextStyle()).copyWith(fontSize: subMono ? 13 : 14, color: C.muted)),
            ],
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
}

/// 둥근 상태 칩. [dot]이면 앞에 점을 찍는다.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.tone, {super.key, this.dot = true});
  final String label;
  final (Color, Color) tone;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: tone.$2, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: tone.$2, fontSize: 12, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// 기술 스택·유형 태그.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.tone});
  final String label;
  final (Color, Color)? tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tone?.$1 ?? C.surface,
          border: Border.all(color: tone == null ? C.borderStrong : const Color(0xFFB9C8F5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: tone?.$2 ?? C.text2)),
      );
}

/// 흰 카드. [title]이 있으면 위에 제목.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.titleAction, required this.child, this.padding = const EdgeInsets.all(20)});
  final String? title;
  final Widget? titleAction;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ?titleAction,
              ]),
            ),
          Padding(padding: padding, child: child),
        ]),
      );
}

/// 시안의 .btn / .btn-primary. [onPressed]가 null이면 비활성.
class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onPressed = _noop, this.primary = false, this.icon, this.small = false, this.ghost = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  final bool small;
  final bool ghost;

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    final style = (primary ? FilledButton.styleFrom() : OutlinedButton.styleFrom()).copyWith(
      minimumSize: WidgetStatePropertyAll(Size(0, small ? 36 : 44)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: small ? 12 : 16)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      side: primary ? null : WidgetStatePropertyAll(BorderSide(color: ghost ? Colors.transparent : C.borderStrong)),
      foregroundColor: primary ? null : const WidgetStatePropertyAll(C.text),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
    final child = icon == null
        ? Text(label)
        : Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [Icon(icon, size: 16), Text(label)]);
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

/// 이름-값 목록 (dl).
class KeyValues extends StatelessWidget {
  const KeyValues(this.rows, {super.key, this.labelWidth = 112});
  final List<(String, Widget)> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Column(
        spacing: 10,
        children: [
          for (final (k, v) in rows)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: labelWidth, child: Text(k, style: const TextStyle(fontSize: 13, color: C.muted))),
              Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: v)),
            ]),
        ],
      );
}

/// 머리행이 있는 표. 좁으면 가로 스크롤.
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rows, this.minWidth = 820});
  final List<String> columns;
  final List<List<Widget>> rows;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: box.maxWidth < minWidth ? minWidth : box.maxWidth,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: C.headBg, border: Border(bottom: BorderSide(color: C.border))),
                  children: [for (final c in columns) _cell(Text(c, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w500)), 12)],
                ),
                for (final r in rows)
                  TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.divider))),
                    children: [for (final c in r) _cell(DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: c), 14)],
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _cell(Widget w, double v) => Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: v), child: w);
}

/// 경고·안내 띠 (노란·빨간·주황 배경 상자).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.child, required this.bg, required this.border, this.icon, this.iconColor, this.trailing = const []});
  final Widget child;
  final Color bg, border;
  final IconData? icon;
  final Color? iconColor;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
        child: Row(spacing: 12, children: [
          if (icon != null) Icon(icon, size: 18, color: iconColor),
          Expanded(child: child),
          ...trailing,
        ]),
      );
}

/// 어두운 로그 상자 안의 한 줄. [level]은 INFO/WARN/포폴링 색을 정한다.
TextSpan logLine(String time, String level, String msg, {String? note}) {
  final levelColor = switch (level) {
    'WARN' => const Color(0xFFF0B84D),
    '포폴링' => const Color(0xFF7DD3A0),
    _ => const Color(0xFF9DB6FF),
  };
  return TextSpan(children: [
    TextSpan(text: '$time  '),
    if (level.isNotEmpty) TextSpan(text: '$level  ', style: TextStyle(color: levelColor)),
    TextSpan(text: msg),
    if (note != null) TextSpan(text: ' $note', style: const TextStyle(color: Color(0xFF8A909C))),
    const TextSpan(text: '\n'),
  ]);
}

/// 너비에 맞춰 [minItemWidth] 이상으로 칸을 나누는 그리드 (CSS auto-fit 대체).
class AutoGrid extends StatelessWidget {
  const AutoGrid({super.key, required this.minItemWidth, required this.children, this.gap = 16});
  final double minItemWidth;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = ((box.maxWidth + gap) / (minItemWidth + gap)).floor().clamp(1, children.length);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

import 'package:flutter/material.dart';

import 'shell.dart';
import 'theme.dart';

/// 왼쪽 메뉴 + 본문 틀. 모든 내부 화면이 공유한다(목업 v2).
///
/// 메뉴: 로고, 카테고리 · 개발, 내 프로젝트, AI 검사, 앱 설정, 그 아래 [ShellScope] 자리(지금 상태 목록).
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.crumbs, required this.children, this.trailing, this.side, this.header});

  /// 경로. 마지막 항목은 현재 화면, 나머지는 (이름, 라우트). 본문 맨 위에 작게 보인다.
  final List<(String, String?)> crumbs;
  final List<Widget> children;
  final Widget? trailing;

  /// 본문 오른쪽에 붙는 패널(예: 개발 홈의 운동장). 본문과 따로 스크롤된다.
  final Widget? side;

  /// 본문 위 흰 머리 영역(프로젝트 화면의 이름·탭). 화면 폭 전체에 붙고 아래 테두리가 있다.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _SideMenu(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (header case final h?)
                Container(
                  decoration: const BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
                  child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1304), child: h)),
                ),
              Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [
                    // 목업 v2: 아래 단계 화면만 맨 위에 "‹ 상위 화면" 돌아가기 링크를 둔다.
                    if (crumbs.length > 1 || trailing != null)
                      Row(children: [
                        if (crumbs.length > 1 && crumbs.first.$2 != null)
                          InkWell(
                            onTap: () => go(context, crumbs.first.$2!),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.chevron_left, size: 16, color: C.text2),
                              Text(crumbs.first.$1, style: const TextStyle(fontSize: 13, color: C.text2)),
                            ]),
                          ),
                        const Spacer(),
                        ?trailing,
                      ]),
                    ...children,
                  ]),
                ),
              ),
              ),
            ]),
          ),
        ),
        ?side,
      ]),
    );
  }
}

class _SideMenu extends StatelessWidget {
  const _SideMenu();

  static const _items = [
    ('내 프로젝트', '/home', Icons.folder_outlined),
    ('AI 검사', '/ai', Icons.auto_awesome_outlined),
    ('앱 설정', '/app-settings', Icons.settings_outlined), // 화면은 ai/ 가 등록한다(#105)
  ];

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;
    final active = current == '/dashboard' ? '/home' : current;
    final status = ShellScope.statusOf(context);
    return Container(
      width: 224,
      color: C.nav,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Row(children: [Logo(size: 18), SizedBox(width: 8), Text('포폴링', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white))]),
          ),
        ),
        InkWell(
          onTap: () => go(context, '/'),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(Icons.chevron_left, size: 16, color: C.navMuted),
              SizedBox(width: 4),
              Text('카테고리 · 개발', style: TextStyle(fontSize: 13, color: C.navMuted)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        for (final (label, route, icon) in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: active == route ? C.navActive : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: ValueKey('menu-$route'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => go(context, route),
                child: SizedBox(
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Icon(icon, size: 18, color: active == route ? Colors.white : C.navText),
                      const SizedBox(width: 10),
                      Text(label, style: TextStyle(fontSize: 14, fontWeight: active == route ? FontWeight.w600 : FontWeight.w400, color: active == route ? Colors.white : C.navText)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        // "지금 상태" 제목은 목록이 직접 그린다(보여 줄 프로젝트가 없으면 제목도 숨긴다).
        if (status != null) ...[
          const Spacer(),
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: SingleChildScrollView(child: status)),
        ],
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

/// 포폴링 로고(주황 P). 목업 v2 의 SVG 경로를 그대로 그린다.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256);
    // M53 210V100A75 75 0 1 1 128 175A19 19 0 0 1 128 137A37 37 0 1 0 91 100V210A19 19 0 0 1 53 210Z
    final path = Path()
      ..moveTo(53, 210)
      ..lineTo(53, 100)
      ..arcToPoint(const Offset(128, 175), radius: const Radius.circular(75), largeArc: true)
      ..arcToPoint(const Offset(128, 137), radius: const Radius.circular(19))
      ..arcToPoint(const Offset(91, 100), radius: const Radius.circular(37), largeArc: true, clockwise: false)
      ..lineTo(91, 210)
      ..arcToPoint(const Offset(53, 210), radius: const Radius.circular(19))
      ..close();
    canvas.drawPath(path, Paint()..color = C.logo);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
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
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, widthFactor: 1, heightFactor: 1, child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: tone.$2, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: tone.$2, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      ));
}

/// 기술 스택·유형 태그.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.tone});
  final String label;
  final (Color, Color)? tone;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: tone?.$1 ?? C.headBg,
          border: Border.all(color: tone == null ? C.border : const Color(0xFFB9C8F5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(widthFactor: 1, child: Text(label, style: TextStyle(fontSize: 12, color: tone?.$2 ?? C.text2))),
      );
}

/// 흰 카드. [title]이 있으면 위에 제목.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.titleAction, this.subtitle, this.actions = const [], required this.child, this.padding = const EdgeInsets.all(20), this.danger = false});
  final String? title;

  /// 실패 안내(목업 v2): 빨간 테두리, 경고 아이콘과 빨간 제목, 제목 아래 구분선.
  final bool danger;

  /// 제목 바로 옆(예: 상태 칩).
  final Widget? titleAction;

  /// 제목 줄의 짧은 설명(목업 v2: 칩 뒤에 회색 글자).
  final String? subtitle;

  /// 제목 줄 오른쪽 버튼들.
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: C.surface, border: Border.all(color: danger ? const Color(0xFFF2B8B5) : C.border), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Container(
              padding: danger ? const EdgeInsets.fromLTRB(20, 14, 20, 14) : const EdgeInsets.fromLTRB(20, 16, 20, 0),
              decoration: danger ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF6D5D2)))) : null,
              child: Row(spacing: 10, children: [
                if (danger) Icon(Icons.warning_amber_rounded, size: 18, color: C.bad.$2),
                Text(title!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: danger ? C.bad.$2 : null)),
                ?titleAction,
                Expanded(child: subtitle == null ? const SizedBox() : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.text2))),
                ...actions,
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
      minimumSize: WidgetStatePropertyAll(Size(0, small ? 32 : 38)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: small ? 12 : 16)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      side: primary ? null : WidgetStatePropertyAll(BorderSide(color: ghost ? Colors.transparent : C.borderStrong)),
      foregroundColor: primary ? null : const WidgetStatePropertyAll(C.text),
      textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: bodyFont, fontSize: small ? 13 : 14, fontWeight: primary ? FontWeight.w600 : FontWeight.w500)),
      backgroundColor: primary ? null : WidgetStatePropertyAll(ghost ? Colors.transparent : C.surface),
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

/// 대화상자 본문: 제목 + 내용. `showDialog(builder: (_) => Dialog(child: ...))` 안이나 시안 화면에 그대로 넣는다.
class DialogBody extends StatelessWidget {
  const DialogBody(this.title, this.children, {super.key, this.maxWidth = 440});
  final String title;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ...children,
          ]),
        ),
      );
}

/// 대화상자로 열렸을 때만 [result] 를 돌려주며 닫는다. 시안 화면에 박혀 있을 땐 닫을 대화상자가 없다.
void closeDialog<T>(BuildContext context, [T? result]) {
  if (ModalRoute.of(context) is DialogRoute) Navigator.pop<T>(context, result);
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
        // 한 줄의 카드 높이를 맞춘다(목업 v2 격자). 마지막 줄의 빈 칸은 비워 둔다.
        return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: gap, children: [
          for (var i = 0; i < children.length; i += cols)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: [
                for (final c in children.skip(i).take(cols)) SizedBox(width: w, child: c),
              ]),
            ),
        ]);
      });
}

/// 다른 프로젝트 항목을 멈추기 전 확인(FR-06, 목업 v2 3c). [중지]면 true.
///
/// 포트를 내 다른 프로젝트 항목이 쓸 때만 쓴다. 외부 프로그램은 멈추지 않으므로 이 창도 없다.
Future<bool> confirmStopOther(BuildContext context, {required String project, required String service}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        child: DialogBody('다른 프로젝트의 $project / $service을 중지할까요?', [
          Text(
            '지금 보고 있는 프로젝트가 아니라 $project의 $service 항목이에요. 포폴링이 시작한 항목이라 중지할 수 있어요. '
            '$project의 다른 항목은 그대로 둬요.',
            style: const TextStyle(fontSize: 14, color: C.text2, height: 1.6),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            // 기본(Enter) 포커스는 [취소]. 다른 프로젝트 항목을 실수로 멈추지 않게 한다.
            OutlinedButton(autofocus: true, onPressed: () => closeDialog(c, false), child: const Text('취소')),
            FilledButton(onPressed: () => closeDialog(c, true), child: const Text('중지')),
          ]),
        ]),
      ),
    ) ??
    false;

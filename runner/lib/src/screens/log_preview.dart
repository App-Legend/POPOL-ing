import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../log/log_line.dart';
import '../log/log_store.dart';

/// 대시보드의 최근 로그. 실패한 항목을 먼저 보여 주고 다른 항목을 고를 수 있다. 비밀값은 파일에 쓸 때 이미 가려져 있다.
class LogPreview extends StatefulWidget {
  const LogPreview({super.key, required this.projectId, required this.services, required this.failed, required this.logs});

  final String projectId;

  /// 로그가 있는 항목(원격 제외). 비어 있으면 안 된다.
  final List<ServiceConfig> services;

  /// 실패한 항목 ID. 새로 실패하면 고른 항목 대신 이것을 보여 준다.
  final String? failed;
  final LogStore logs;

  @override
  State<LogPreview> createState() => _LogPreviewState();
}

class _LogPreviewState extends State<LogPreview> {
  String? _picked;
  String? _linesOf;
  var _lines = const <LogLine>[];
  late final Timer _poll;

  ServiceConfig get _service {
    ServiceConfig? byId(String? id) => widget.services.where((s) => s.id == id).firstOrNull;
    return byId(_picked) ??
        byId(widget.failed) ??
        widget.services.whereType<ProcessService>().firstOrNull ??
        widget.services.first;
  }

  ItemRef get _item => ItemRef(projectId: widget.projectId, serviceId: _service.id);

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  @override
  void didUpdateWidget(LogPreview old) {
    super.didUpdateWidget(old);
    if (widget.failed != null && widget.failed != old.failed) _picked = null;
    if (_service.id != _linesOf) unawaited(_read());
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_service is! ProcessService) return;
    final item = _item;
    final raw = await widget.logs.tail(item, lines: 8, maxRead: 64 * 1024);
    if (!mounted || item != _item) return; // 읽는 사이 다른 항목을 골랐다
    setState(() {
      _linesOf = item.serviceId;
      _lines = [for (final l in raw) parseLogLine(l)];
    });
  }

  void _pick(String id) {
    setState(() => _picked = id);
    unawaited(_read());
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    final lines = _linesOf == s.id ? _lines : const <LogLine>[];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
        Row(children: [
          Expanded(
            child: Text('최근 로그 · ${s.id}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE6E8EC))),
          ),
          LinkText('전체 로그', size: 13, color: const Color(0xFF9DB6FF), onTap: () => Navigator.pushNamed(context, '/detail', arguments: _item)),
        ]),
        if (widget.services.length > 1) Wrap(spacing: 4, runSpacing: 4, children: [for (final o in widget.services) _tab(o.id, o.id == s.id)]),
        if (s is! ProcessService)
          const Text('Compose 로그는 [전체 로그]에서 볼 수 있어요.', style: TextStyle(fontSize: 13, color: Color(0xFF8A909C)))
        else if (lines.isEmpty)
          const Text('아직 로그가 없어요. 항목을 시작하면 여기에 출력이 보여요.', style: TextStyle(fontSize: 13, color: Color(0xFF8A909C)))
        else
          Text.rich(
            TextSpan(children: [
              for (final l in lines) logLine(l.time, l.stream == 'out' ? '' : l.stream, _short(l.text)),
            ]),
            style: mono.copyWith(fontSize: 12, height: 1.7, color: C.logText),
          ),
      ]),
    );
  }

  /// 아주 긴 줄이 미리보기를 밀어내지 않게 자른다.
  static String _short(String text) {
    final chars = text.characters;
    return chars.length > 300 ? '${chars.take(300)}…' : text;
  }

  Widget _tab(String id, bool selected) => Semantics(
        selected: selected,
        child: TextButton(
          onPressed: () => _pick(id),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            backgroundColor: selected ? C.darkLine : null,
            foregroundColor: selected ? Colors.white : const Color(0xFF9AA1AD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(id),
        ),
      );
}

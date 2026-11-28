import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../log/log_line.dart';
import '../log/log_store.dart';
import 'item_status.dart';
import 'log_tab.dart';

/// 프로젝트 화면 로그 탭의 항목 로그(목업 v2). 항목이 바뀌면 `key` 로 새로 만든다.
///
/// 프로세스 로그는 [LogStore] 파일 끝을 1초마다 다시 읽고(비밀값은 이미 가려져 있다), Compose 로그는 [ItemLauncher.logs] 를 구독한다.
class ItemLogView extends StatefulWidget {
  const ItemLogView({super.key, required this.item, required this.service, required this.runner, required this.logs, required this.launcher});

  final ItemRef item;
  final ServiceConfig service;
  final Orchestrator runner;
  final LogStore logs;
  final ItemLauncher? launcher;

  @override
  State<ItemLogView> createState() => _ItemLogViewState();
}

/// 화면에 보여 주는 최근 줄 수.
const _maxLines = 5000;

class _ItemLogViewState extends State<ItemLogView> {
  var _lines = <LogLine>[];
  var _filter = 0; // 0 전체, 1 stdout, 2 stderr
  var _query = '';
  var _autoScroll = true;
  final _scroll = ScrollController();
  StreamSubscription<RunEvent>? _eventSub;
  StreamSubscription<String>? _composeSub;
  Timer? _poll;

  ItemRef get _item => widget.item;

  @override
  void initState() {
    super.initState();
    _eventSub = widget.runner.events.listen((e) {
      // Compose 는 새로 띄우면 컨테이너가 바뀌니 다시 구독한다.
      if (e case ItemStateChanged(:final item) when item == _item) {
        if (widget.service case final ComposeService s when isUp(widget.runner.stateOf(_item))) _followCompose(s);
      }
    });
    switch (widget.service) {
      case ProcessService():
        _readProcessLog();
        // 다른 화면에 가려져 있으면 읽지 않는다. 화면이 여러 개 쌓여도 매초 큰 파일을 겹쳐 읽지 않게.
        _poll = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && ModalRoute.of(context)?.isCurrent != false) _readProcessLog();
        });
      case final ComposeService s:
        _followCompose(s);
      case RemoteService():
        break;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _eventSub?.cancel();
    _composeSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _readProcessLog() async {
    final List<String> raw;
    try {
      raw = await widget.logs.tail(_item, lines: _maxLines);
    } catch (_) {
      return; // 읽지 못하면(권한·잠금) 이번 차례는 건너뛰고 다음 1초에 다시 읽는다
    }
    if (!mounted) return;
    final lines = [for (final l in raw) parseLogLine(l)];
    if (lines.length == _lines.length && (lines.isEmpty || lines.last == _lines.last)) return;
    setState(() => _lines = lines);
    _scrollToEnd();
  }

  void _followCompose(ComposeService s) {
    final launcher = widget.launcher;
    if (launcher == null) return;
    _composeSub?.cancel();
    setState(() => _lines = []);
    _composeSub = launcher.logs(_item.projectId, s).listen((l) {
      if (!mounted) return;
      setState(() {
        _lines.add((time: '', stream: 'out', text: l));
        if (_lines.length > _maxLines) _lines.removeRange(0, _lines.length - _maxLines);
      });
      _scrollToEnd();
    }, onError: (Object e) {
      if (mounted) setState(() => _lines.add((time: '', stream: '포폴링', text: errorText(e))));
    });
  }

  void _scrollToEnd() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  List<LogLine> get _visible => [
        for (final l in _lines)
          if ((_filter == 0 || l.stream == (_filter == 1 ? 'out' : 'err') || l.stream == '포폴링') &&
              (_query.isEmpty || l.text.toLowerCase().contains(_query.toLowerCase())))
            l,
      ];

  @override
  Widget build(BuildContext context) => _logBox(widget.service);

  Widget _logBox(ServiceConfig s) {
    Widget tab(String label, int i) => LogTab(label, selected: _filter == i, onPressed: () => setState(() => _filter = i));
    final visible = _visible;
    final empty = switch (s) {
      RemoteService() => '원격 항목은 포폴링이 띄우지 않아 로그가 없어요.',
      _ when _lines.isEmpty => '아직 로그가 없어요. 항목을 시작하면 여기에 출력이 보여요.',
      _ => '검색 결과가 없어요.',
    };
    Widget darkButton(String label, VoidCallback? onPressed, {bool on = false}) => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            backgroundColor: on ? C.darkLine : Colors.transparent,
            foregroundColor: const Color(0xFFE6E8EC),
            disabledForegroundColor: const Color(0xFF6B717C),
            side: const BorderSide(color: Color(0xFF3A3E48)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          child: Text(label),
        );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.darkLine))),
          child: Row(spacing: 6, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${s.id} 로그', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              TextSpan(text: s is ProcessService ? '  · 실시간' : '', style: const TextStyle(color: Color(0xFF8A909C))),
            ]), style: const TextStyle(fontSize: 13.5)),
            const SizedBox(width: 10),
            tab('전체', 0),
            if (s is ProcessService) ...[tab('stdout', 1), tab('stderr', 2)],
            // 좁은 창에서는 검색 칸이 줄어든다(최대 200).
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                    width: 200,
                    height: 32,
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '로그에서 찾기',
                        hintStyle: TextStyle(color: Color(0xFF8A909C), fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF8A909C)),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3E48)), borderRadius: BorderRadius.all(Radius.circular(6))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary), borderRadius: BorderRadius.all(Radius.circular(6))),
                      ),
                    ),
                  ),
              ),
            ),
            darkButton('자동 스크롤', () => setState(() => _autoScroll = !_autoScroll), on: _autoScroll),
            darkButton(
              '복사',
              visible.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: visible.map((l) => '${l.time} ${l.text}').join('\n')));
                      toast(context, '보이는 로그 ${visible.length}줄을 복사했어요.');
                    },
            ),
          ]),
        ),
        SizedBox(
          height: 300,
          child: visible.isEmpty
              ? Center(child: Text(empty, style: const TextStyle(color: Color(0xFF8A909C))))
              : SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: SelectableText.rich(
                    TextSpan(children: [
                      for (final l in visible) logLine(l.time, l.stream == 'out' ? '' : l.stream, l.text),
                    ]),
                    style: mono.copyWith(fontSize: 12.5, height: 1.8, color: C.logText),
                  ),
                ),
        ),
      ]),
    );
  }
}

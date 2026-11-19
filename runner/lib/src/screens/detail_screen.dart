import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/ui.dart';

import '../log/log_store.dart';
import '../orchestrator/runner_orchestrator.dart';
import 'item_status.dart';

/// 4. 실행 항목 상세 · 로그. 대시보드가 `arguments` 로 [ItemRef] 를 넘긴다.
///
/// 프로세스 로그는 [LogStore] 파일 끝을 1초마다 다시 읽고(비밀값은 이미 가려져 있다), Compose 로그는 [ItemLauncher.logs] 를 구독한다.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.projects,
    required this.runner,
    required this.process,
    required this.logs,
    required this.launcher,
  });

  final ItemRef item;
  final ProjectRepository projects;
  final Orchestrator runner;

  /// 지금 떠 있는 내 프로세스. 없으면 null.
  final LiveProcess? Function(ItemRef) process;
  final LogStore logs;
  final ItemLauncher launcher;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

/// 화면에 보여 주는 최근 줄 수.
const _maxLines = 5000;

typedef _Line = ({String time, String stream, String text});

class _DetailScreenState extends State<DetailScreen> {
  Project? _project;
  String? _loadError;
  var _lines = <_Line>[];
  var _filter = 0; // 0 전체, 1 stdout, 2 stderr
  var _query = '';
  var _autoScroll = true;
  var _busy = false;
  String? _reason;
  final _scroll = ScrollController();
  StreamSubscription<RunEvent>? _eventSub;
  StreamSubscription<String>? _composeSub;
  Timer? _poll;

  ItemRef get _item => widget.item;

  ServiceConfig? get _service => _project?.config?.services.where((s) => s.id == _item.serviceId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _eventSub = widget.runner.events.listen((e) {
      if (e case ItemStateChanged(:final item, :final reason) when item == _item) {
        setState(() => _reason = reason);
        // Compose 는 새로 띄우면 컨테이너가 바뀌니 다시 구독한다.
        if (_service case final ComposeService s when isUp(widget.runner.stateOf(_item))) _followCompose(s);
      }
    });
    widget.projects.getProject(_item.projectId).then((p) {
      if (!mounted) return;
      setState(() => _project = p);
      switch (_service) {
        case ProcessService():
          _readProcessLog();
          _poll = Timer.periodic(const Duration(seconds: 1), (_) => _readProcessLog());
        case final ComposeService s:
          _followCompose(s);
        case RemoteService() || null:
          break;
      }
    }, onError: (Object e) {
      if (mounted) setState(() => _loadError = errorText(e));
    });
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
    final raw = await widget.logs.tail(_item, lines: _maxLines);
    if (!mounted) return;
    final lines = [for (final l in raw) _parse(l)];
    if (lines.length == _lines.length && (lines.isEmpty || lines.last == _lines.last)) return;
    setState(() => _lines = lines);
    _scrollToEnd();
  }

  void _followCompose(ComposeService s) {
    _composeSub?.cancel();
    setState(() => _lines = []);
    _composeSub = widget.launcher.logs(_item.projectId, s).listen((l) {
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

  /// `LogStore` 한 줄(`<시각> out|err | <내용>` 또는 `--- 시작 <시각> ---`)을 나눈다.
  static _Line _parse(String l) {
    if (RegExp(r'^--- 시작 (\S+) ---$').firstMatch(l) case final m?) {
      return (time: _clock(m[1]!), stream: '포폴링', text: '실행 시작');
    }
    if (RegExp(r'^(\S+) (out|err) \| (.*)$').firstMatch(l) case final m?) {
      return (time: _clock(m[1]!), stream: m[2]!, text: m[3]!);
    }
    return (time: '', stream: 'out', text: l);
  }

  /// ISO 시각에서 `HH:mm:ss` 만.
  static String _clock(String iso) => DateTime.tryParse(iso)?.toIso8601String().substring(11, 19) ?? iso;

  void _scrollToEnd() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  List<_Line> get _visible => [
        for (final l in _lines)
          if ((_filter == 0 || l.stream == (_filter == 1 ? 'out' : 'err') || l.stream == '포폴링') &&
              (_query.isEmpty || l.text.toLowerCase().contains(_query.toLowerCase())))
            l,
      ];

  Future<void> _act(Future<ItemResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      if (mounted) setState(() => _reason = r.reason);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restart() => _act(() async {
        final stopped = await widget.runner.stop(_item);
        if (stopped.outcome != ItemOutcome.ok) return stopped;
        return widget.runner.start(_item);
      });

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final s = _service;
    final crumbs = [('개발', '/home'), (p?.name ?? _item.projectId, '/dashboard'), (_item.serviceId, null)];
    if (p == null || s == null) {
      final error = _loadError ?? (p != null ? '설정에 없는 항목이에요: ${_item.serviceId}' : null);
      return AppPage(crumbs: crumbs, children: [
        if (error != null) Text(error, style: const TextStyle(color: C.muted)) else const LinearProgressIndicator(),
      ]);
    }
    return AppPage(
      crumbs: crumbs,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
          SizedBox(width: 380, child: Column(spacing: 16, children: [_statusPanel(s), _configPanel(s)])),
          Expanded(child: _logBox(s)),
        ]),
      ],
    );
  }

  Widget _statusPanel(ServiceConfig s) {
    final state = widget.runner.stateOf(_item);
    final live = widget.process(_item);
    final started = live?.process.startedAt;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(children: [
          Expanded(child: Text(s.id, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          stateChip(state),
        ]),
        if (_reason != null && !isUp(state)) Text(_reason!, style: TextStyle(fontSize: 13, color: C.bad.$2)),
        KeyValues([
          if (s is ProcessService) ...[
            ('시작 시각', Text(started == null ? '—' : '${started.month}/${started.day} ${_clock(started.toIso8601String())}')),
            ('PID', Text(live == null ? '—' : '${live.process.pid}', style: mono)),
            ('소유권', Text(live == null ? '띄운 프로세스 없음' : '포폴링이 시작함', style: TextStyle(color: live == null ? C.muted : C.ok.$2))),
          ],
          if (s is ComposeService) ('Compose 프로젝트', Text('ppoling-${_item.projectId}', style: mono)),
        ]),
        if (s is RemoteService)
          Btn('다시 확인', onPressed: _busy ? null : () => _act(() => widget.runner.start(_item)))
        else
          Row(spacing: 8, children: [
            Expanded(
              child: isUp(state) || state == ItemState.stopping
                  ? Btn('중지', onPressed: _busy || state == ItemState.stopping ? null : () => _act(() => widget.runner.stop(_item)))
                  : Btn('시작', primary: true, onPressed: _busy ? null : () => _act(() => widget.runner.start(_item))),
            ),
            Expanded(child: Btn('재시작', onPressed: _busy || !isUp(state) ? null : _restart)),
          ]),
      ]),
    );
  }

  Widget _configPanel(ServiceConfig s) {
    const m = TextStyle(fontFamily: 'Menlo', fontSize: 13);
    return Panel(
      title: '실행 설정',
      titleAction: LinkText('편집', size: 13, onTap: () => Navigator.pushNamed(context, '/settings', arguments: _item.projectId)),
      child: KeyValues([
        ('유형', Text(kindOf(s))),
        if (s case ProcessService(:final cwd, :final command, :final env, :final envFile, :final ports, :final stopTimeout)) ...[
          ('작업 폴더', Text(cwd, style: m)),
          ('명령', Text(command.join(' '), style: m)),
          if (env.isNotEmpty) ('환경변수', Text(env.entries.map((e) => '${e.key}=${e.value}').join('\n'), style: m)),
          if (envFile != null)
            ('env 파일', Text.rich(TextSpan(children: [
              TextSpan(text: '$envFile ', style: m),
              const TextSpan(text: '(값은 표시하지 않음)', style: TextStyle(color: C.muted)),
            ]))),
          ('포트', Text(ports.isEmpty ? '—' : ports.join(', '), style: m)),
          ('종료 유예', Text('${stopTimeout.inSeconds}초 후 강제 종료')),
        ],
        if (s case ComposeService(:final file, :final services)) ...[
          ('Compose 파일', Text(file, style: m)),
          if (services.isNotEmpty) ('서비스', Text(services.join(', '), style: m)),
        ],
        ('의존 항목', Text(s.dependsOn.isEmpty ? '—' : s.dependsOn.join(', '))),
        ('준비 조건', Text(s.ready is NoneReady ? readyText(s.ready) : '${readyText(s.ready)} · 최대 ${s.ready.timeout.inSeconds}초')),
      ]),
    );
  }

  Widget _logBox(ServiceConfig s) {
    Widget tab(String label, int i) => TextButton(
          onPressed: () => setState(() => _filter = i),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            backgroundColor: _filter == i ? C.darkLine : null,
            foregroundColor: _filter == i ? Colors.white : const Color(0xFF9AA1AD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(label),
        );
    final visible = _visible;
    final empty = switch (s) {
      RemoteService() => '원격 항목은 포폴링이 띄우지 않아 로그가 없어요.',
      _ when _lines.isEmpty => '아직 로그가 없어요. 항목을 시작하면 여기에 출력이 보여요.',
      _ => '검색 결과가 없어요.',
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.darkLine))),
          child: Wrap(spacing: 4, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            tab('전체', 0),
            if (s is ProcessService) ...[tab('stdout', 1), tab('stderr', 2)],
            const SizedBox(width: 16),
            SizedBox(
              width: 170,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '검색',
                  hintStyle: TextStyle(color: Color(0xFF9AA1AD)),
                  prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF9AA1AD)),
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFF22252C),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ),
            Checkbox(value: _autoScroll, onChanged: (v) => setState(() => _autoScroll = v!)),
            const Text('자동 스크롤', style: TextStyle(fontSize: 13, color: C.logText)),
            TextButton(
              onPressed: visible.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: visible.map((l) => '${l.time} ${l.text}').join('\n')));
                      toast(context, '보이는 로그 ${visible.length}줄을 복사했어요.');
                    },
              style: TextButton.styleFrom(minimumSize: const Size(0, 36), foregroundColor: const Color(0xFF9AA1AD)),
              child: const Text('복사'),
            ),
          ]),
        ),
        SizedBox(
          height: 520,
          child: visible.isEmpty
              ? Center(child: Text(empty, style: const TextStyle(color: Color(0xFF8A909C))))
              : SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText.rich(
                    TextSpan(children: [
                      for (final l in visible) logLine(l.time, l.stream == 'out' ? '' : l.stream, l.text),
                    ]),
                    style: mono.copyWith(fontSize: 12.5, height: 1.8, color: C.logText),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.darkLine))),
          child: Text(
            s is ProcessService
                ? '화면에는 최근 5,000줄까지 보여요. err 는 stderr 로 나온 줄이에요(오류라는 뜻은 아니에요). 전체 로그는 파일로 저장돼요 (10MB × 3개 회전).'
                : '화면에는 최근 5,000줄까지 보여요.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A909C)),
          ),
        ),
      ]),
    );
  }
}

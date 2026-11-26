import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../git/git_adapter.dart';
import '../log/log_store.dart';
import 'health_section.dart';
import 'item_log_view.dart';
import 'item_status.dart';
import 'project_summary.dart';

/// 3. 프로젝트 화면(목업 v2): 머리·알림 줄·실행 흐름·탭. 카탈로그의 [열기]가 `arguments` 로 프로젝트 ID 를 넘긴다.
///
/// 전체 실행·종료(FR-04·05), 항목 시작·중지(FR-03), 포트 주인이 내 다른 항목이면 [그 항목 중지](AT-17).
/// 로그 탭은 내장이고, 다른 탭은 기능들이 [ProjectTab] 으로 등록한 것을 이어 붙인다.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.projectId,
    required this.projects,
    required this.runner,
    required this.ports,
    required this.runtime,
    this.git,
    this.logs,
    this.launcher,
    this.tabs = const [],
    this.panels = const ProjectPanels(),
    this.qa,
  });

  final String projectId;
  final ProjectRepository projects;
  final Orchestrator runner;
  final PortProbe ports;
  final RuntimeQuery runtime;
  final GitAdapter? git;

  /// 로그를 읽는 곳. 없으면 로그를 숨긴다.
  final LogStore? logs;

  /// Compose 로그를 읽는 곳.
  final ItemLauncher? launcher;

  /// 로그 탭 뒤에 붙일 탭(order 순).
  final List<ProjectTab> tabs;

  /// 실패 안내 자리 등 다른 기능이 채우는 자리.
  final ProjectPanels panels;

  /// 로그 탭 아래 헬스체크. 없으면 숨긴다.
  final QaRunner? qa;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Project? _project;
  String? _loadError;
  RunSummary? _summary;
  GitStatus? _git;
  final _reasons = <ItemRef, String?>{};

  /// 포트 사용 중인 항목 → 그 포트를 쓰는 내 다른 항목.
  final _owners = <ItemRef, (int, ItemRef)>{};

  /// 처리 중인 버튼('all' 또는 항목 ID). 두 번 누르지 않게 막는다.
  final _busy = <String>{};
  late final StreamSubscription<List<Project>> _projectSub;
  late final StreamSubscription<RunEvent> _eventSub;

  var _gitLoaded = false;

  /// 사용자가 고른 실행 흐름 카드(로그 탭에 보일 항목). 새로 실패한 항목이 생기면 그것으로 바뀐다.
  String? _picked;

  /// 0 은 로그 탭, 그 뒤는 [DashboardScreen.tabs] 순서.
  var _tab = 0;

  /// 탭 배지. 그릴 때마다 다시 점검하지 않게 한 번만 만든다.
  late final Map<String, Stream<int>> _badges = {
    for (final t in widget.tabs)
      if (t.badge case final badge?) t.id: badge(_id),
  };

  String get _id => widget.projectId;

  /// 지금 아는 상태를 먼저 보여 주고, [fetch] 면 원격을 확인한 뒤 다시 보여 준다.
  Future<void> _loadGit(String folder, {bool fetch = false}) async {
    Future<void> show() async {
      final status = await widget.git?.status(folder);
      if (mounted) setState(() => _git = status);
    }

    await show();
    if (fetch && _git != null && await widget.git!.fetch(folder)) await show();
  }

  @override
  void initState() {
    super.initState();
    _projectSub = widget.projects.watchProjects().listen((all) {
      final p = all.where((p) => p.id == _id).firstOrNull;
      setState(() {
        _project = p;
        _loadError = p == null ? '목록에 없는 프로젝트예요: $_id' : null;
      });
      if (p != null && !_gitLoaded) {
        _gitLoaded = true;
        unawaited(_loadGit(p.folderPath, fetch: true));
      }
    }, onError: (Object e) => setState(() => _loadError = errorText(e)));
    _eventSub = widget.runner.events.listen((e) {
      if (e case ItemStateChanged(:final item, :final state, :final reason) when item.projectId == _id) {
        setState(() {
          _reasons[item] = reason;
          if (state == ItemState.failed) _picked = item.serviceId;
        });
        if (state == ItemState.portBusy) unawaited(_findOwner(item));
        if (state != ItemState.portBusy) _owners.remove(item);
      } else if (e case RunSucceeded(:final summary) when summary.projectId == _id) {
        setState(() => _summary = summary);
      }
    });
    widget.runner.lastRun(_id).then((s) {
      if (mounted && _summary == null) setState(() => _summary = s);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _projectSub.cancel();
    _eventSub.cancel();
    super.dispose();
  }

  List<ServiceConfig> get _services => _project?.config?.services ?? const [];

  /// 먼저 볼 실패한 항목. 지금 실패한 항목이 없으면 마지막 전체 실행에서 실패했고 아직 안 뜬 항목.
  String? _failedOf(List<ServiceConfig> services) {
    final lastFailed = {
      for (final r in _summary?.items ?? const <ItemResult>[])
        if (r.outcome == ItemOutcome.failed) r.item.serviceId,
    };
    bool failed(ServiceConfig s) => widget.runner.stateOf(_ref(s)) == ItemState.failed;
    bool failedLast(ServiceConfig s) => lastFailed.contains(s.id) && !isUp(widget.runner.stateOf(_ref(s)));
    return (services.where(failed).firstOrNull ?? services.where(failedLast).firstOrNull)?.id;
  }

  ItemRef _ref(ServiceConfig s) => ItemRef(projectId: _id, serviceId: s.id);

  /// [key] 버튼을 막아 두고 [action] 을 한다. 예외는 화면 아래에 알린다.
  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() => _busy.add(key));
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _runAll() => _run('all', () async {
        final s = await widget.runner.runAll(_id);
        if (!mounted) return;
        setState(() => _summary = s);
        if (_project case final p?) unawaited(_loadGit(p.folderPath));
      });

  /// 전체 실행이 최신 코드를 기다리는 중에도 누를 수 있게 따로 막는다.
  Future<void> _stopAll() => _run('stopAll', () async {
        final s = await widget.runner.stopAll(_id);
        final failed = s.items.where((r) => r.outcome == ItemOutcome.failed).toList();
        if (mounted && failed.isNotEmpty) toast(context, '${failed.first.item.serviceId}: ${failed.first.reason}');
      });

  Future<void> _start(ServiceConfig s) => _run(s.id, () async {
        final r = await widget.runner.start(_ref(s));
        setState(() => _reasons[r.item] = r.reason);
        if (widget.runner.stateOf(r.item) == ItemState.portBusy) await _findOwner(r.item);
      });

  Future<void> _stop(ServiceConfig s) => _run(s.id, () async {
        final r = await widget.runner.stop(_ref(s));
        setState(() => _reasons[r.item] = r.reason);
      });

  /// 포트를 쓰는 내 다른 항목을 멈춘다(AT-17). 멈추면 바로 이 항목을 시작할 수 있다.
  Future<void> _stopOwner(ItemRef item, ItemRef owner) async {
    if (owner.projectId != _id && !await confirmStopOther(context, project: owner.projectId, service: owner.serviceId)) return;
    return _stopOwnerConfirmed(item, owner);
  }

  Future<void> _stopOwnerConfirmed(ItemRef item, ItemRef owner) => _run(item.serviceId, () async {
        final r = await widget.runner.stop(owner);
        if (r.outcome != ItemOutcome.ok) throw StateError(r.reason ?? '멈추지 못했어요.');
        setState(() {
          _owners.remove(item);
          _reasons.remove(item); // 주인을 멈췄으니 '쓰고 있어요' 문장은 더 맞지 않다
        });
        if (mounted) toast(context, '$owner 항목을 멈췄어요. 이제 ${item.serviceId} 항목을 시작할 수 있어요.');
      });

  /// [item] 의 포트를 쓰는 게 포폴링이 띄운 내 항목인지 찾는다. 외부 프로그램이면 이유 문장만 보여 준다.
  Future<void> _findOwner(ItemRef item) async {
    final s = _services.where((s) => s.id == item.serviceId).firstOrNull;
    if (s is! ProcessService) return;
    for (final port in s.ports) {
      try {
        if (await widget.ports.whoUses(port) case final PortInUse usage) {
          if (await widget.runtime.ownerOf(usage) case final owner?) {
            if (mounted) setState(() => _owners[item] = (port, owner));
            return;
          }
        }
      } catch (_) {} // 포트를 쓰는 프로그램을 알 수 없으면 버튼 없이 이유만 보여 준다
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (p == null) {
      return AppPage(crumbs: [('내 프로젝트', '/home'), (_id, null)], children: [
        if (_loadError != null) Text(_loadError!, style: const TextStyle(color: C.muted)) else const LinearProgressIndicator(),
      ]);
    }
    final allBusy = _busy.contains('all') || _busy.contains('stopAll');
    final waitingPull = _busy.contains('all') &&
        _git != null &&
        (p.config?.git.pullBeforeRun ?? false) &&
        !_services.any((s) => isUp(widget.runner.stateOf(_ref(s))));
    final states = [for (final s in _services) widget.runner.stateOf(_ref(s))];
    final anyUp = states.any(isUp) || states.contains(ItemState.connected);
    final alerts = _alerts(p, waitingPull);
    return AppPage(
      crumbs: [('내 프로젝트', '/home'), (p.name, null)],
      children: [
        _head(p, states, anyUp, allBusy),
        if (alerts.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: alerts),
        if (_services.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            const Text('실행 흐름', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Wrap(spacing: 12, runSpacing: 12, children: [for (final s in _services) _flowCard(s)]),
          ]),
        _tabBar(),
        if (_tab == 0) _logTab() else widget.tabs[_tab - 1].build(context, _id),
      ],
    );
  }

  Widget _head(Project p, List<ItemState> states, bool anyUp, bool allBusy) {
    final summary = projectSummary(states);
    final about = p.config?.about;
    final repo = about?.links['repo'];
    return Wrap(spacing: 20, runSpacing: 16, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(p.name, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            StatusChip(summary.label, summary.tone),
            for (final t in about?.stack ?? const <String>[]) Tag(t),
            if ((_git?.behind ?? 0) > 0) StatusChip('최신 코드가 있어요 · ${_git!.behind}커밋', C.warn, dot: false),
          ]),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (about?.summary case final summary?) Text(summary, style: const TextStyle(fontSize: 14, color: C.text2)),
            if (repo != null) ...[const Text('·', style: TextStyle(color: C.muted)), Text('저장소', style: const TextStyle(fontSize: 14, color: C.primary))],
            if (about?.memo != null) ...[const Text('·', style: TextStyle(color: C.muted)), const Text('메모 1', style: TextStyle(fontSize: 14, color: C.text2))],
          ]),
          Text(_sentence(states), style: const TextStyle(fontSize: 13, color: C.text2)),
          if (_summary case final s? when s.items.isNotEmpty) Text(_counts(s), style: const TextStyle(fontSize: 13, color: C.muted)),
        ]),
      ),
      Wrap(spacing: 8, children: [
        if (!anyUp || allBusy) Btn('전체 실행', primary: true, icon: Icons.play_arrow, onPressed: allBusy || _services.isEmpty ? null : _runAll),
        if (anyUp || allBusy) Btn('전체 종료', icon: Icons.stop, onPressed: _busy.contains('stopAll') || _services.isEmpty ? null : _stopAll),
      ]),
    ]);
  }

  /// 머리 요약 문장. 예: `4개 중 3개 준비 완료 · web 항목을 시작하지 못했어요`
  String _sentence(List<ItemState> states) {
    if (_services.isEmpty) return '실행 항목이 아직 없어요. popoling.yaml 에 실행 방법을 적어 주세요.';
    final n = states.length;
    final k = states.where((s) => s == ItemState.ready || s == ItemState.connected).length;
    final failed = [for (final (i, s) in _services.indexed) if (states[i] == ItemState.failed || states[i] == ItemState.portBusy) s.id];
    if (states.any((s) => isUp(s) || s == ItemState.connected || s == ItemState.failed || s == ItemState.portBusy)) {
      return [
        '$n개 중 $k개 준비 완료',
        if (failed.isNotEmpty) '${failed.join(', ')} 항목을 시작하지 못했어요',
      ].join(' · ');
    }
    if (_summary case final s?) return '마지막 전체 실행 ${_time(s.finishedAt)}';
    return '아직 전체 실행 기록이 없어요.';
  }

  List<Widget> _alerts(Project p, bool waitingPull) => [
        if (p.configIssues.isNotEmpty)
          Notice(
            bg: C.bad.$1,
            border: C.bad.$1,
            icon: Icons.error_outline,
            iconColor: C.bad.$2,
            child: Text('설정 파일에 문제가 있어 실행할 수 없어요: ${p.configIssues.first.message}', style: TextStyle(fontSize: 14, color: C.bad.$2)),
          ),
        if (waitingPull) const Text('전체 실행을 준비하고 있어요. 최신 코드를 확인하느라 1분쯤 걸릴 수 있어요.', style: TextStyle(fontSize: 13, color: C.text2)),
        for (final s in _services) ?_itemNotice(s),
      ];

  /// 항목 하나의 알림: 포트 주인이 내 다른 항목이면 [그 항목 중지], 아니면 실패 이유.
  Widget? _itemNotice(ServiceConfig s) {
    final item = _ref(s);
    final state = widget.runner.stateOf(item);
    final busy = _busy.contains(s.id) || _busy.contains('all') || _busy.contains('stopAll');
    final reason = _reasons[item];
    if (_owners[item] case final owner?) {
      return _notice(C.port, '포트 ${owner.$1} 를 내 프로젝트 ${owner.$2} 항목이 쓰고 있어요.', [
        if (owner.$2.projectId != _id)
          Btn('${owner.$2.projectId} 로 이동', small: true, onPressed: () => Navigator.pushNamed(context, '/dashboard', arguments: owner.$2.projectId)),
        Btn('${owner.$2} 중지', small: true, onPressed: busy ? null : () => _stopOwner(item, owner.$2)),
      ]);
    }
    if (reason != null && !isUp(state)) return _notice(state == ItemState.portBusy ? C.port : C.bad, reason, const []);
    return null;
  }

  Widget _flowCard(ServiceConfig s) {
    final item = _ref(s);
    final state = widget.runner.stateOf(item);
    final busy = _busy.contains(s.id) || _busy.contains('all') || _busy.contains('stopAll');
    final selected = s.id == _selectedService?.id;
    final skipped = !isUp(state) &&
        state != ItemState.failed &&
        (_summary?.items.any((r) => r.item == item && r.outcome == ItemOutcome.skipped) ?? false);
    final kind = s is RemoteService ? '원격 · 연결만 확인' : kindOf(s);
    final port = s is ProcessService && s.ports.isNotEmpty ? ' · ${s.ports.join(', ')}' : '';
    final Widget action = switch (s) {
      RemoteService() => Btn('다시 확인', small: true, onPressed: busy ? null : () => _start(s)),
      _ when state == ItemState.stopping => const IconButton(onPressed: null, tooltip: '중지', icon: Icon(Icons.stop, size: 18)),
      _ when isUp(state) => IconButton(tooltip: '중지', onPressed: busy ? null : () => _stop(s), icon: const Icon(Icons.stop, size: 18)),
      _ => IconButton(tooltip: '시작', onPressed: busy ? null : () => _start(s), icon: const Icon(Icons.play_arrow, size: 18)),
    };
    return SizedBox(
      width: 220,
      child: Material(
        color: C.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? C.primary : C.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          key: ValueKey('flow-${s.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: s is RemoteService ? null : () => setState(() {
            _picked = s.id;
            _tab = 0;
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              Row(children: [
                Expanded(child: Text(s.id, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                action,
              ]),
              Text('$kind$port', style: const TextStyle(fontSize: 12, color: C.muted)),
              skipped ? const StatusChip('건너뜀', C.idle) : stateChip(state),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tabBar() {
    final labels = ['로그', for (final t in widget.tabs) t.label];
    Widget badge(int i) {
      final stream = i == 0 ? null : _badges[widget.tabs[i - 1].id];
      if (stream == null) return const SizedBox.shrink();
      return StreamBuilder<int>(
        stream: stream,
        builder: (_, snap) => (snap.data ?? 0) > 0
            ? Padding(padding: const EdgeInsets.only(left: 6), child: StatusChip('${snap.data}', C.bad, dot: false))
            : const SizedBox.shrink(),
      );
    }

    return Container(
      key: const ValueKey('project-tabs'),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
      child: Wrap(children: [
        for (final (i, label) in labels.indexed)
          InkWell(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i ? C.primary : Colors.transparent, width: 2))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, key: const ValueKey('tab-label'), style: TextStyle(fontSize: 14, fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400, color: _tab == i ? C.primary : C.text2)),
                badge(i),
              ]),
            ),
          ),
      ]),
    );
  }

  /// 로그 탭에 보일 항목: 고른 카드 → 실패한 항목 → 첫 프로세스.
  ServiceConfig? get _selectedService {
    final logged = [for (final s in _services) if (s is! RemoteService) s];
    if (logged.isEmpty) return null;
    ServiceConfig? byId(String? id) => logged.where((s) => s.id == id).firstOrNull;
    return byId(_picked) ?? byId(_failedOf(logged)) ?? logged.whereType<ProcessService>().firstOrNull ?? logged.first;
  }

  Widget _logTab() {
    final s = _selectedService;
    final logs = widget.logs;
    final qa = widget.qa;
    final health = qa == null ? null : HealthSection(projectId: _id, qa: qa, summary: widget.panels.qaSummary);
    if (s == null || logs == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        const Text('로그가 있는 실행 항목이 없어요.', style: TextStyle(color: C.muted)),
        ?health,
      ]);
    }
    final item = _ref(s);
    final result = _summary?.items.where((r) => r.item == item && r.outcome == ItemOutcome.failed).firstOrNull;
    final failure = widget.panels.failure;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      if (failure != null && result != null && _summary != null && !isUp(widget.runner.stateOf(item))) failure(context, result, _summary!),
      ItemLogView(key: ValueKey(item), item: item, service: s, runner: widget.runner, logs: logs, launcher: widget.launcher),
      ?health,
    ]);
  }

  /// `성공 2 · 실패 1 · 건너뜀 1` 처럼 있는 결과만. Git pull 은 항목이 아니라 세지 않는다.
  static String _counts(RunSummary s) => [
        for (final (outcome, label) in const [(ItemOutcome.ok, '성공'), (ItemOutcome.failed, '실패'), (ItemOutcome.skipped, '건너뜀')])
          if (s.items.where((r) => r.outcome == outcome).length case final n when n > 0) '$label $n',
      ].join(' · ');

  static String _time(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Widget _notice((Color, Color) tone, String text, List<Widget> actions) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(8)),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(text, style: TextStyle(fontSize: 13, color: tone.$2)),
          ),
          ...actions,
        ]),
      );
}

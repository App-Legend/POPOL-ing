import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../git/git_adapter.dart';
import '../log/log_store.dart';
import 'item_status.dart';
import 'log_preview.dart';

/// 3. 프로젝트 대시보드. 카탈로그의 [열기]가 `arguments` 로 프로젝트 ID 를 넘긴다.
///
/// 전체 실행·종료(FR-04·05), 항목 시작·중지(FR-03), 포트 주인이 내 다른 항목이면 [그 항목 중지](AT-17).
// 환경 배너(EnvBanner)는 4주차에 여기 더한다.
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
  });

  final String projectId;
  final ProjectRepository projects;
  final Orchestrator runner;
  final PortProbe ports;
  final RuntimeQuery runtime;
  final GitAdapter? git;

  /// 최근 로그를 읽는 곳. 없으면 최근 로그를 숨긴다.
  final LogStore? logs;

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
        setState(() => _reasons[item] = reason);
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

  Future<void> _stopAll() => _run('all', () async {
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
  Future<void> _stopOwner(ItemRef item, ItemRef owner) => _run(item.serviceId, () async {
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
      return AppPage(crumbs: [('개발', '/home'), (_id, null)], children: [
        if (_loadError != null) Text(_loadError!, style: const TextStyle(color: C.muted)) else const LinearProgressIndicator(),
      ]);
    }
    final allBusy = _busy.contains('all');
    final logged = [for (final s in _services) if (s is! RemoteService) s];
    return AppPage(
      crumbs: [('개발', '/home'), (p.name, null)],
      children: [
        Wrap(spacing: 20, runSpacing: 16, alignment: WrapAlignment.spaceBetween, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Text(p.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              Text(p.folderPath, style: mono.copyWith(fontSize: 13, color: C.muted)),
              if (_git case final git?) _gitLine(git),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('전체 실행', primary: true, icon: Icons.play_arrow, onPressed: allBusy || _services.isEmpty ? null : _runAll),
            Btn('전체 종료', icon: Icons.stop, onPressed: allBusy || _services.isEmpty ? null : _stopAll),
            Btn('헬스체크', onPressed: () => Navigator.pushNamed(context, '/qa', arguments: _id)),
            Btn('AI 검사', onPressed: () => Navigator.pushNamed(context, '/ai', arguments: _id)),
            Btn('설정', icon: Icons.settings_outlined, onPressed: () => Navigator.pushNamed(context, '/settings', arguments: _id)),
          ]),
        ]),
        if (p.configIssues.isNotEmpty)
          Notice(
            bg: C.bad.$1,
            border: C.bad.$1,
            icon: Icons.error_outline,
            iconColor: C.bad.$2,
            trailing: [LinkText('설정 고치기', onTap: () => Navigator.pushNamed(context, '/settings', arguments: _id))],
            child: Text('설정 파일에 문제가 있어 실행할 수 없어요: ${p.configIssues.first.message}',
                style: TextStyle(fontSize: 14, color: C.bad.$2)),
          ),
        Panel(
          title: '실행 항목',
          titleAction: _services.isEmpty ? null : Text('실행 순서는 의존 항목 먼저', style: const TextStyle(fontSize: 13, color: C.muted)),
          padding: const EdgeInsets.only(top: 16),
          child: _services.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Text('아직 실행 항목이 없어요. [설정] 에서 실행 방법을 추가해 주세요.', style: TextStyle(color: C.muted)),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _row(const [Text('항목'), Text('포트'), Text('준비 조건'), Text('상태'), SizedBox()], head: true),
                  for (final s in _services) _itemRow(s),
                ]),
        ),
        Panel(
          title: '마지막 전체 실행',
          titleAction: _summary == null ? null : Text(_time(_summary!.finishedAt), style: const TextStyle(fontSize: 13, color: C.muted)),
          child: _summary == null
              ? const Text('아직 전체 실행 기록이 없어요.', style: TextStyle(color: C.muted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                  if (_summary!.items.isNotEmpty) Text(_counts(_summary!), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (_summary!.pull case final pull?) _resultRow(pull.outcome, 'Git pull — ${pull.message}'),
                  for (final r in _summary!.items)
                    _resultRow(r.outcome, '${r.item.serviceId}${r.reason == null ? '' : ' — ${r.reason}'}'),
                ]),
        ),
        if (widget.logs case final logs? when logged.isNotEmpty)
          LogPreview(projectId: _id, services: logged, failed: _failedOf(logged), logs: logs),
      ],
    );
  }

  /// `성공 2 · 실패 1` 처럼 있는 결과만. Git pull 은 항목이 아니라 세지 않는다.
  static String _counts(RunSummary s) => [
        for (final (outcome, label) in const [(ItemOutcome.ok, '성공'), (ItemOutcome.failed, '실패'), (ItemOutcome.skipped, '건너뜀')])
          if (s.items.where((r) => r.outcome == outcome).length case final n when n > 0) '$label $n',
      ].join(' · ');

  static Widget _resultRow(ItemOutcome outcome, String text) => Row(spacing: 8, children: [
        SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: outcomeChip(outcome))),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ]);

  static Widget _gitLine(GitStatus git) => Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            const Icon(Icons.call_split, size: 14, color: C.text2, semanticLabel: 'Git 브랜치'),
            const Text('브랜치', style: TextStyle(fontSize: 13, color: C.text2)),
            Flexible(child: Text(git.branch ?? '없음', overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
          if (git.changed > 0) Text('커밋하지 않은 변경 ${git.changed}개', style: const TextStyle(fontSize: 13, color: C.text2)),
          if (git.behind > 0) Text('원격보다 ${git.behind}커밋 뒤처짐', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.warn.$2)),
        ],
      );

  Widget _itemRow(ServiceConfig s) {
    final item = _ref(s);
    final state = widget.runner.stateOf(item);
    final busy = _busy.contains(s.id) || _busy.contains('all');
    final reason = _reasons[item];
    final owner = _owners[item];
    final Widget action = switch (s) {
      RemoteService() => Btn('다시 확인', small: true, onPressed: busy ? null : () => _start(s)),
      _ when state == ItemState.stopping => const Btn('중지', small: true, onPressed: null),
      _ when isUp(state) => Btn('중지', small: true, onPressed: busy ? null : () => _stop(s)),
      _ => Btn('시작', small: true, onPressed: busy ? null : () => _start(s)),
    };
    return _row(
      [
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            InkWell(
              onTap: () => Navigator.pushNamed(context, '/detail', arguments: item),
              child: Text(s.id, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.primary)),
            ),
            Tag(kindOf(s), tone: s is RemoteService ? C.remote : null),
            if (s.dependsOn.isNotEmpty) Text('의존: ${s.dependsOn.join(', ')}', style: const TextStyle(fontSize: 12, color: C.muted)),
          ]),
          Text(_summaryOf(s), style: mono.copyWith(fontSize: 12, color: C.muted), overflow: TextOverflow.ellipsis),
        ]),
        Text(s is ProcessService && s.ports.isNotEmpty ? s.ports.join(', ') : '—', style: mono.copyWith(fontSize: 13)),
        Text(readyText(s.ready)),
        stateChip(state),
        action,
      ],
      extra: owner != null
          ? _notice(
              C.port,
              '포트 ${owner.$1} 를 내 프로젝트 ${owner.$2} 항목이 쓰고 있어요.',
              [
                if (owner.$2.projectId != _id)
                  Btn('${owner.$2.projectId} 로 이동', small: true,
                      onPressed: () => Navigator.pushNamed(context, '/dashboard', arguments: owner.$2.projectId)),
                Btn('${owner.$2} 중지', small: true, onPressed: busy ? null : () => _stopOwner(item, owner.$2)),
              ],
            )
          : reason != null && !isUp(state)
              ? _notice(state == ItemState.portBusy ? C.port : C.bad, reason, const [])
              : null,
    );
  }

  static String _summaryOf(ServiceConfig s) => switch (s) {
        ProcessService(:final cwd, :final command) => '$cwd · ${command.join(' ')}',
        ComposeService(:final file, :final services) => '$file${services.isEmpty ? '' : ' · ${services.join(', ')}'}',
        RemoteService(:final ready) => readyText(ready),
      };

  static String _time(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Widget _notice((Color, Color) tone, String text, List<Widget> actions) => Container(
        margin: const EdgeInsets.only(top: 10),
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

  static Widget _row(List<Widget> cells, {bool head = false, Widget? extra}) {
    const widths = [null, 90.0, null, 150.0, 96.0]; // null 칸(항목·준비 조건)이 남은 너비를 나눠 쓴다
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: head ? 8 : 16),
      decoration: BoxDecoration(color: head ? C.headBg : null, border: const Border(top: BorderSide(color: C.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DefaultTextStyle.merge(
          style: head ? const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500) : const TextStyle(fontSize: 13, color: C.text2),
          child: Row(spacing: 16, children: [
            for (final (i, c) in cells.indexed)
              widths[i] == null ? Expanded(child: c) : SizedBox(width: widths[i], child: Align(alignment: Alignment.centerLeft, child: c)),
          ]),
        ),
        ?extra,
      ]),
    );
  }
}

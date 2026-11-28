import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'catalog_view.dart';
import 'field/field_panel.dart';
import 'run_info.dart';

/// 2. 개발 홈 — 프로젝트 카탈로그(FR-14). 등록한 프로젝트를 카드로 보여 주고 검색·필터·정렬한다.
///
/// 다른 화면으로는 경로 이름으로만 넘어간다: [열기]·[원인 보기] `/dashboard`(`arguments` 로 프로젝트 ID),
/// [프로젝트 추가] `/add-project`. 목업 v2 개발 홈.
/// 카드의 [전체 실행]·[전체 종료]는 [runner] 에 맡기고, 실패하면 카드에 한 줄로 남긴다.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.projects, required this.runs, required this.runner, this.clock});

  final ProjectRepository projects;
  final RunInfoSource runs;
  final Orchestrator runner;

  /// 지금 시각. 테스트에서 고정한다.
  final DateTime Function()? clock;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<Project>? _projects;
  Map<String, RunInfo> _runs = const {};
  Object? _error;
  late final StreamSubscription<List<Project>> _projectSub;
  late final StreamSubscription<Map<String, RunInfo>> _runSub;

  var _query = '';
  var _filter = CatalogFilter.all;
  var _sort = CatalogSort.recent;

  /// 전체 실행·종료를 기다리는 프로젝트 ID → 종료 중인지.
  final Map<String, bool> _busy = {};

  /// 마지막 전체 실행·종료에서 생긴 문제(프로젝트 ID → 한 줄). 그 카드에서 다시 누르면 지운다.
  final Map<String, String> _problems = {};

  /// 요청 자체가 예외로 끝난 프로젝트. 원인 볼 실행 결과가 없으니 다시 실행할 수 있게 둔다.
  final Set<String> _requestFailed = {};

  @override
  void initState() {
    super.initState();
    _projectSub = widget.projects.watchProjects().listen(
      (projects) => setState(() {
        _projects = projects;
        _error = null;
        // 고른 태그가 목록에서 사라졌으면 빈 화면에 갇히지 않게 전체로 돌아간다.
        if (_filter.isTag && !stackTags(projects).map(CatalogFilter.tag).contains(_filter)) {
          _filter = CatalogFilter.all;
        }
      }),
      onError: (Object e) => setState(() => _error = e),
    );
    // 실행 정보를 못 받으면 이전 값(처음엔 "실행 기록 없음")을 그대로 둔다.
    _runSub = widget.runs.watchRunInfo().listen((runs) => setState(() => _runs = runs), onError: (Object _) {});
  }

  @override
  void dispose() {
    _projectSub.cancel();
    _runSub.cancel();
    super.dispose();
  }

  void _open(String route, [Object? arguments]) => Navigator.pushNamed(context, route, arguments: arguments);

  void _addProject() => _open('/add-project');

  /// 전체 실행([stop] 이 false) 또는 전체 종료. 카드 상태는 실행 정보 스트림으로 따로 바뀐다.
  Future<void> _runAll(Project p, {required bool stop}) async {
    setState(() {
      _busy[p.id] = stop;
      _problems.remove(p.id);
      _requestFailed.remove(p.id);
    });
    String? problem;
    try {
      final summary = stop ? await widget.runner.stopAll(p.id) : await widget.runner.runAll(p.id);
      problem = runProblemText(summary, stopping: stop);
    } catch (e) {
      final what = stop ? '멈추지' : '실행하지';
      problem = e is PopolingException ? '$what 못했어요. ${e.message}' : '$what 못했어요.';
      _requestFailed.add(p.id);
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(p.id);
      if (problem != null) _problems[p.id] = problem;
    });
    if (problem == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('${p.name}: ${stop ? '모두 멈췄어요.' : '모두 실행됐어요.'}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final now = (widget.clock ?? DateTime.now)();
    return AppPage(
      crumbs: const [('내 프로젝트', null)],
      side: projects == null || projects.isEmpty ? null : _field(projects, now),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              Text(projects == null ? '내 프로젝트' : '내 프로젝트  ${projects.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const Text("오래 실행하지 않은 프로젝트는 '오래됨'으로 표시돼요.", style: TextStyle(fontSize: 13.5, color: C.text2)),
            ]),
          ),
          if (projects != null && projects.isNotEmpty) Btn('프로젝트 추가', primary: true, icon: Icons.add, onPressed: _addProject),
        ]),
        if (_error != null)
          _errorNotice(_error!)
        else if (projects == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
        else if (projects.isEmpty)
          _noProjects()
        else
          ..._catalog(projects, now),
      ],
    );
  }

  /// 오른쪽 운동장: 레인 4개(실행 중·실패·중지·실행 방법 없음 순)와 벤치(오래된 프로젝트 하나).
  Widget _field(List<Project> projects, DateTime now) {
    final entries = [for (final p in projects) CatalogEntry(p, _runs[p.id] ?? RunInfo.none)];
    final stale = entries.where((e) => e.isStale(now)).toList();
    FieldRunner runner(CatalogEntry e) {
      final p = e.project;
      if (e.serviceCount == 0 && (p.config?.services.isEmpty ?? true)) return FieldRunner(name: p.name, status: '실행 방법 없음', pose: FieldPose.empty);
      if (e.isRunning) return FieldRunner(name: p.name, status: '준비 완료 · ${e.run.running}/${e.serviceCount}', pose: FieldPose.run);
      if (e.run.lastSucceeded == false) return FieldRunner(name: p.name, status: '실패 · 원인 보기', pose: FieldPose.fallen);
      return FieldRunner(name: p.name, status: '중지 · 출발선 대기', pose: FieldPose.wait);
    }

    final lanes = [for (final e in entries) if (!e.isStale(now)) runner(e)]
      ..sort((a, b) => a.pose.index.compareTo(b.pose.index));
    return FieldPanel(
      lanes: lanes,
      bench: stale.isEmpty ? null : (stale.first.project.name, cardStateLabel(stale.first, now)),
    );
  }

  List<Widget> _catalog(List<Project> projects, DateTime now) {
    final entries = [for (final p in projects) CatalogEntry(p, _runs[p.id] ?? RunInfo.none)];
    final visible = visibleEntries(entries, query: _query, filter: _filter, sort: _sort, now: now);
    final filters = [CatalogFilter.all, CatalogFilter.running, CatalogFilter.stale, ...stackTags(projects).map(CatalogFilter.tag)];
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 230,
              height: 38,
              child: TextField(
                key: const Key('catalog-search'),
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: '이름·설명·기술로 찾기',
                  hintStyle: TextStyle(fontSize: 13.5, color: C.muted),
                  prefixIcon: Icon(Icons.search, size: 16, color: C.muted),
                  isDense: true,
                  filled: true,
                  fillColor: C.surface,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong), borderRadius: BorderRadius.all(Radius.circular(8))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: C.primary), borderRadius: BorderRadius.all(Radius.circular(8))),
                ),
              ),
            ),
            for (final f in filters) _filterChip(f),
          ]),
        ),
        Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          const Text('정렬', style: TextStyle(fontSize: 13, color: C.muted)),
          Container(
            height: 38,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.borderStrong), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CatalogSort>(
                key: const Key('catalog-sort'),
                value: _sort,
                style: const TextStyle(fontFamily: bodyFont, fontSize: 13.5, color: C.text),
                icon: const Icon(Icons.expand_more, size: 18),
                items: [for (final s in CatalogSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (v) => setState(() => _sort = v!),
              ),
            ),
          ),
        ]),
      ]),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.', style: TextStyle(fontSize: 14, color: C.muted))),
        )
      else
        AutoGrid(minItemWidth: 240, gap: 12, children: [for (final e in visible) _card(e, now)]),
    ];
  }

  /// 목업 v2 필터 칩: 고르면 연한 파랑.
  Widget _filterChip(CatalogFilter f) {
    final on = _filter == f;
    return ChoiceChip(
      label: Text(f.label),
      selected: on,
      showCheckmark: false,
      backgroundColor: C.surface,
      selectedColor: const Color(0xFFECF1FF),
      labelStyle: TextStyle(fontFamily: bodyFont, color: on ? const Color(0xFF1F44C4) : C.text, fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      shape: StadiumBorder(side: BorderSide(color: on ? const Color(0xFFD9E2FF) : C.border)),
      onSelected: (_) => setState(() => _filter = f),
    );
  }

  Widget _noProjects() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(spacing: 14, children: [
          const Mascot(MascotPose.empty, size: 96),
          const Text('첫 프로젝트를 등록해 주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Text('프로젝트 폴더를 고르면 실행 방법(popoling.yaml)을 찾아 불러와요. 없으면 실행 방법을 함께 적어요.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: C.text2)),
          Btn('프로젝트 폴더 고르기', primary: true, icon: Icons.add, onPressed: _addProject),
          const Text('명령은 처음 실행할 때 목록을 보여주고 확인받은 뒤에만 실행해요.', style: TextStyle(fontSize: 13, color: C.muted)),
        ]),
      );

  Widget _errorNotice(Object error) => Notice(
        bg: C.bad.$1,
        border: C.bad.$2.withValues(alpha: 0.3),
        icon: Icons.error_outline,
        iconColor: C.bad.$2,
        child: Text(error is PopolingException ? '프로젝트 목록을 읽지 못했어요. ${error.message}' : '프로젝트 목록을 읽지 못했어요.'),
      );

  /// 목록에서 빼기(FR-01). 폴더·설정 파일·실행 기록은 지우지 않는다.
  Future<void> _remove(Project p) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => Dialog(
            child: DialogBody('${p.name}을 목록에서 뺄까요?', [
              const Text('포폴링 목록에서만 빠져요. 프로젝트 폴더와 popoling.yaml, 실행 기록 파일은 지우지 않아요.',
                  style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.headBg, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
                child: Text('${p.folderPath}  · 폴더는 그대로 남아요', style: mono.copyWith(fontSize: 12.5, color: C.text2)),
              ),
              const Text('다시 넣고 싶으면 [프로젝트 추가]에서 같은 폴더를 고르면 돼요.', style: TextStyle(fontSize: 13, color: C.muted)),
              Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
                OutlinedButton(autofocus: true, onPressed: () => closeDialog(c, false), child: const Text('취소')),
                FilledButton(onPressed: () => closeDialog(c, true), child: const Text('목록에서 빼기')),
              ]),
            ]),
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.projects.removeProject(p.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e is PopolingException ? e.message : '목록에서 빼지 못했어요.')));
    }
  }

  Widget _card(CatalogEntry e, DateTime now) {
    final p = e.project;
    final label = cardStateLabel(e, now);
    final hasServices = p.config?.services.isNotEmpty ?? false;
    final succeeded = e.run.lastSucceeded;
    final chip = !hasServices
        ? const StatusChip('실행 방법 없음', C.idle)
        : switch (cardStateOf(e, now)) {
            CardState.running => StatusChip(label, C.ok),
            CardState.stale => Tooltip(message: '90일 넘게 실행하지 않았어요.', child: StatusChip(label, (const Color(0xFFF4EDE9), const Color(0xFF7A4A3A)))),
            CardState.stopped => succeeded == false ? const StatusChip('실패', C.bad) : StatusChip(label, C.idle),
            CardState.never => StatusChip(label, C.idle),
          };
    final last = lastRunText(e.run, now);
    final problem = _problems[p.id];
    const small = TextStyle(fontSize: 13.5, color: C.text2);

    return Container(
      key: ValueKey('catalog-card-${p.id}'),
      padding: EdgeInsets.all(e.isRunning ? 15.5 : 16),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border.all(color: e.isRunning ? C.primary : C.border, width: e.isRunning ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Row(spacing: 10, children: [
          Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          chip,
          SizedBox(
            width: 26,
            height: 26,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: '목록에서 빼기',
              onPressed: () => _remove(p),
              icon: const Icon(Icons.close, size: 15, color: C.muted),
            ),
          ),
        ]),
        Text(p.about.summary ?? '설명이 아직 없어요. README에서 가져오거나 직접 적어 주세요.', style: small),
        if (problem != null) Text(problem, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.bad.$2)),
        if (p.about.stack.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.about.stack) Tag(s)]),
        if (!hasServices)
          const Text('실행 항목이 아직 없어요', style: small)
        else if (last != null)
          Text.rich(TextSpan(style: small, children: [
            TextSpan(text: succeeded == null ? last : '$last · '),
            if (succeeded != null) TextSpan(text: succeeded ? '성공' : '실패', style: TextStyle(color: succeeded ? C.ok.$2 : C.bad.$2)),
          ])),
        const Spacer(),
        const SizedBox(height: 4),
        Row(spacing: 8, children: [
          Expanded(child: Btn('열기', primary: e.isRunning, onPressed: () => _open('/dashboard', p.id))),
          if (hasServices)
            Expanded(
              child: !e.isRunning && _busy[p.id] == null && !_requestFailed.contains(p.id) && (problem != null || succeeded == false)
                  ? Btn('원인 보기', onPressed: () => _open('/dashboard', p.id))
                  : _runButton(p, running: e.isRunning),
            ),
        ]),
      ]),
    );
  }

  /// 떠 있으면 [전체 종료], 아니면 [전체 실행]. 기다리는 동안은 눌리지 않는다.
  Widget _runButton(Project p, {required bool running}) => switch (_busy[p.id]) {
        true => const Btn('멈추는 중…', onPressed: null),
        false => const Btn('시작하는 중…', onPressed: null),
        null when running => Btn('전체 종료', onPressed: () => _runAll(p, stop: true)),
        null => Btn('전체 실행', onPressed: () => _runAll(p, stop: false)),
      };
}

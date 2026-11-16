import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/ui.dart';

import 'catalog_view.dart';
import 'run_info.dart';

/// 2. 개발 홈 — 프로젝트 카탈로그(FR-14). 등록한 프로젝트를 카드로 보여 주고 검색·필터·정렬한다.
///
/// 다른 화면으로는 경로 이름으로만 넘어간다: [열기] `/dashboard`, [실행 방법 설정하기] `/settings`
/// (둘 다 `arguments` 로 프로젝트 ID), [프로젝트 추가] `/add-project`.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.projects, required this.runs, this.clock});

  final ProjectRepository projects;
  final RunInfoSource runs;

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

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return AppPage(
      crumbs: const [('개발', null)],
      children: [
        PageHead(
          title: projects == null ? '내 프로젝트' : '내 프로젝트  ${projects.length}',
          sub: "오래 실행하지 않은 프로젝트는 '오래됨'으로 표시돼요.",
          actions: [Btn('프로젝트 추가', primary: true, icon: Icons.add, onPressed: _addProject)],
        ),
        if (_error != null)
          _errorNotice(_error!)
        else if (projects == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
        else if (projects.isEmpty)
          _noProjects()
        else
          ..._catalog(projects),
      ],
    );
  }

  List<Widget> _catalog(List<Project> projects) {
    final now = (widget.clock ?? DateTime.now)();
    final entries = [for (final p in projects) CatalogEntry(p, _runs[p.id] ?? RunInfo.none)];
    final visible = visibleEntries(entries, query: _query, filter: _filter, sort: _sort, now: now);
    final filters = [CatalogFilter.all, CatalogFilter.running, CatalogFilter.stale, ...stackTags(projects).map(CatalogFilter.tag)];
    return [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 320,
          child: TextField(
            key: const Key('catalog-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: '이름, 설명, 기술 스택으로 검색',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: C.surface,
              border: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
            ),
          ),
        ),
        for (final f in filters)
          ChoiceChip(
            label: Text(f.label),
            selected: _filter == f,
            showCheckmark: false,
            selectedColor: C.dark,
            labelStyle: TextStyle(color: _filter == f ? Colors.white : C.text2, fontSize: 13),
            shape: const StadiumBorder(side: BorderSide(color: C.borderStrong)),
            onSelected: (_) => setState(() => _filter = f),
          ),
        Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          const Text('정렬', style: TextStyle(fontSize: 13, color: C.muted)),
          DropdownButton<CatalogSort>(
            key: const Key('catalog-sort'),
            value: _sort,
            items: [for (final s in CatalogSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _sort = v!),
          ),
        ]),
      ]),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('조건에 맞는 프로젝트가 없어요. 검색어나 필터를 바꿔 보세요.', style: TextStyle(fontSize: 14, color: C.muted))),
        )
      else
        AutoGrid(minItemWidth: 340, children: [for (final e in visible) _card(e, now)]),
    ];
  }

  Widget _noProjects() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(spacing: 16, children: [
          const Text('아직 등록한 프로젝트가 없어요. 프로젝트 폴더를 추가하면 여기에 모여요.', style: TextStyle(fontSize: 14, color: C.muted)),
          Btn('프로젝트 추가', icon: Icons.add, onPressed: _addProject),
        ]),
      );

  Widget _errorNotice(Object error) => Notice(
        bg: C.bad.$1,
        border: C.bad.$2.withValues(alpha: 0.3),
        icon: Icons.error_outline,
        iconColor: C.bad.$2,
        child: Text(error is PpolingException ? '프로젝트 목록을 읽지 못했어요. ${error.message}' : '프로젝트 목록을 읽지 못했어요.'),
      );

  Widget _card(CatalogEntry e, DateTime now) {
    final p = e.project;
    final label = cardStateLabel(e, now);
    final chip = switch (cardStateOf(e, now)) {
      CardState.running => StatusChip(label, C.ok),
      CardState.stale => Tooltip(message: '90일 넘게 실행하지 않았어요.', child: StatusChip(label, C.warn, dot: false)),
      CardState.stopped => StatusChip(label, C.idle),
      CardState.never => StatusChip(label, C.idle, dot: false),
    };
    final hasServices = p.config?.services.isNotEmpty ?? false;
    final last = lastRunText(e.run, now);
    final succeeded = e.run.lastSucceeded;
    const small = TextStyle(fontSize: 13, color: C.muted);

    return Container(
      key: ValueKey('catalog-card-${p.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border.all(color: e.isRunning ? C.primary : C.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(p.about.summary ?? '설명이 없어요. README에서 가져오거나 직접 적어 주세요.', style: const TextStyle(fontSize: 14, color: C.muted)),
            ]),
          ),
          Flexible(child: chip),
        ]),
        if (p.about.stack.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.about.stack) Tag(s)]),
        if (!hasServices)
          const Text('실행 항목이 아직 없어요.', style: small)
        else if (last != null)
          Text.rich(TextSpan(style: small, children: [
            TextSpan(text: succeeded == null ? last : '$last · '),
            if (succeeded != null) TextSpan(text: succeeded ? '성공' : '실패', style: TextStyle(color: succeeded ? C.ok.$2 : C.bad.$2)),
          ])),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: hasServices
                ? Btn('열기', primary: e.isRunning, onPressed: () => _open('/dashboard', p.id))
                : Btn('실행 방법 설정하기', onPressed: () => _open('/settings', p.id)),
          ),
        ]),
      ]),
    );
  }
}

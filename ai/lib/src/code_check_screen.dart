import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_request.dart';
import 'api_key_dialog.dart';
import 'api_key_status.dart';
import 'api_key_store.dart';
import 'code_check.dart';

/// 8. AI 검사 = 프로젝트별 코드 점검(AI-04, 목업 v2 7-1~7-5, #108).
///
/// 왼쪽 프로젝트 목록에서 고르면, 기준 4개마다 `좋음`·`주의`·`위험`과 이유·고칠 방법·"앱이 확인" 줄·근거를 보여 준다.
/// 점수는 쓰지 않는다. 결과는 [store] 에 프로젝트마다 마지막 하나만 둔다.
class CodeCheckScreen extends StatefulWidget {
  const CodeCheckScreen({
    super.key,
    required this.projects,
    required this.keys,
    required this.client,
    required this.store,
    this.source,
    this.checkKey,
    this.clock,
  });

  final ProjectRepository projects;
  final ApiKeyStore keys;
  final LlmClient client;
  final CodeCheckStore store;

  /// 보낼 파일·"앱이 확인" 줄. C 의 규칙 검사(#107)가 붙기 전에는 null 이고, 그동안은 검사를 시작할 수 없다.
  final CodeCheckSource? source;
  final ApiKeyCheck? checkKey;

  /// 지금 시각. 테스트에서 고정한다.
  final DateTime Function()? clock;

  @override
  State<CodeCheckScreen> createState() => _CodeCheckScreenState();
}

enum _Filter {
  all('전체'),
  checked('검사함'),
  unchecked('검사 전');

  const _Filter(this.label);

  final String label;
}

const _notSent = '.env처럼 비밀값만 담은 파일, API 키, node_modules·build 폴더, 고르지 않은 나머지 파일';
const _sendNote = '보낼 파일은 앱이 규칙으로 최대 5개까지 골라요. 비밀값처럼 보이는 줄은 ●●●로 바꿔 보내요.';
const _working = '보통 20초 안에 끝나요. 그동안 다른 일을 해도 돼요.';
const _caution = '점수는 매기지 않아요. AI 결과는 틀릴 수 있어요. 근거를 확인한 뒤 판단해 주세요.';

class _CodeCheckScreenState extends State<CodeCheckScreen> {
  List<Project>? _projects;
  Map<String, CodeCheckResult> _results = const {};
  var _filter = _Filter.all;
  String? _selected;
  late final StreamSubscription<List<Project>> _sub;

  /// 고른 프로젝트의 "앱이 확인" 줄.
  Future<Map<CheckCriterion, List<String>>>? _findings;

  /// 마지막으로 보낸 글. 답을 읽을 때 보낸 파일 목록을 같이 남긴다.
  PreparedCheck? _sent;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _sub = widget.projects.watchProjects().listen((p) => setState(() {
          _projects = p;
          if (_selected == null || !p.any((x) => x.id == _selected)) _select(p.isEmpty ? null : p.first.id);
        }));
    widget.store.load().then((r) {
      if (mounted) setState(() => _results = r);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _select(String? id) {
    _selected = id;
    _findings = id == null ? null : widget.source?.appFindings(id).catchError((Object _) => <CheckCriterion, List<String>>{});
  }

  Future<String> _content(String projectId) async {
    final source = widget.source!;
    final prepared = prepareCodeCheck(
      await source.filesToSend(projectId),
      await (_findings ?? Future.value(const <CheckCriterion, List<String>>{})),
      secrets: [?await widget.keys.read()],
    );
    _sent = prepared;
    // 확인 창 미리보기 맨 위에 보낼 파일과 가린 곳을 보여 준다(기획서 §9 "AI 검사 보내기 확인").
    return [
      '[보낼 파일 ${prepared.files.length}개] ${prepared.files.join(', ')}',
      '[가린 비밀값 ${prepared.hiddenAt.length}곳] ${prepared.hiddenAt.isEmpty ? '없음' : prepared.hiddenAt.join(', ')}',
      prepared.prompt,
    ].join('\n');
  }

  Future<void> _saved(CodeCheckResult result) async {
    setState(() => _results = {..._results, result.projectId: result});
    await widget.store.save(result);
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return AppPage(
      crumbs: const [('AI 검사', null)],
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              Text('AI 검사', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              Text('프로젝트를 기준 4개로 살펴보고 좋음·주의·위험으로 알려 줘요.', style: TextStyle(fontSize: 14, color: C.text2)),
            ]),
          ),
          Flexible(child: Align(alignment: Alignment.topRight, child: ApiKeyStatus(keys: widget.keys, client: widget.client, checkKey: widget.checkKey))),
        ]),
        if (projects == null)
          const Center(child: CircularProgressIndicator())
        else if (projects.isEmpty)
          const Text('등록한 프로젝트가 없어요. 내 프로젝트에서 먼저 추가해 주세요.', style: TextStyle(fontSize: 14, color: C.muted))
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
            SizedBox(width: 280, child: _list(projects)),
            Expanded(child: _detail(projects.firstWhere((p) => p.id == _selected, orElse: () => projects.first))),
          ]),
      ],
    );
  }

  Widget _list(List<Project> projects) {
    final shown = [
      for (final p in projects)
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.checked => _results.containsKey(p.id),
          _Filter.unchecked => !_results.containsKey(p.id),
        })
          p,
    ];
    return Panel(
      title: '프로젝트',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Wrap(spacing: 6, children: [
          for (final f in _Filter.values) ChoiceChip(label: Text(f.label), selected: _filter == f, showCheckmark: false, onSelected: (_) => setState(() => _filter = f)),
        ]),
        if (shown.isEmpty) const Text('조건에 맞는 프로젝트가 없어요.', style: TextStyle(fontSize: 13, color: C.muted)),
        for (final p in shown) _row(p),
      ]),
    );
  }

  Widget _row(Project p) {
    final r = _results[p.id];
    final on = p.id == _selected;
    return Material(
      color: on ? const Color(0xFFECF1FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey('check-row-${p.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _select(p.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(r == null ? '검사 기록 없음 · 검사 전' : '${_when(r.at)} · ${r.countsLabel}', style: const TextStyle(fontSize: 12, color: C.text2)),
            if (r != null) Text(r.mostUrgent, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _detail(Project p) {
    final r = _results[p.id];
    const muted = TextStyle(fontSize: 13, color: C.muted, height: 1.6);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      if (r != null) ...[
        Text(r.mostUrgent, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text(r.countsLabel, style: const TextStyle(fontSize: 13, color: C.text2)),
      ] else
        const Text('검사 기록 없음 · 검사 전', style: TextStyle(fontSize: 14, color: C.text2)),
      FutureBuilder<Map<CheckCriterion, List<String>>>(
        future: _findings,
        builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          for (final c in CheckCriterion.values)
            _criterion(c, r?.results.firstWhere((x) => x.criterion == c), snap.data?[c] ?? const []),
        ]),
      ),
      if (r != null) ...[
        Text('보낸 것: 고른 파일 ${r.files.length}개 · 가린 비밀값 ${r.hiddenSecrets}개 · ${r.model} · ${_when(r.at)}', style: mono.copyWith(fontSize: 12, color: C.text2)),
        const Text(_caution, style: muted),
      ],
      if (widget.source == null)
        Notice(
          bg: C.headBg,
          border: C.border,
          icon: Icons.hourglass_empty,
          iconColor: C.muted,
          child: const Text('보낼 파일을 고르는 규칙 검사가 아직 준비 중이라 AI 검사를 시작할 수 없어요. 준비되면 이 자리에 [AI 검사 시작]이 생겨요.', style: TextStyle(fontSize: 14, height: 1.6)),
        )
      else
        AiRequestView<CodeCheckResult>(
          key: ValueKey('check-${p.id}'),
          client: widget.client,
          keys: widget.keys,
          requestName: 'AI 코드 점검',
          content: () => _content(p.id),
          parse: (reply) => parseCodeCheck(reply, projectId: p.id, at: _now(), model: widget.client.modelName, sent: _sent!),
          done: (context, result, again) => Align(alignment: Alignment.centerRight, child: Btn('다시 검사', onPressed: again)),
          startLabel: r == null ? 'AI 검사 시작' : '다시 검사',
          againLabel: '다시 검사',
          system: codeCheckSystem,
          notes: const [_sendNote],
          notSent: _notSent,
          workingText: _working,
          cancelLabel: '검사 취소',
          checkKey: widget.checkKey,
          onDone: _saved,
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Btn('프로젝트 열기', onPressed: () => Navigator.pushNamed(context, '/dashboard', arguments: p.id)),
      ),
    ]);
  }

  /// 기준 하나: 상태(글자로)·이유·고칠 방법·"앱이 확인" 줄·근거.
  Widget _criterion(CheckCriterion c, CriterionResult? r, List<String> findings) {
    const small = TextStyle(fontSize: 13, color: C.text2, height: 1.5);
    final (label, tone) = switch (r?.level) {
      null => ('검사 전', C.idle),
      CheckLevel.danger => ('위험', C.bad),
      CheckLevel.caution => ('주의', C.warn),
      CheckLevel.good => ('좋음', C.ok),
    };
    return Container(
      key: ValueKey('criterion-${c.name}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Row(spacing: 10, children: [
          Expanded(child: Text(c.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          StatusChip(label, tone),
        ]),
        if (r != null) Text(r.reason, style: const TextStyle(fontSize: 14, height: 1.5)),
        if (r?.fix case final fix?) Text('고칠 방법 · $fix', style: small),
        Text(findings.isEmpty ? '앱이 확인 · 아직 규칙 검사 결과가 없어요' : '앱이 확인 · ${findings.join(' · ')}', style: small),
        if (r != null && r.evidence.isNotEmpty) Text('근거 · ${r.evidence.join(', ')}', style: mono.copyWith(fontSize: 12, color: C.text2)),
      ]),
    );
  }

  static String _when(DateTime t) => '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

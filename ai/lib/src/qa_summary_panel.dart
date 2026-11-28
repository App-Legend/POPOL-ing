import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_request.dart';
import 'messages.dart';
import 'analysis_history.dart';
import 'api_key_dialog.dart';
import 'api_key_store.dart';
import 'qa_summary.dart';

/// 보내기 전 확인 창에 쓰는 분석 이름. 팀 용어로 QA = 헬스체크라 화면에는 "헬스체크"로 쓴다.
const qaSummaryRequestName = '헬스체크 결과 요약';

const _description = '검사 결과를 AI가 두세 문장으로 정리해요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.';
const _afterNotice = '요약은 판정을 바꾸지 않아요. 통과·실패는 헬스체크 규칙 그대로예요. AI 결과는 틀릴 수 있으니 근거를 확인해 주세요.';
const _sendNote = '주소는 호스트를 빼고 경로만 보내요. 응답 본문은 보내지 않아요.';

/// AI-03 헬스체크 결과 요약 패널. 화면 8 카드에 쓰고, 나중에 화면 6(헬스체크, C) 아래에도 끼운다.
///
/// 통과·실패 판정은 [run] 그대로 보여주고 AI 는 설명만 붙인다. 보내기는 [AiRequestView](`AiSender` 한 길)로만 한다.
class QaSummaryPanel extends StatefulWidget {
  const QaSummaryPanel({
    super.key,
    required this.run,
    required this.client,
    required this.keys,
    required this.qa,
    required this.orchestrator,
    this.checkKey,
    this.onKeysChanged,
    this.onRecord,
  });

  /// 요약할 검사.
  final QaRun run;
  final LlmClient client;

  /// 키 입력 창과 보낼 내용의 키 가리기에 쓴다.
  final ApiKeyStore keys;

  /// 같은 항목의 최근 이력을 읽는다.
  final QaRunner qa;

  /// 마지막 전체 실행 요약을 읽는다.
  final Orchestrator orchestrator;

  /// 키 입력 창의 [연결 확인]. null 이면 버튼이 없다.
  final ApiKeyCheck? checkKey;

  /// 패널의 [키 입력]·[키 바꾸기]로 키를 저장하거나 지웠을 때. 화면 머리의 키 상태를 다시 읽게 한다.
  final VoidCallback? onKeysChanged;

  /// 요약이 끝나면(답 받음·보내지 못함) 기록 하나를 넘긴다.
  final void Function(AnalysisRecord record)? onRecord;

  @override
  State<QaSummaryPanel> createState() => _QaSummaryPanelState();
}

enum _Phase { loading, empty, allPassed, request }

class _QaSummaryPanelState extends State<QaSummaryPanel> {
  _Phase _phase = _Phase.loading;
  QaSummaryInput? _input;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QaSummaryPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.run, widget.run)) {
      _phase = _Phase.loading;
      _load();
    }
  }

  void _set(_Phase phase) {
    if (mounted) {
      setState(() => _phase = phase);
    }
  }

  Future<void> _load() async {
    final run = widget.run;
    if (run.results.isEmpty) {
      return _set(_Phase.empty);
    }
    // 이력·실행 요약을 못 읽어도 이번 검사만으로 요약한다(예: 목록에서 지워진 프로젝트).
    List<QaRun> history;
    try {
      history = await widget.qa.history(run.projectId);
    } on Exception {
      history = const [];
    }
    RunSummary? lastRun;
    try {
      lastRun = await widget.orchestrator.lastRun(run.projectId);
    } on Exception {
      lastRun = null;
    }
    final input = QaSummaryInput(run: run, history: history, lastRun: lastRun);
    _input = input;
    _set(input.needsAi ? _Phase.request : _Phase.allPassed);
  }

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 14, height: 1.6);
    return switch (_phase) {
      _Phase.loading => const SizedBox.shrink(),
      _Phase.empty => const Text('검사할 항목이 없어요.', style: body),
      _Phase.allPassed => const Text('모든 검사를 통과했어요.', style: body),
      _Phase.request => _request(_input!),
    };
  }

  Widget _request(QaSummaryInput input) => AiRequestView<List<QaSummarySentence>>(
        key: ObjectKey(input),
        client: widget.client,
        keys: widget.keys,
        requestName: qaSummaryRequestName,
        content: () async => input.prompt,
        parse: (reply) => parseQaSummary(reply, input.run),
        done: (context, sentences, again) => _done(input, sentences, again),
        startLabel: 'AI 요약',
        againLabel: '다시 요약',
        system: qaSummarySystem,
        notes: const [_sendNote],
        description: _description,
        checkKey: widget.checkKey,
        onKeysChanged: widget.onKeysChanged,
        onDone: (sentences) => _record(AnalysisOutcome.received, sentences.first.text, sentences.map((s) => s.text).join('\n')),
        onFailed: (failure) => _record(AnalysisOutcome.failed, llmErrorText(failure).title, null),
        onUnreadable: () => _record(AnalysisOutcome.received, 'AI 답을 읽지 못했어요.', null),
      );

  void _record(AnalysisOutcome outcome, String title, String? body) => widget.onRecord?.call(AnalysisRecord(
        kind: AnalysisKind.qaSummary,
        projectId: widget.run.projectId,
        title: title,
        body: body,
        sentSummary: '헬스체크 결과 ${widget.run.results.length}건(주소는 경로만)',
        model: outcome == AnalysisOutcome.received ? widget.client.modelName : null,
        at: DateTime.now(),
        outcome: outcome,
      ));

  Widget _done(QaSummaryInput input, List<QaSummarySentence> sentences, VoidCallback again) {
    const body = TextStyle(fontSize: 14, height: 1.6);
    const muted = TextStyle(fontSize: 13, color: C.muted, height: 1.6);
    final flags = input.flags;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      for (final s in sentences)
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text(s.text, style: body),
          Text('근거  ${s.evidence.map(evidenceLabel).join(' / ')}', style: mono.copyWith(fontSize: 12, color: C.text2)),
        ]),
      if (flags.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in flags)
            StatusChip('${f.label} · ${f.result.name}', switch (f.kind) {
              QaFlagKind.failed => C.bad,
              QaFlagKind.slow => C.warn,
              QaFlagKind.needsSetup => C.idle,
            }),
        ]),
      Text('요약 완료 · ${widget.client.modelName}', style: mono.copyWith(fontSize: 12, color: C.text2)),
      const Text(_afterNotice, style: muted),
      Align(alignment: Alignment.centerRight, child: Btn('다시 요약', onPressed: again)),
    ]);
  }
}

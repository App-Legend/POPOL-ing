import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_sender.dart';
import 'api_key_dialog.dart';
import 'api_key_store.dart';
import 'messages.dart';
import 'qa_summary.dart';

/// 보내기 전 확인 창에 쓰는 분석 이름. 팀 용어로 QA = 헬스체크라 화면에는 "헬스체크"로 쓴다.
const qaSummaryRequestName = '헬스체크 결과 요약';

const _description = '검사 결과를 AI가 두세 문장으로 정리해요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.';
const _working = '분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.';
const _afterNotice = '요약은 판정을 바꾸지 않아요. 통과·실패는 헬스체크 규칙 그대로예요. AI 결과는 틀릴 수 있으니 근거를 확인해 주세요.';
const _sendNote = '주소는 호스트를 빼고 경로만 보내요. 응답 본문은 보내지 않아요.';

/// AI-03 헬스체크 결과 요약 패널. 화면 8 카드에 쓰고, 나중에 화면 6(헬스체크, C) 아래에도 끼운다.
///
/// 통과·실패 판정은 [run] 그대로 보여주고 AI 는 설명만 붙인다. 보내기는 [AiSender] 한 길로만 한다.
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

  @override
  State<QaSummaryPanel> createState() => _QaSummaryPanelState();
}

enum _Phase { loading, empty, allPassed, missingKey, keyUnreadable, ready, working, done, failed, unreadable, cancelled }

class _QaSummaryPanelState extends State<QaSummaryPanel> {
  _Phase _phase = _Phase.loading;
  QaSummaryInput? _input;
  List<QaSummarySentence> _sentences = const [];
  LlmFailure? _failure;

  /// 보낼 때마다 올린다. [취소]·화면 떠남 뒤에 온 답은 번호가 달라 버린다.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QaSummaryPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.run, widget.run)) {
      _attempt++;
      _phase = _Phase.loading;
      _load();
    }
  }

  @override
  void dispose() {
    _attempt++;
    super.dispose();
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
    if (!input.needsAi) {
      return _set(_Phase.allPassed);
    }
    await _checkKey();
  }

  Future<void> _checkKey() async {
    final bool configured;
    try {
      configured = await widget.client.isConfigured();
    } catch (_) {
      return _set(_Phase.keyUnreadable); // OS 보안 저장소를 못 읽음(잠김 등). 빈 카드로 멈추지 않게 알린다.
    }
    if (!configured) {
      _failure = LlmFailure.missingKey;
    }
    _set(configured ? _Phase.ready : _Phase.missingKey);
  }

  Future<void> _send() async {
    final input = _input!;
    final attempt = ++_attempt;
    final before = _phase;
    var confirmed = false;
    try {
      final reply = await AiSender(widget.client, keys: widget.keys).send(
        context,
        requestName: qaSummaryRequestName,
        content: input.prompt,
        system: qaSummarySystem,
        notes: const [_sendNote],
        onConfirmed: () {
          confirmed = true;
          if (attempt == _attempt) _set(_Phase.working);
        },
      );
      if (attempt != _attempt) {
        return;
      }
      if (reply == null) {
        return _set(before); // 확인 창에서 [취소]
      }
      final sentences = parseQaSummary(reply, input.run);
      if (sentences == null) {
        return _set(_Phase.unreadable);
      }
      _sentences = sentences;
      _set(_Phase.done);
    } on LlmException catch (e) {
      if (attempt != _attempt) {
        return;
      }
      _failure = e.failure;
      _set(e.failure == LlmFailure.missingKey ? _Phase.missingKey : _Phase.failed);
    } catch (_) {
      // LlmException 이 아닌 오류. 보내기 전이면 키 저장소 문제, 보낸 뒤면 연결 문제로 안내한다("분석 중"에 멈추지 않게).
      if (attempt != _attempt) {
        return;
      }
      if (confirmed) {
        _failure = LlmFailure.network;
        _set(_Phase.failed);
      } else {
        _set(_Phase.keyUnreadable);
      }
    }
  }

  void _cancel() {
    _attempt++;
    _set(_Phase.cancelled);
  }

  Future<void> _openKeys() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ApiKeyChange? change;
    try {
      change = await showApiKeyDialog(context, widget.keys, check: widget.checkKey);
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('보안 저장소를 쓰지 못해 키 입력 창을 열지 못했어요.')));
      return;
    }
    if (change != null) {
      widget.onKeysChanged?.call();
    }
    await _checkKey();
  }

  void _onErrorAction(LlmFailure failure) => switch (failure) {
        LlmFailure.missingKey || LlmFailure.invalidKey => _openKeys(),
        LlmFailure.quotaExceeded || LlmFailure.network => _send(),
      };

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 14, height: 1.6);
    const muted = TextStyle(fontSize: 13, color: C.muted, height: 1.6);
    Widget action(String label, VoidCallback onPressed, {bool primary = false}) =>
        Align(alignment: Alignment.centerRight, child: Btn(label, primary: primary, onPressed: onPressed));

    final children = switch (_phase) {
      _Phase.loading => <Widget>[],
      _Phase.empty => [const Text('검사할 항목이 없어요.', style: body)],
      _Phase.allPassed => [const Text('모든 검사를 통과했어요.', style: body)],
      _Phase.ready => [const Text(_description, style: muted), action('AI 요약', _send, primary: true)],
      _Phase.cancelled => [
          const Text('분석을 멈췄어요.', style: body),
          const Text(_description, style: muted),
          action('AI 요약', _send, primary: true),
        ],
      _Phase.working => [const Text(_working, style: body), action('취소', _cancel)],
      _Phase.unreadable => [const Text('AI 답을 읽지 못했어요.', style: body), action('다시 요약', _send)],
      _Phase.keyUnreadable => [const Text('이 컴퓨터의 보안 저장소에서 API 키를 읽지 못했어요.', style: body), action('다시 시도', _checkKey)],
      _Phase.missingKey || _Phase.failed => _error(llmErrorText(_failure!), body),
      _Phase.done => _done(body, muted, action),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: children);
  }

  List<Widget> _error(LlmErrorText text, TextStyle body) => [
        Text(text.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Text(text.body, style: body),
        Align(alignment: Alignment.centerRight, child: Btn(text.action, onPressed: () => _onErrorAction(_failure!))),
      ];

  List<Widget> _done(TextStyle body, TextStyle muted, Widget Function(String, VoidCallback, {bool primary}) action) {
    final flags = _input!.flags;
    return [
      for (final s in _sentences)
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
      Text(_afterNotice, style: muted),
      action('다시 요약', _send),
    ];
  }
}

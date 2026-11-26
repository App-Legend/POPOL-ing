import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'analysis_history.dart';
import 'api_key_dialog.dart';
import 'api_key_store.dart';

/// 화면에 보여 줄 키. 끝 4자리만 남긴다. 8자 이하로 짧으면 4자리도 많이 드러나서 모두 가린다.
String maskedApiKey(String key) => key.length <= 8 ? '••••••••' : '••••••••${key.substring(key.length - 4)}';

/// 7. AI 검사(목업 v2): API 키 상태와 [키 입력]·[키 바꾸기], 받은 분석 기록 목록.
///
/// 분석은 프로젝트 화면(로그 탭의 [원인 분석], 헬스체크의 [AI 요약])에서 하고, 그 결과가 [history] 에 남는다.
class AiScreen extends StatefulWidget {
  const AiScreen({super.key, required this.keys, required this.client, this.checkKey, this.history});

  final ApiKeyStore keys;

  /// 모델 이름(`modelName`)을 보여 준다.
  final LlmClient client;

  /// 키 입력 창의 [연결 확인]. null 이면 버튼이 없다.
  final ApiKeyCheck? checkKey;

  /// 분석 기록. 없으면 목록 자리에 안내만.
  final AnalysisHistory? history;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

enum _KeyStatus { loading, missing, present, unreadable }

class _AiScreenState extends State<AiScreen> {
  _KeyStatus _status = _KeyStatus.loading;

  /// 가린 키. 키 전체는 화면 상태에 두지 않는다.
  String? _masked;

  List<AnalysisRecord>? _records;
  var _corrupt = false;
  int? _open;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadHistory());
    _changes = widget.history?.changes.listen((_) => _loadHistory());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = widget.history;
    if (history == null) return;
    try {
      final records = await history.list();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      // 깨진 파일(AnalysisHistoryCorrupt)이든 폴더를 못 찾았든, 덮어쓰지 않고 알리기만 한다
      if (mounted) setState(() => _corrupt = true);
    }
  }

  Future<void> _load() async {
    _KeyStatus status;
    String? masked;
    try {
      final key = await widget.keys.read();
      status = key == null ? _KeyStatus.missing : _KeyStatus.present;
      masked = key == null ? null : maskedApiKey(key);
    } catch (_) {
      status = _KeyStatus.unreadable;
    }
    if (mounted) {
      setState(() {
        _status = status;
        _masked = masked;
      });
    }
  }

  Future<void> _openDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    ApiKeyChange? change;
    try {
      change = await showApiKeyDialog(context, widget.keys, check: widget.checkKey);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('보안 저장소를 쓰지 못해 키 입력 창을 열지 못했어요.')));
      return;
    }
    if (change == null) {
      return;
    }
    await _load();
    messenger.showSnackBar(SnackBar(
      content: Text(switch (change) {
        ApiKeyChange.saved => 'API 키를 저장했어요.',
        ApiKeyChange.deleted => 'API 키를 지웠어요. AI 분석을 하려면 다시 넣어 주세요.',
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final (label, tone, description) = switch (_status) {
      _KeyStatus.loading => ('키 확인 중', C.idle, ''),
      _KeyStatus.present => ('API 키 입력됨', C.ok, '${widget.client.modelName} · 키 $_masked'),
      _KeyStatus.missing => ('API 키 필요', C.idle, 'Gemini API 키를 넣으면 AI 분석을 쓸 수 있어요.'),
      _KeyStatus.unreadable => ('키를 읽지 못함', C.bad, '이 컴퓨터의 보안 저장소에서 API 키를 읽지 못했어요.'),
    };
    final hasKey = _status == _KeyStatus.present;
    const body = TextStyle(fontSize: 14, height: 1.6);

    return AppPage(
      crumbs: const [('AI 검사', null)],
      children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Text('AI 검사', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          Text('[원인 분석]·[AI 요약]으로 받은 답이 남아요.', style: TextStyle(fontSize: 14, color: C.text2)),
        ]),
        Panel(
          child: Wrap(spacing: 12, runSpacing: 10, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(label, tone),
              if (description.isNotEmpty)
                Text(description, style: hasKey ? mono.copyWith(fontSize: 13, color: C.text2) : const TextStyle(fontSize: 13, color: C.text2)),
            ]),
            Btn(hasKey ? '키 바꾸기' : '키 입력', primary: !hasKey, onPressed: _status == _KeyStatus.loading ? null : _openDialog),
          ]),
        ),
        Notice(
          bg: C.remote.$1,
          border: const Color(0xFFB9C8F5),
          icon: Icons.send_outlined,
          iconColor: C.remote.$2,
          child: const Text('[보내기]를 누른 뒤에만 Google로 보내요. .env 값과 API 키는 보내지 않아요.', style: body),
        ),
        if (_status == _KeyStatus.missing || _status == _KeyStatus.unreadable)
          Notice(
            bg: C.headBg,
            border: C.border,
            icon: Icons.key_outlined,
            iconColor: C.muted,
            child: const Text(
              'AI 분석을 하려면 Gemini API 키가 필요해요. 키가 없어도 실행·종료·헬스체크 같은 다른 기능은 그대로 쓸 수 있어요.',
              style: body,
            ),
          ),
        _historyPanel(),
      ],
    );
  }

  Widget _historyPanel() {
    final records = _records;
    if (_corrupt) return const Text('기록 파일을 읽지 못했어요', style: TextStyle(fontSize: 14));
    if (widget.history != null && records == null) return const SizedBox.shrink(); // 읽는 동안은 비워 둔다(보통 바로 끝난다)
    if (records == null || records.isEmpty) return const Text('아직 받은 답이 없어요.', style: TextStyle(fontSize: 14, color: C.muted));
    return Panel(
      title: '최근 · ${records.length}',
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in records.indexed) _recordRow(i, r),
      ]),
    );
  }

  Widget _recordRow(int i, AnalysisRecord r) {
    final open = _open == i;
    final received = r.outcome == AnalysisOutcome.received;
    final where = r.serviceId == null ? r.projectId : '${r.projectId} · ${r.serviceId}';
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(spacing: 12, children: [
              SizedBox(width: 72, child: Text(r.kind == AnalysisKind.failure ? '원인 분석' : 'AI 요약', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(where, style: const TextStyle(fontSize: 12, color: C.muted)),
                  Text(r.title, maxLines: open ? null : 1, overflow: open ? null : TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                ]),
              ),
              Text(_time(r.at), style: const TextStyle(fontSize: 12, color: C.muted)),
              received ? const StatusChip('받음', C.ok) : const StatusChip('보내지 못함', C.bad),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(104, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              if (r.body != null) Text(r.body!, style: const TextStyle(fontSize: 14, height: 1.6)),
              Text('보낸 것: ${r.sentSummary}${r.model == null ? '' : ' · ${r.model}'}', style: const TextStyle(fontSize: 12, color: C.muted)),
              if (received) const Text('AI 결과는 틀릴 수 있어요. 근거를 확인한 뒤 판단해 주세요.', style: TextStyle(fontSize: 12, color: C.muted)),
              Btn('프로젝트 열기', small: true, onPressed: () => Navigator.pushNamed(context, '/dashboard', arguments: r.projectId)),
            ]),
          ),
      ]),
    );
  }

  static String _time(DateTime t) => '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

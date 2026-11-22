import 'package:flutter/material.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/ui.dart';

import 'api_key_dialog.dart';
import 'api_key_store.dart';
import 'qa_summary_panel.dart';

/// 화면에 보여 줄 키. 끝 4자리만 남긴다. 8자 이하로 짧으면 4자리도 많이 드러나서 모두 가린다.
String maskedApiKey(String key) => key.length <= 8 ? '••••••••' : '••••••••${key.substring(key.length - 4)}';

/// 8. AI 검사. 머리(API 키 상태와 [키 입력]·[키 바꾸기])와 헬스체크 결과 요약(AI-03) 카드.
// 실행 실패 원인 분석(AI-02) 카드는 다음에 붙인다.
class AiScreen extends StatefulWidget {
  const AiScreen({
    super.key,
    required this.keys,
    required this.client,
    this.checkKey,
    this.projectId,
    this.qa,
    this.orchestrator,
    this.clock = DateTime.now,
  });

  final ApiKeyStore keys;

  /// 모델 이름(`modelName`)을 보여 준다.
  final LlmClient client;

  /// 키 입력 창의 [연결 확인]. null 이면 버튼이 없다.
  final ApiKeyCheck? checkKey;

  /// 대시보드 [AI 검사]가 넘긴 프로젝트. [qa]·[orchestrator] 와 함께 있으면 헬스체크 결과 요약 카드를 그린다.
  final String? projectId;
  final QaRunner? qa;
  final Orchestrator? orchestrator;

  /// 카드 머리의 "오늘" 판단에 쓴다.
  final DateTime Function() clock;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

enum _KeyStatus { loading, missing, present, unreadable }

class _AiScreenState extends State<AiScreen> {
  _KeyStatus _status = _KeyStatus.loading;

  /// 가린 키. 키 전체는 화면 상태에 두지 않는다.
  String? _masked;

  /// 요약할 최근 헬스체크. [_qaLoaded] 가 true 인데 null 이면 아직 검사한 적이 없다.
  QaRun? _latest;
  bool _qaLoaded = false;
  bool _checking = false;

  bool get _hasCard => widget.projectId != null && widget.qa != null && widget.orchestrator != null;

  @override
  void initState() {
    super.initState();
    _load();
    if (_hasCard) {
      _loadQa();
    }
  }

  Future<void> _loadQa() async {
    QaRun? latest;
    try {
      latest = (await widget.qa!.history(widget.projectId!)).firstOrNull;
    } on Exception {
      latest = null;
    }
    if (mounted) {
      setState(() {
        _latest = latest;
        _qaLoaded = true;
      });
    }
  }

  /// 카드의 [헬스체크]. 누를 때만 검사한다.
  Future<void> _runCheck() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      await widget.qa!.runChecks(widget.projectId!);
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('헬스체크를 하지 못했어요.')));
    }
    await _loadQa();
    if (mounted) {
      setState(() => _checking = false);
    }
  }

  /// "오늘 14:05" 또는 "11/22 14:05".
  String _when(DateTime t) {
    final now = widget.clock();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final today = t.year == now.year && t.month == now.month && t.day == now.day;
    return today ? '오늘 $hm' : '${t.month}/${t.day} $hm';
  }

  Widget _qaCard() {
    final latest = _latest;
    return Panel(
      title: '헬스체크 결과 요약',
      titleAction: latest == null ? null : Text('${_when(latest.startedAt)} 검사 기준', style: const TextStyle(fontSize: 13, color: C.muted)),
      child: !_qaLoaded
          ? const SizedBox.shrink()
          : latest == null
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                  const Text('아직 헬스체크 결과가 없어요.', style: TextStyle(fontSize: 14, height: 1.6)),
                  Align(alignment: Alignment.centerRight, child: Btn('헬스체크', onPressed: _checking ? null : _runCheck)),
                ])
              : QaSummaryPanel(
                  // 새 검사나 키 상태가 바뀌면 패널을 새로 그린다(키를 넣은 뒤 "API 키 필요"가 남지 않게).
                  key: ValueKey('${latest.startedAt}-$_status'),
                  run: latest,
                  client: widget.client,
                  keys: widget.keys,
                  qa: widget.qa!,
                  orchestrator: widget.orchestrator!,
                  checkKey: widget.checkKey,
                ),
    );
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
      crumbs: const [('개발', '/home'), ('AI 검사', null)],
      children: [
        Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            const Text('AI 검사', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(label, tone),
              if (description.isNotEmpty)
                Text(description, style: hasKey ? mono.copyWith(fontSize: 13, color: C.text2) : const TextStyle(fontSize: 13, color: C.text2)),
            ]),
          ]),
          Btn(
            hasKey ? '키 바꾸기' : '키 입력',
            primary: !hasKey,
            onPressed: _status == _KeyStatus.loading ? null : _openDialog,
          ),
        ]),
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
        if (_hasCard) _qaCard(),
        Text(
          _hasCard ? '실행 실패 원인 분석은 준비 중이에요.' : '실행 실패 원인 분석과 헬스체크 결과 요약은 준비 중이에요.',
          style: const TextStyle(fontSize: 13, color: C.muted),
        ),
      ],
    );
  }
}

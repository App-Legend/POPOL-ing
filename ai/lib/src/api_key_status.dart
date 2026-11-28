import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_screen.dart' show maskedApiKey;
import 'api_key_dialog.dart';
import 'api_key_store.dart';

enum _KeyStatus { loading, missing, present, unreadable }

/// API 키 상태 한 줄: 상태 칩, 모델·가린 키(끝 4자리), [키 입력]·[키 바꾸기].
///
/// 키 전체는 화면 상태에 두지 않고 가린 글만 둔다.
class ApiKeyStatus extends StatefulWidget {
  const ApiKeyStatus({super.key, required this.keys, required this.client, this.checkKey});

  final ApiKeyStore keys;
  final LlmClient client;
  final ApiKeyCheck? checkKey;

  @override
  State<ApiKeyStatus> createState() => _ApiKeyStatusState();
}

class _ApiKeyStatusState extends State<ApiKeyStatus> {
  _KeyStatus _status = _KeyStatus.loading;
  String? _masked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _KeyStatus status;
    String? masked;
    try {
      final key = await widget.keys.read();
      status = key == null ? _KeyStatus.missing : _KeyStatus.present;
      masked = key == null ? null : maskedApiKey(key);
    } catch (_) {
      status = _KeyStatus.unreadable; // OS 보안 저장소를 못 읽음(잠김 등)
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
    if (change == null) return;
    // 창이 돌려준 결과 대신 저장소를 다시 읽는다. 보안 저장소에 실제로 들어갔는지 화면만 보고 알 수 있게.
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
    return Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      StatusChip(label, tone),
      if (description.isNotEmpty) Text(description, style: hasKey ? mono.copyWith(fontSize: 13, color: C.text2) : const TextStyle(fontSize: 13, color: C.text2)),
      Btn(hasKey ? '키 바꾸기' : '키 입력', small: true, primary: !hasKey, onPressed: _status == _KeyStatus.loading ? null : _openDialog),
    ]);
  }
}

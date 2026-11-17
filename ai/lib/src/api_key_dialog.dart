import 'package:flutter/material.dart';
import 'package:ppoling_core/ui.dart';

import 'api_key_store.dart';

/// 키 입력 창에서 한 일.
enum ApiKeyChange { saved, deleted }

/// "Gemini API 키 입력" 창을 띄운다. 저장·삭제는 창 안에서 [store] 에 바로 한다. 취소하면 null.
Future<ApiKeyChange?> showApiKeyDialog(BuildContext context, ApiKeyStore store) async {
  final hasKey = await store.read() != null;
  if (!context.mounted) {
    return null;
  }
  return showDialog<ApiKeyChange>(
    context: context,
    builder: (_) => Dialog(child: ApiKeyDialog(store: store, hasKey: hasKey)),
  );
}

/// API 키 입력 창. 입력한 키는 가려서 보이고, 이 컴퓨터의 보안 저장소에만 둔다.
class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({super.key, required this.store, required this.hasKey});

  final ApiKeyStore store;

  /// 이미 저장된 키가 있는지. 있으면 [키 지우기]를 보여준다.
  final bool hasKey;

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  final _field = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _field.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'API 키를 넣어 주세요.');
      return;
    }
    await _change(() => widget.store.write(key), ApiKeyChange.saved, '키를 저장하지 못했어요. 이 컴퓨터의 보안 저장소를 쓸 수 없어요.');
  }

  Future<void> _delete() =>
      _change(widget.store.delete, ApiKeyChange.deleted, '키를 지우지 못했어요. 이 컴퓨터의 보안 저장소를 쓸 수 없어요.');

  /// 저장소를 바꾸고 창을 닫는다. 실패하면 창에 [failure] 를 보이고 다시 누를 수 있게 둔다.
  Future<void> _change(Future<void> Function() action, ApiKeyChange done, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure;
        });
      }
      return;
    }
    if (mounted) {
      closeDialog(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    const note = TextStyle(fontSize: 12.5, color: C.muted, height: 1.5);
    return DialogBody('Gemini API 키 입력', [
      const Text(
        'AI 분석에 쓸 내 Gemini API 키를 넣어 주세요. 키는 Google AI Studio에서 무료로 만들 수 있어요.',
        style: TextStyle(fontSize: 14, color: C.text2, height: 1.6),
      ),
      TextField(
        key: const Key('api-key-field'),
        controller: _field,
        obscureText: true,
        autofocus: true,
        enableSuggestions: false,
        autocorrect: false,
        style: mono.copyWith(fontSize: 13),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'API 키',
          hintText: widget.hasKey ? '새 키를 넣으면 바꿔요' : 'Google AI Studio에서 만든 키를 붙여 넣어 주세요',
          errorText: _error,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
      const Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Icon(Icons.lock_outline, size: 15, color: C.muted),
        Expanded(child: Text('키는 이 컴퓨터의 보안 저장소에만 두고, 화면과 로그에는 가려서 보여요. ppoling.yaml에는 쓰지 않아요.', style: note)),
      ]),
      const Text('무료 등급은 사용량 제한이 있고, 보낸 내용이 Google 서비스 개선에 쓰일 수 있어요. 자세한 조건은 Google 약관을 확인해 주세요.', style: note),
      Row(spacing: 8, children: [
        if (widget.hasKey) Btn('키 지우기', ghost: true, onPressed: _busy ? null : _delete),
        const Spacer(),
        Btn('취소', onPressed: _busy ? null : () => closeDialog(context)),
        Btn('저장', primary: true, onPressed: _busy ? null : _save),
      ]),
    ]);
  }
}

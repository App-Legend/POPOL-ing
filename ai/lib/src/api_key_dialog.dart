import 'package:flutter/material.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/ui.dart';

import 'api_key_store.dart';
import 'messages.dart';

/// 키 입력 창에서 한 일.
enum ApiKeyChange { saved, deleted }

/// 키로 연결되는지 확인한다. 되면 끝나고, 안 되면 [LlmException]. 예: `GeminiLlmClient.checkKey`.
typedef ApiKeyCheck = Future<void> Function(String key);

/// "Gemini API 키 입력" 창을 띄운다. 저장·삭제는 창 안에서 [store] 에 바로 한다. 취소하면 null.
/// [check] 를 주면 [연결 확인] 버튼이 생긴다.
Future<ApiKeyChange?> showApiKeyDialog(BuildContext context, ApiKeyStore store, {ApiKeyCheck? check}) async {
  final hasKey = await store.read() != null;
  if (!context.mounted) {
    return null;
  }
  return showDialog<ApiKeyChange>(
    context: context,
    builder: (_) => Dialog(child: ApiKeyDialog(store: store, hasKey: hasKey, check: check)),
  );
}

/// API 키 입력 창. 입력한 키는 가려서 보이고, 이 컴퓨터의 보안 저장소에만 둔다.
class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({super.key, required this.store, required this.hasKey, this.check});

  final ApiKeyStore store;

  /// 이미 저장된 키가 있는지. 있으면 [키 지우기]를 보여준다.
  final bool hasKey;

  /// [연결 확인]에 쓴다. null 이면 버튼이 없다.
  final ApiKeyCheck? check;

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

/// [연결 확인] 결과 한 줄.
sealed class _CheckResult {}

class _Connected implements _CheckResult {
  _Connected({required this.saved});

  /// 저장된 키로 확인했다(칸이 비어 있었다).
  final bool saved;
}

class _NotConnected implements _CheckResult {
  _NotConnected(this.failure);

  final LlmFailure failure;
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  final _field = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _checking = false;
  _CheckResult? _check;

  Future<void> _connect(ApiKeyCheck check) async {
    final typed = _field.text.trim();
    var key = typed;
    final saved = key.isEmpty;
    setState(() {
      _error = null;
      _check = null;
      _checking = true;
    });
    _CheckResult? result;
    try {
      if (saved) {
        key = await widget.store.read() ?? '';
      }
      if (key.isNotEmpty) {
        await check(key);
        result = _Connected(saved: saved);
      }
    } on LlmException catch (e) {
      result = _NotConnected(e.failure);
    } catch (_) {
      result = _NotConnected(LlmFailure.network);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      // 확인하는 사이에 키를 고쳤으면 고치기 전 키의 결과라 보여 주지 않는다.
      if (_field.text.trim() == typed) {
        _check = result;
        _error = result == null ? 'API 키를 넣어 주세요.' : null;
      }
    });
  }

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
    final check = widget.check;
    return DialogBody('Gemini API 키 입력', maxWidth: 480, [
      const Text(
        'AI 분석에 쓸 내 Gemini API 키를 넣어 주세요. 키는 Google AI Studio에서 무료로 만들 수 있어요.',
        style: TextStyle(fontSize: 14, color: C.text2, height: 1.6),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
        const Text('키 만드는 방법: 아래 주소를 브라우저에 붙여 넣고 Google 계정으로 로그인한 뒤, 새 API 키를 만들어 복사해 오세요.', style: note),
        SelectableText('https://aistudio.google.com/apikey', style: mono.copyWith(fontSize: 12.5, color: C.text2)),
      ]),
      TextField(
        key: const Key('api-key-field'),
        controller: _field,
        obscureText: true,
        autofocus: true,
        enableSuggestions: false,
        autocorrect: false,
        style: mono.copyWith(fontSize: 13),
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_check != null || _error != null) {
            setState(() {
              _check = null;
              _error = null;
            });
          }
        },
        decoration: InputDecoration(
          labelText: 'API 키',
          hintText: widget.hasKey ? '새 키를 넣으면 바꿔요' : 'Google AI Studio에서 만든 키를 붙여 넣어 주세요',
          errorText: _error,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
      if (_check case final result?) _checkLine(result),
      const Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Icon(Icons.lock_outline, size: 15, color: C.muted),
        Expanded(child: Text('키는 이 컴퓨터의 보안 저장소에만 두고, 화면과 로그에는 가려서 보여요. popoling.yaml에는 쓰지 않아요.', style: note)),
      ]),
      if (check != null) const Text('[연결 확인]은 이 키로 Google에 연결되는지만 봐요. 다른 내용은 보내지 않아요.', style: note),
      const Text('무료 등급은 사용량 제한이 있고, 보낸 내용이 Google 서비스 개선에 쓰일 수 있어요. 자세한 조건은 Google 약관을 확인해 주세요.', style: note),
      Row(spacing: 8, children: [
        if (widget.hasKey) Btn('키 지우기', ghost: true, onPressed: _busy ? null : _delete),
        const Spacer(),
        if (check != null)
          _checking ? const Btn('확인하는 중…', onPressed: null) : Btn('연결 확인', onPressed: _busy ? null : () => _connect(check)),
        Btn('취소', onPressed: _busy ? null : () => closeDialog(context)),
        Btn('저장', primary: true, onPressed: _busy ? null : _save),
      ]),
    ]);
  }

  /// [연결 확인] 결과. 실패하면 오류 안내 4종의 제목과 설명을 그대로 쓴다.
  Widget _checkLine(_CheckResult result) {
    final (icon, color, title, body) = switch (result) {
      _Connected(saved: true) => (Icons.check_circle_outline, C.ok.$2, null, '연결됐어요. 저장된 키로 AI 분석을 쓸 수 있어요.'),
      _Connected() => (Icons.check_circle_outline, C.ok.$2, null, '연결됐어요. [저장]을 누르면 이 키를 써요.'),
      _NotConnected(:final failure) => (Icons.error_outline, C.bad.$2, llmErrorText(failure).title, llmErrorText(failure).body),
    };
    const style = TextStyle(fontSize: 13, height: 1.5, color: C.text2);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
      Icon(icon, size: 16, color: color),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          if (title != null) Text(title, style: style.copyWith(fontWeight: FontWeight.w700, color: C.text)),
          Text(body, style: style),
        ]),
      ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_sender.dart';
import 'api_key_dialog.dart';
import 'api_key_store.dart';
import 'messages.dart';

const aiWorkingText = '분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.';

/// AI 분석 하나의 보내기 과정. AI-02 원인 분석·AI-03 헬스체크 결과 요약이 같이 쓴다.
///
/// 키 확인 → [startLabel] → 보내기 전 확인 창([AiSender]) → 분석 중·[취소] → [done] 또는 오류 안내.
/// 각 기능은 무엇을 보낼지([content])와 답을 어떻게 읽고 그릴지([parse]·[done])만 넘긴다.
class AiRequestView<T extends Object> extends StatefulWidget {
  const AiRequestView({
    super.key,
    required this.client,
    required this.keys,
    required this.requestName,
    required this.content,
    required this.parse,
    required this.done,
    required this.startLabel,
    required this.againLabel,
    this.system,
    this.notes = const [],
    this.description,
    this.checkKey,
    this.onKeysChanged,
    this.onDone,
    this.onFailed,
  });

  final LlmClient client;

  /// 키 입력 창과 보낼 내용의 키 가리기에 쓴다.
  final ApiKeyStore keys;

  /// 보내기 전 확인 창의 분석 이름.
  final String requestName;

  /// 보낼 글. 보낼 때마다 새로 부른다(예: 로그를 그때 읽는다).
  final Future<String> Function() content;

  /// 답을 읽는다. 못 읽으면 null 이고 "AI 답을 읽지 못했어요"로 보여준다.
  final T? Function(String reply) parse;

  /// 읽은 답을 그린다. [again] 은 [againLabel] 버튼에 쓴다.
  final Widget Function(BuildContext context, T result, VoidCallback again) done;

  /// 처음·취소함 상태의 버튼. 예: `AI 요약`, `원인 분석`
  final String startLabel;

  /// 답을 못 읽었을 때와 완료 화면의 다시 버튼. 예: `다시 요약`, `다시 분석`
  final String againLabel;

  final String? system;

  /// 보내기 전 확인 창에 덧붙일 안내.
  final List<String> notes;

  /// 처음·취소함 상태에 보여줄 설명. null 이면 버튼만.
  final String? description;

  /// 키 입력 창의 [연결 확인]. null 이면 버튼이 없다.
  final ApiKeyCheck? checkKey;

  /// [키 입력]·[키 바꾸기]로 키를 저장하거나 지웠을 때. 화면 머리의 키 상태를 다시 읽게 한다.
  final VoidCallback? onKeysChanged;

  /// 답을 읽었을 때 한 번(분석 기록). 취소한 분석은 부르지 않는다.
  final void Function(T result)? onDone;

  /// 보냈는데 실패했을 때 한 번(분석 기록). 키가 없어 보내지 않은 것도 부르지 않는다.
  final void Function(LlmFailure failure)? onFailed;

  @override
  State<AiRequestView<T>> createState() => _AiRequestViewState<T>();
}

enum _Phase { loading, missingKey, keyUnreadable, ready, working, done, failed, unreadable, cancelled }

class _AiRequestViewState<T extends Object> extends State<AiRequestView<T>> {
  _Phase _phase = _Phase.loading;
  T? _result;
  LlmFailure? _failure;

  /// 보낼 때마다 올린다. [취소]·화면 떠남 뒤에 온 답은 번호가 달라 버린다.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _checkKey();
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
    final attempt = ++_attempt;
    final before = _phase;
    var confirmed = false;
    try {
      final content = await widget.content();
      if (!mounted || attempt != _attempt) {
        return;
      }
      final reply = await AiSender(widget.client, keys: widget.keys).send(
        context,
        requestName: widget.requestName,
        content: content,
        system: widget.system,
        notes: widget.notes,
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
      final result = widget.parse(reply);
      if (result == null) {
        return _set(_Phase.unreadable);
      }
      _result = result;
      widget.onDone?.call(result);
      _set(_Phase.done);
    } on LlmException catch (e) {
      if (attempt != _attempt) {
        return;
      }
      _failure = e.failure;
      if (e.failure != LlmFailure.missingKey) widget.onFailed?.call(e.failure);
      _set(e.failure == LlmFailure.missingKey ? _Phase.missingKey : _Phase.failed);
    } catch (_) {
      // LlmException 이 아닌 오류. 보내기 전이면 키 저장소 문제, 보낸 뒤면 연결 문제로 안내한다("분석 중"에 멈추지 않게).
      if (attempt != _attempt) {
        return;
      }
      if (confirmed) {
        _failure = LlmFailure.network;
        widget.onFailed?.call(LlmFailure.network);
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
    final description = widget.description;

    final children = switch (_phase) {
      _Phase.loading => <Widget>[],
      _Phase.ready => [
          if (description != null) Text(description, style: muted),
          action(widget.startLabel, _send, primary: true),
        ],
      _Phase.cancelled => [
          const Text('분석을 멈췄어요.', style: body),
          if (description != null) Text(description, style: muted),
          action(widget.startLabel, _send, primary: true),
        ],
      _Phase.working => [const Text(aiWorkingText, style: body), action('취소', _cancel)],
      _Phase.unreadable => [const Text('AI 답을 읽지 못했어요.', style: body), action(widget.againLabel, _send)],
      _Phase.keyUnreadable => [const Text('이 컴퓨터의 보안 저장소에서 API 키를 읽지 못했어요.', style: body), action('다시 시도', _checkKey)],
      _Phase.missingKey || _Phase.failed => _error(llmErrorText(_failure!), body),
      _Phase.done => [widget.done(context, _result as T, _send)],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: children);
  }

  List<Widget> _error(LlmErrorText text, TextStyle body) => [
        Text(text.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Text(text.body, style: body),
        Align(alignment: Alignment.centerRight, child: Btn(text.action, onPressed: () => _onErrorAction(_failure!))),
      ];
}

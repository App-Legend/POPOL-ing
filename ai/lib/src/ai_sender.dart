import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';

import 'api_key_store.dart';
import 'redact.dart';
import 'send_confirm_dialog.dart';

/// AI 에 보내는 길은 이것 하나다: 비밀값 가리기 → 보내기 전 확인 창 → [보내기]를 눌렀을 때만 전송.
class AiSender {
  AiSender(this.client, {this.keys});

  final LlmClient client;

  /// 있으면 저장된 API 키가 내용에 섞여 있어도 가린다.
  final ApiKeyStore? keys;

  /// [content] 를 가려서 보여주고, 사용자가 [보내기]를 누르면 보내 답을 돌려준다.
  ///
  /// - 취소하면 아무것도 보내지 않고 null.
  /// - 키가 없으면 창을 띄우지 않고 [LlmException] ([LlmFailure.missingKey]).
  /// - [secrets] 는 꼭 가려야 하는 값(예: 그 프로젝트의 `.env` 값).
  /// - [onConfirmed] 는 [보내기]를 누른 직후, 보내기 전에 한 번 부른다. 화면을 "분석 중"으로 바꿀 때 쓴다.
  Future<String?> send(
    BuildContext context, {
    required String requestName,
    required String content,
    String? system,
    Iterable<String> secrets = const [],
    List<String> notes = const [],
    VoidCallback? onConfirmed,
  }) async {
    if (!await client.isConfigured()) {
      throw LlmException(LlmFailure.missingKey);
    }
    final apiKey = await keys?.read();
    final redacted = redactSecrets(content, secrets: [...secrets, ?apiKey]);
    if (!context.mounted) {
      return null;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        child: SendConfirmDialog(requestName: requestName, content: redacted.text, redactedCount: redacted.count, notes: notes),
      ),
    );
    if (confirmed != true) {
      return null;
    }
    onConfirmed?.call();
    return client.complete(redacted.text, system: system);
  }
}

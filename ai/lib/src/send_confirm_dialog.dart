import 'package:flutter/material.dart';
import 'package:ppoling_core/ui.dart';

/// 보내기 전 확인 창(기획서 §2, AT-21). 실제로 보낼 내용을 그대로 보여주고, [보내기]를 눌러야 true.
class SendConfirmDialog extends StatelessWidget {
  const SendConfirmDialog({super.key, required this.requestName, required this.content, this.redactedCount = 0, this.notes = const []});

  /// 무엇을 하려고 보내는지. 예: "QA 결과 요약", "실행 실패 원인 분석"
  final String requestName;

  /// 보낼 내용. 비밀값을 가린 뒤의 글 그대로다.
  final String content;

  /// 가린 비밀값 수.
  final int redactedCount;

  /// 요청마다 덧붙일 안내. 예: "주소는 호스트를 빼고 경로만 보내요."
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final hidden = redactedCount > 0 ? '비밀값으로 보이는 $redactedCount곳을 가렸어요. ' : '';
    return DialogBody('이 내용을 Google로 보낼까요?', maxWidth: 560, [
      Text(
        '${withObjectParticle(requestName)} 하려고 아래 내용을 Gemini API(Google)로 보내요. [보내기]를 누르기 전에는 아무것도 보내지 않아요.',
        style: const TextStyle(fontSize: 14, color: C.text2, height: 1.6),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: Container(
          decoration: BoxDecoration(color: C.headBg, border: Border.all(color: C.divider), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(content, key: const Key('send-preview'), style: mono.copyWith(fontSize: 12, height: 1.6)),
          ),
        ),
      ),
      Text(
        [...notes, '$hidden.env 값과 API 키는 보내지 않아요.', '무료 등급에서는 보낸 내용이 Google 서비스 개선에 쓰일 수 있어요.'].join(' '),
        style: const TextStyle(fontSize: 12.5, color: C.muted, height: 1.5),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
        Btn('취소', onPressed: () => closeDialog(context, false)),
        Btn('보내기', primary: true, icon: Icons.send, onPressed: () => closeDialog(context, true)),
      ]),
    ]);
  }
}

/// 받침에 맞춰 "을/를"을 붙인다. 한글로 끝나지 않으면 "을(를)".
String withObjectParticle(String word) {
  if (word.isEmpty) {
    return word;
  }
  final last = word.codeUnitAt(word.length - 1);
  if (last < 0xAC00 || last > 0xD7A3) {
    return '$word을(를)';
  }
  return (last - 0xAC00) % 28 == 0 ? '$word를' : '$word을';
}

import 'package:flutter/material.dart';

import 'theme.dart';

/// 라벨 + 입력칸. 대화상자 화면도 같이 쓴다. [obscure] 면 API 키처럼 값을 가린다.
Widget field(String label, String value, {bool isMono = false, int lines = 1, String? hint, bool obscure = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text.rich(TextSpan(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), children: [
          TextSpan(text: label),
          if (hint != null) TextSpan(text: '  $hint', style: const TextStyle(fontWeight: FontWeight.w400, color: C.muted)),
        ])),
        TextFormField(
          initialValue: value,
          maxLines: lines,
          obscureText: obscure,
          style: isMono ? mono.copyWith(fontSize: 13) : const TextStyle(fontSize: 14),
          decoration: _inputDeco,
        ),
      ],
    );

Widget dropdown(String label, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        DropdownButtonFormField<String>(
          initialValue: items.first,
          isExpanded: true,
          decoration: _inputDeco,
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 14)))],
          onChanged: (_) {},
        ),
      ],
    );

const _inputDeco = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: C.surface,
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  border: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
);

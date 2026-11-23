import 'package:flutter/material.dart';
import 'package:popoling_core/ui.dart';

/// 어두운 로그 상자의 탭 버튼.
class LogTab extends StatelessWidget {
  const LogTab(this.label, {super.key, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            backgroundColor: selected ? C.darkLine : null,
            foregroundColor: selected ? Colors.white : const Color(0xFF9AA1AD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(label),
        ),
      );
}

import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'item_status.dart';

/// 앱을 닫을 때 실행 중인 항목이 있으면 [취소]·[모두 종료하고 닫기]를 묻는다(FR-12, 기획서 v1.4).
class ExitGuard extends StatefulWidget {
  const ExitGuard({
    super.key,
    required this.navigatorKey,
    required this.stillUp,
    required this.stopEverything,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Future<List<ItemRef>> Function() stillUp;

  /// 모두 멈추고, 멈추지 못한 항목만 돌려준다.
  final Future<List<ItemResult>> Function() stopEverything;
  final Widget child;

  @override
  State<ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<ExitGuard> {
  late final AppLifecycleListener _listener;
  var _asking = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onExitRequested: _onExit);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _onExit() async {
    if (_asking) return AppExitResponse.cancel; // 이미 묻는 중이면 그 창에서 고른다
    _asking = true;
    try {
      final items = await widget.stillUp();
      final context = widget.navigatorKey.currentContext;
      if (items.isEmpty || context == null || !context.mounted) return AppExitResponse.exit;
      final exit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExitDialog(items: items, stopEverything: widget.stopEverything),
      );
      return exit ?? false ? AppExitResponse.exit : AppExitResponse.cancel;
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ExitDialog extends StatefulWidget {
  const _ExitDialog({required this.items, required this.stopEverything});

  final List<ItemRef> items;
  final Future<List<ItemResult>> Function() stopEverything;

  @override
  State<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends State<_ExitDialog> {
  var _stopping = false;
  List<String>? _failed;

  Future<void> _stopAndExit() async {
    setState(() => _stopping = true);
    List<String> failed;
    try {
      failed = [for (final r in await widget.stopEverything()) '${r.item}: ${r.reason ?? '멈추지 못했어요.'}'];
    } catch (e) {
      failed = [errorText(e)];
    }
    if (!mounted) return;
    if (failed.isEmpty) return _close(true);
    setState(() {
      _stopping = false;
      _failed = failed;
    });
  }

  void _close(bool exit) => Navigator.pop(context, exit);

  @override
  Widget build(BuildContext context) {
    final failed = _failed;
    return PopScope(
      canPop: !_stopping,
      child: CallbackShortcuts(
        bindings: {
          if (!_stopping) const SingleActivator(LogicalKeyboardKey.escape): () => _close(false),
        },
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: failed != null ? _failedBody(failed) : _stopping ? _stoppingBody() : _askBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _askBody() {
    final byProject = <String, List<String>>{};
    for (final i in widget.items) {
      byProject.putIfAbsent(i.projectId, () => []).add(i.serviceId);
    }
    return [
      _title('실행 중인 항목이 있어요'),
      const Text('포폴링을 닫기 전에 어떻게 할까요?', style: TextStyle(fontSize: 14, color: C.text2)),
      _list([for (final MapEntry(:key, :value) in byProject.entries) '$key — ${value.join(', ')}']),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
        Btn('취소', onPressed: () => _close(false)),
        // Btn 은 자동 포커스를 받지 못한다. Enter 가 기본값이 되려면 포커스가 있어야 한다.
        FilledButton(
          autofocus: true,
          onPressed: _stopAndExit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          child: const Text('모두 종료하고 닫기'),
        ),
      ]),
    ];
  }

  List<Widget> _stoppingBody() => [
        _title('종료하는 중이에요…'),
        const Text('항목이 모두 멈추면 포폴링을 닫아요.', style: TextStyle(fontSize: 14, color: C.text2)),
        const LinearProgressIndicator(),
      ];

  List<Widget> _failedBody(List<String> failed) => [
        _title('멈추지 못한 항목이 있어요'),
        _list(failed),
        const Text('그래도 닫으면 이 항목은 계속 실행될 수 있어요.', style: TextStyle(fontSize: 14, color: C.text2)),
        Btn('그래도 닫기', onPressed: () => _close(true)),
        Focus(autofocus: true, child: Btn('취소', ghost: true, onPressed: () => _close(false))), // Esc 를 받을 포커스
      ];

  static Widget _title(String text) => Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700));

  static Widget _list(List<String> lines) =>
      Text([for (final l in lines) '•  $l'].join('\n'), style: const TextStyle(fontSize: 14, height: 1.8));
}

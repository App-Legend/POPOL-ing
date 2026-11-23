import 'package:popoling_core/contracts.dart';

import '../orchestrator/runner_orchestrator.dart';

/// [RuntimeQuery] 의 진짜 구현. 포트를 쓰는 PID 가 내가 띄운 프로세스 그룹(Windows 는 Job)에 들었는지로 판단한다.
///
/// - 프로세스 항목은 설정의 `ports` 에 그 포트가 있어야 한다. 포트를 적지 않은 항목은 내 것이라고 하지 않는다.
/// - Compose 항목은 C 의 [ItemLauncher.composeOwnerOf] 에 묻는다.
class RunnerRuntimeQuery implements RuntimeQuery {
  RunnerRuntimeQuery({required this.processes, required this.launcher});

  final Iterable<LiveProcess> Function() processes;
  final ItemLauncher Function() launcher;

  @override
  Future<ItemRef?> ownerOf(PortInUse usage) async {
    try {
      if (usage.pid case final pid?) {
        for (final p in processes()) {
          if (p.service.ports.contains(usage.port) && await p.process.contains(pid)) return p.item;
        }
      }
      return await launcher().composeOwnerOf(usage.port);
    } catch (_) {
      return null; // 약속: 예외를 던지지 않고, 모르면 null
    }
  }
}

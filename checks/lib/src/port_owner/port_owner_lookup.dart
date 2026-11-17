import 'dart:io';

import 'package:ppoling_core/models.dart';

import 'macos_port_owner.dart';
import 'windows_port_owner.dart';

/// 외부 명령 실행. 테스트에서 기록된 출력으로 바꿔 끼운다.
typedef RunProcess = Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> runProcess(String executable, List<String> arguments) => Process.run(executable, arguments);

/// 이 컴퓨터에서 TCP 포트를 열어 둔(LISTEN) 프로세스를 OS 명령으로 찾는다. OS별 코드는 이 폴더에만 둔다.
abstract interface class PortOwnerLookup {
  /// 지금 OS 에 맞는 구현. 지원하지 않는 OS 면 아무것도 모른다고 답한다.
  factory PortOwnerLookup.forPlatform({RunProcess run = runProcess}) {
    if (Platform.isWindows) return WindowsPortOwner(run: run);
    if (Platform.isMacOS) return MacosPortOwner(run: run);
    return const _Unknown();
  }

  /// - [PortInUse]: 주인을 찾았다(PID·이름).
  /// - [PortFree]: 모든 프로세스를 봤는데 아무도 안 쓴다.
  /// - null: 확실히 모른다(명령 실패, 권한 때문에 남의 프로세스가 안 보임). 부르는 쪽이 다른 방법으로 확인한다.
  Future<PortUsage?> find(int port);
}

class _Unknown implements PortOwnerLookup {
  const _Unknown();

  @override
  Future<PortUsage?> find(int port) async => null;
}

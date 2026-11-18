import 'dart:async';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

import 'failure_reason.dart';
import 'port_owner/port_owner_lookup.dart';

/// [PortProbe] 진짜 구현.
///
/// [whoUses] 는 OS 명령으로 주인 PID·이름을 찾고(`port_owner/`), 그걸로 확실히 모르면
/// 직접 포트를 열어 보며 쓰는지만 확인한다(이때 PID·이름은 null). 어떤 경우에도 프로세스를 종료하지 않는다.
class SystemPortProbe implements PortProbe {
  SystemPortProbe({PortOwnerLookup? owners}) : _owners = owners ?? PortOwnerLookup.forPlatform();

  final PortOwnerLookup _owners;

  @override
  Future<PortUsage> whoUses(int port) async {
    _checkPort(port);
    return await _owners.find(port) ?? await _tryBind(port);
  }

  /// 루프백과 모든 주소에 잠깐 열어 본다. 둘 중 하나라도 이미 쓰고 있으면 실패한다.
  Future<PortUsage> _tryBind(int port) async {
    for (final address in [InternetAddress.loopbackIPv4, InternetAddress.anyIPv4]) {
      try {
        final server = await ServerSocket.bind(address, port);
        await server.close();
      } on SocketException {
        return PortInUse(port);
      }
    }
    return PortFree(port);
  }

  @override
  Future<ProbeResult> connect(int port, {String? host, Duration timeout = PortProbe.defaultTimeout}) async {
    _checkPort(port);
    final address = host ?? 'localhost';
    final target = '$address:$port';
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(address, port, timeout: timeout);
      final elapsed = watch.elapsed;
      socket.destroy(); // 연결만 확인한다. 아무것도 보내지 않는다.
      return ProbeResult(target: target, ok: true, elapsed: elapsed);
    } on SocketException catch (e) {
      return ProbeResult(target: target, ok: false, failureReason: connectFailureReason(e, watch.elapsed, timeout));
    } on TimeoutException {
      return ProbeResult(target: target, ok: false, failureReason: timedOutReason(timeout));
    }
  }
}

void _checkPort(int port) {
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', '포트 번호는 1~65535 사이여야 해요');
  }
}

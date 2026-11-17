import 'dart:async';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

/// [PortProbe] 진짜 구현. 지금은 [connect] 만 있다.
///
/// [whoUses] 는 포트를 쓰는 PID·프로그램 이름을 OS 명령(`lsof`·`netstat`)으로 찾아야 해서,
/// OS별 코드를 어디에 둘지 팀과 정한 뒤 채운다. 그 전에는 앱에 등록하지 않는다.
class SystemPortProbe implements PortProbe {
  @override
  Future<PortUsage> whoUses(int port) async {
    _checkPort(port);
    throw UnimplementedError('whoUses 는 OS별 코드 위치를 정한 뒤 구현한다.');
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
      return ProbeResult(target: target, ok: false, failureReason: _reason(e, watch.elapsed, timeout));
    } on TimeoutException {
      return ProbeResult(target: target, ok: false, failureReason: _timedOut(timeout));
    }
  }
}

void _checkPort(int port) {
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', '포트 번호는 1~65535 사이여야 해요');
  }
}

/// 연결 거부를 뜻하는 OS 오류 코드 (Linux 111, macOS 61, Windows 10061·1225).
/// Windows 는 거부돼도 약 2초 다시 시도한 뒤 1225 로 알려서, 기본 대기 시간(2초)이면 `응답 없음`이 될 수 있다.
const _refusedCodes = {111, 61, 10061, 1225};

String _reason(SocketException e, Duration elapsed, Duration timeout) {
  final message = e.message.toLowerCase();
  if (message.contains('timed out') || elapsed >= timeout) return _timedOut(timeout);
  if (message.contains('host lookup')) return '주소를 찾을 수 없음';
  if (_refusedCodes.contains(e.osError?.errorCode)) return '연결 거부';
  return '연결 실패';
}

String _timedOut(Duration timeout) {
  final seconds = timeout.inMilliseconds / 1000;
  final text = seconds == seconds.roundToDouble() ? '${seconds.round()}' : '$seconds';
  return '응답 없음 ($text초 안에 연결되지 않음)';
}

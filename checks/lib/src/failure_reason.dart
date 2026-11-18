import 'dart:io';

/// 연결 확인(`PortProbe.connect`·`HttpProbe.get`)이 화면에 보여줄 실패 이유.

/// 연결 거부를 뜻하는 OS 오류 코드 (Linux 111, macOS 61, Windows 10061·1225).
/// Windows 는 거부돼도 약 2초 다시 시도한 뒤 1225 로 알려서, 대기 시간이 2초 이하면 `응답 없음`이 될 수 있다.
const _refusedCodes = {111, 61, 10061, 1225};

String connectFailureReason(SocketException e, Duration elapsed, Duration timeout) {
  final message = e.message.toLowerCase();
  if (message.contains('timed out') || elapsed >= timeout) return timedOutReason(timeout);
  if (message.contains('host lookup')) return '주소를 찾을 수 없음';
  if (_refusedCodes.contains(e.osError?.errorCode)) return '연결 거부';
  return '연결 실패';
}

String timedOutReason(Duration timeout) {
  final seconds = timeout.inMilliseconds / 1000;
  final text = seconds == seconds.roundToDouble() ? '${seconds.round()}' : '$seconds';
  return '응답 없음 ($text초 안에 답이 없음)';
}

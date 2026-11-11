import '../models/probe.dart';

/// 포트 확인(FR-06)과 TCP 연결 확인.
///
/// - 진짜 구현: C (`checks/`)
/// - 쓰는 곳: A(시작 전 포트 확인, `type: port` 준비 조건), D(QA 의 port 검사), C(원격 연결 FR-18)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [portProbeContract] 로 확인한다.
/// - 포트 번호가 1~65535 밖이면 [ArgumentError]. 그 밖의 실패는 예외 대신 결과로 돌려준다.
/// - 프로세스를 종료하지 않는다. 누가 쓰는지 알려주기만 한다.
abstract interface class PortProbe {
  /// [connect] 의 기본 대기 시간.
  static const defaultTimeout = Duration(seconds: 2);

  /// 이 컴퓨터에서 [port] 를 누가 쓰는지. 시작 전에 부른다.
  Future<PortUsage> whoUses(int port);

  /// [host] 의 [port] 에 TCP 연결이 되는지. [host] 가 null 이면 이 컴퓨터(localhost).
  /// [timeout] 안에 연결되지 않으면 실패다.
  Future<ProbeResult> connect(int port, {String? host, Duration timeout = defaultTimeout});
}

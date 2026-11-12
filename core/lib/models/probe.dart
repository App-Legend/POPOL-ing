/// 포트 확인(FR-06)과 연결 확인(FR-10 QA, FR-18 원격 연결, 준비 조건)의 결과.
library;

/// 이 컴퓨터의 포트를 누가 쓰고 있는가. `PortProbe.whoUses` 의 결과.
sealed class PortUsage {
  const PortUsage(this.port);

  final int port;
}

/// 아무도 쓰지 않는다. 바로 시작할 수 있다.
final class PortFree extends PortUsage {
  const PortFree(super.port);
}

/// 누군가 포트를 쓰고 있다. 화면에는 `포트 사용 중`으로 보인다.
///
/// 누가 쓰는지 알아내지 못하면(권한 부족 등) [pid]·[processName] 이 null 이다.
/// 이 값만으로 프로세스를 종료하지 않는다(PID 는 재사용된다). 포폴링이 띄운 내 항목인지는
/// 실행 기록(A 의 `RuntimeQuery`)으로 판단하고, 외부 프로그램이면 이름·PID 만 보여준다.
final class PortInUse extends PortUsage {
  const PortInUse(super.port, {this.pid, this.processName});

  final int? pid;

  /// 실행 파일 이름. 예: `java`, `node.exe`
  final String? processName;
}

/// 연결 확인 한 번의 결과. TCP 연결(`PortProbe.connect`)과 HTTP 요청(`HttpProbe.get`)이 함께 쓴다.
///
/// 연결 실패는 예외가 아니라 정상적인 답이므로 [ok] 가 false 인 결과로 돌려준다.
class ProbeResult {
  const ProbeResult({required this.target, required this.ok, this.statusCode, this.elapsed, this.failureReason});

  /// 확인한 곳. QA 결과의 '대상' 칸과 같은 형식이다. 예: `GET http://localhost:8080/health`, `localhost:3306`
  final String target;

  /// 연결됐고, HTTP 면 기대한 응답 코드를 받았다.
  final bool ok;

  /// HTTP 응답 코드. TCP 확인이거나 응답을 못 받았으면 null.
  final int? statusCode;

  /// 응답 시간. 응답을 못 받았으면 null.
  final Duration? elapsed;

  /// 실패 이유. 화면에 그대로 보여줄 수 있는 짧은 문장. 예: `연결 거부`, `기대 200, 받은 500`. [ok] 면 null.
  final String? failureReason;
}

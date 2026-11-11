/// 실행 항목을 "준비 완료"로 보는 기준 (기획서 §6 준비 조건 유형).
///
/// ```yaml
/// ready:
///   type: http          # port | http | log | compose-healthy | none
///   url: http://localhost:8080/actuator/health
///   timeout: 120        # 초. 기본 60
///   interval: 1         # 초. 기본 1
/// ```
sealed class ReadyCondition {
  const ReadyCondition({this.timeout = defaultTimeout, this.interval = defaultInterval});

  static const defaultTimeout = Duration(seconds: 60);
  static const defaultInterval = Duration(seconds: 1);

  /// 이 시간 안에 준비되지 않으면 실패로 본다.
  final Duration timeout;

  /// 준비됐는지 다시 확인하는 간격.
  final Duration interval;
}

/// 포트에 TCP 연결이 되면 준비 완료. `type: port`
final class PortReady extends ReadyCondition {
  const PortReady({required this.port, this.host, super.timeout, super.interval});

  final int port;

  /// 연결할 곳. null 이면 이 컴퓨터(localhost). 원격 항목은 꼭 적는다.
  final String? host;
}

/// 주소가 기대한 상태 코드로 응답하면 준비 완료. `type: http`
final class HttpReady extends ReadyCondition {
  const HttpReady({required this.url, this.expectStatus, super.timeout, super.interval});

  final String url;

  /// 기대하는 응답 코드. null 이면 200~399 를 모두 성공으로 본다.
  final int? expectStatus;
}

/// 출력에 정규식이 나타나면 준비 완료. `type: log`
final class LogReady extends ReadyCondition {
  const LogReady({required this.pattern, super.timeout, super.interval});

  /// 정규식. 예: `Started .* in`
  final String pattern;
}

/// Compose 서비스의 healthcheck 가 healthy 면 준비 완료. `type: compose-healthy`
final class ComposeHealthyReady extends ReadyCondition {
  const ComposeHealthyReady({super.timeout, super.interval});
}

/// 시작되면 바로 준비 완료. `type: none` (ready 를 안 적었을 때의 기본값)
final class NoneReady extends ReadyCondition {
  const NoneReady({super.timeout, super.interval});
}

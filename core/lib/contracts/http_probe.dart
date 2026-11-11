import '../models/probe.dart';

/// HTTP 응답 확인.
///
/// - 진짜 구현: C (`checks/`)
/// - 쓰는 곳: A(`type: http` 준비 조건), D(QA 의 url 검사), C(원격 연결 FR-18)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [httpProbeContract] 로 확인한다.
/// - GET 을 한 번 보낸다. 리다이렉트는 따라가지 않는다(3xx 도 응답으로 본다).
/// - 연결 실패·시간 초과·잘못된 주소도 예외 대신 `ok: false` 결과로 돌려준다.
abstract interface class HttpProbe {
  /// [get] 의 기본 대기 시간.
  static const defaultTimeout = Duration(seconds: 5);

  /// [url] 에 GET 을 보낸다. [expectStatus] 와 같은 응답 코드면 성공이고,
  /// null 이면 200~399 를 모두 성공으로 본다.
  Future<ProbeResult> get(String url, {int? expectStatus, Duration timeout = defaultTimeout});
}

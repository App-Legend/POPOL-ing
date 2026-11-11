/// 기본 QA 검사 하나. ppoling.yaml 의 `checks` 목록 한 칸이다(FR-10).
///
/// ```yaml
/// checks:
///   - name: API 헬스
///     url: http://localhost:8080/actuator/health
///     expectStatus: 200
///   - name: DB 포트
///     port: 3306            # url 대신 포트만 확인할 수도 있다
///   - name: 관리자 페이지   # 주소가 없으면 QA 결과는 '설정 필요'
/// ```
class CheckConfig {
  const CheckConfig({required this.name, this.url, this.port, this.host, this.expectStatus});

  /// 화면에 보이는 검사 이름.
  final String name;

  /// HTTP 로 요청할 주소. [port] 와 함께 쓰지 않는다.
  final String? url;

  /// TCP 연결만 확인할 포트. [url] 과 함께 쓰지 않는다.
  final int? port;

  /// [port] 를 확인할 곳. null 이면 이 컴퓨터(localhost).
  final String? host;

  /// [url] 의 기대 응답 코드. null 이면 200~399 를 모두 통과로 본다.
  final int? expectStatus;

  /// 검사할 주소가 있는가. 없으면 QA 결과는 '설정 필요'다.
  bool get hasTarget => url != null || port != null;
}

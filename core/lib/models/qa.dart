/// 검사 하나의 결과. 화면 6(QA 결과)의 한 줄이다.
enum QaStatus {
  /// 통과
  passed,

  /// 실패
  failed,

  /// 설정 필요: 검사할 주소(url·port)가 없다.
  needsSetup,
}

/// 검사를 시작한 계기. 화면 6 이력 표의 '계기' 칸이다.
///
/// '전체 실행 후 자동' 검사를 넣을지는 팀이 정한 뒤 추가한다.
enum QaTrigger {
  /// 사용자가 [헬스체크]·[다시 검사]를 눌렀다.
  manual,

  /// 오래된 프로젝트 점검(FR-17)이 환경 점검·전체 실행 뒤에 돌렸다.
  staleCheck,
}

/// check 하나의 검사 결과(FR-10).
class QaResult {
  const QaResult({
    required this.name,
    required this.status,
    required this.checkedAt,
    this.target,
    this.statusCode,
    this.elapsed,
    this.failureReason,
  });

  /// check 이름. 예: `API 헬스`
  final String name;

  final QaStatus status;

  /// 검사한 때.
  final DateTime checkedAt;

  /// 검사한 곳. 예: `GET http://localhost:8080/health`, `localhost:3306`. 설정 필요면 null.
  final String? target;

  /// HTTP 응답 코드. 포트 검사거나 응답을 못 받았으면 null.
  final int? statusCode;

  /// 응답 시간. 응답을 못 받았으면 null.
  final Duration? elapsed;

  /// 실패 이유. 예: `연결 거부`, `기대 200, 받은 500`. 통과·설정 필요면 null.
  final String? failureReason;
}

/// 검사 한 번(여러 check)의 결과. 화면 6 이력 표의 한 줄이다.
class QaRun {
  const QaRun({required this.projectId, required this.startedAt, required this.trigger, required this.results});

  final String projectId;
  final DateTime startedAt;
  final QaTrigger trigger;

  /// ppoling.yaml 의 checks 와 같은 순서.
  final List<QaResult> results;

  int get passed => _count(QaStatus.passed);
  int get failed => _count(QaStatus.failed);
  int get needsSetup => _count(QaStatus.needsSetup);

  int _count(QaStatus status) => results.where((r) => r.status == status).length;
}

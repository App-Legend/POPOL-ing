import 'requirement.dart';

/// 환경 점검(FR-07) 항목 하나의 상태. 화면 5 '도구와 런타임' 표의 '상태' 칸이다.
///
/// 문제 상태는 서로 다른 안내를 보여줘야 하므로 구분한다(기획서 오류 안내 7종).
enum EnvStatus {
  /// 통과
  passed,

  /// 미설치: 명령을 찾을 수 없다. 설치 방법과 PATH 확인 방법을 안내한다.
  notInstalled,

  /// 버전 불일치: 설치는 됐지만 요구 버전 범위 밖이다.
  versionMismatch,

  /// 데몬 미실행: Docker 가 꺼져 있다. Compose 항목의 시작을 막는다.
  daemonNotRunning,

  /// 점검 실패: 버전 범위를 해석할 수 없거나, 버전 출력을 읽지 못했다.
  checkFailed,
}

/// `requires` 한 칸의 점검 결과.
class EnvCheckResult {
  const EnvCheckResult({required this.requirement, required this.status, this.foundVersion, this.message});

  /// 점검한 요구 사항. 받은 객체를 그대로 담는다.
  final Requirement requirement;

  final EnvStatus status;

  /// 지금 설치된 버전. Docker 는 데몬(서버) 버전. 미설치·데몬 미실행이면 null.
  final String? foundVersion;

  /// 덧붙일 설명. 화면에 그대로 보여줄 수 있는 문장. 통과면 보통 null.
  final String? message;
}

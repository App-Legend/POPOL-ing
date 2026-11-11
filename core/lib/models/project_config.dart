import '../src/config_reader.dart';
import 'check_config.dart';
import 'requirement.dart';
import 'service_config.dart';

/// 프로젝트 소개. 나중에 다시 봐도 뭔지 알 수 있게 남긴다(FR-15).
///
/// ```yaml
/// about:
///   summary: 동아리 행사 예약 웹서비스 (2025 캡스톤)
///   stack: [Spring Boot, React, MySQL]
///   links:
///     repo: https://github.com/example/my-team-project
///   memo: 관리자 계정은 .env 의 ADMIN_* 참고
/// ```
class About {
  const About({this.summary, this.stack = const [], this.links = const {}, this.memo});

  /// 한 줄 설명.
  final String? summary;

  /// 기술 스택 태그. 카탈로그 카드와 필터에 쓴다.
  final List<String> stack;

  /// 링크 이름 → 주소. 예: `{'repo': 'https://github.com/...'}`
  final Map<String, String> links;

  /// 자유 메모. 비밀값은 적지 않는다.
  final String? memo;
}

/// ppoling.yaml 한 개의 내용 (스키마 v1).
///
/// ```yaml
/// version: 1             # 필수. 지금은 1만 읽는다
/// name: my-team-project  # 선택
/// about: ...             # 선택. [About]
/// requires: [...]        # 선택. 환경 점검 대상. [Requirement]
/// services: [...]        # 선택. 실행 항목. [ServiceConfig]
/// checks: [...]          # 선택. 기본 QA 대상. [CheckConfig]
/// ```
///
/// 스키마 v1 에 아직 없는 것: `shell: true`(셸 문자열 실행), 키체인 비밀값 참조.
/// 팀이 정하면 추가한다(1.0 이후에도 항목 추가는 할 수 있다).
class ProjectConfig {
  const ProjectConfig({
    this.version = supportedVersion,
    this.name,
    this.about = const About(),
    this.requires = const [],
    this.services = const [],
    this.checks = const [],
  });

  /// 이 앱이 읽을 수 있는 스키마 버전.
  static const supportedVersion = 1;

  final int version;
  final String? name;
  final About about;
  final List<Requirement> requires;
  final List<ServiceConfig> services;
  final List<CheckConfig> checks;

  /// YAML 을 읽어 만든 Map 에서 설정을 만든다. YAML 파싱 자체는 부르는 쪽이 한다.
  ///
  /// 형식 문제(필수값 누락, 타입 오류, 모르는 항목 이름, 허용하지 않는 값, 프로젝트 폴더
  /// 밖을 가리키는 경로)를 끝까지 모아 [ConfigFormatException] 하나로 던진다.
  /// 항목 사이의 관계(중복 id, 없는 의존 대상, 순환 의존)는 ConfigValidator 가 검사한다.
  factory ProjectConfig.fromMap(Map<Object?, Object?> map) => readProjectConfig(map);
}

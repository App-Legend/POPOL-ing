/// 환경 점검 대상 하나. ppoling.yaml 의 `requires` 목록 한 칸이다.
///
/// ```yaml
/// requires:
///   - cli: node
///     version: ">=20"
///   - docker: true
/// ```
sealed class Requirement {
  const Requirement();
}

/// 설치돼 있어야 하는 명령줄 도구.
final class CliRequirement extends Requirement {
  const CliRequirement(this.cli, {this.version});

  /// 명령 이름. 예: `node`, `java`
  final String cli;

  /// 필요한 버전 범위. 예: `>=20`. null 이면 설치만 확인한다. 해석은 환경 점검(C)이 한다.
  final String? version;
}

/// Docker 데몬에 연결할 수 있어야 한다.
final class DockerRequirement extends Requirement {
  const DockerRequirement();
}

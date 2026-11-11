import 'config_issue.dart';

/// 포폴링 계약 함수가 던지는 예외의 공통 부모.
///
/// 팀 규칙: 계약 함수는 실패를 예외로 알린다. [message] 는 화면에 그대로 보여줄 수
/// 있는 문장으로 쓴다. 단, 설정 검사(ConfigValidator)는 문제를 한 번에 여러 개
/// 보여줘야 하므로 예외 대신 [ConfigIssue] 목록을 돌려준다.
class PpolingException implements Exception {
  const PpolingException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 등록하려는 폴더가 없을 때.
class FolderNotFoundException extends PpolingException {
  FolderNotFoundException(this.path) : super('폴더를 찾을 수 없어요: $path');

  final String path;
}

/// 이미 등록된 폴더를 다시 등록하려 할 때.
class ProjectAlreadyRegisteredException extends PpolingException {
  ProjectAlreadyRegisteredException(this.path, {required this.projectId})
      : super('이미 등록된 폴더예요: $path');

  final String path;

  /// 이미 등록된 프로젝트의 ID. 화면에서 그 프로젝트로 이동시킬 때 쓴다.
  final String projectId;
}

/// 등록되지 않은 프로젝트 ID를 받았을 때.
class ProjectNotFoundException extends PpolingException {
  ProjectNotFoundException(this.projectId) : super('등록된 프로젝트가 아니에요: $projectId');

  final String projectId;
}

/// ppoling.yaml 의 형식(필수값, 타입, 허용 값)이 잘못됐을 때. 찾은 문제를 모두 담는다.
class ConfigFormatException extends PpolingException {
  ConfigFormatException(List<ConfigIssue> issues)
      : issues = List.unmodifiable(issues),
        super('ppoling.yaml 에서 고칠 곳이 ${issues.length}군데 있어요.');

  final List<ConfigIssue> issues;
}

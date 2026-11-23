import 'config_issue.dart';
import 'llm.dart';

/// 포폴링 계약 함수가 던지는 예외의 공통 부모.
///
/// 팀 규칙: 계약 함수는 실패를 예외로 알린다. [message] 는 화면에 그대로 보여줄 수
/// 있는 문장으로 쓴다. 단, 설정 검사(ConfigValidator)는 문제를 한 번에 여러 개
/// 보여줘야 하므로 예외 대신 [ConfigIssue] 목록을 돌려준다.
class PopolingException implements Exception {
  const PopolingException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 등록하려는 폴더가 없을 때.
class FolderNotFoundException extends PopolingException {
  FolderNotFoundException(this.path) : super('폴더를 찾을 수 없어요: $path');

  final String path;
}

/// 이미 등록된 폴더를 다시 등록하려 할 때.
class ProjectAlreadyRegisteredException extends PopolingException {
  ProjectAlreadyRegisteredException(this.path, {required this.projectId})
      : super('이미 등록된 폴더예요: $path');

  final String path;

  /// 이미 등록된 프로젝트의 ID. 화면에서 그 프로젝트로 이동시킬 때 쓴다.
  final String projectId;
}

/// 등록되지 않은 프로젝트 ID를 받았을 때.
class ProjectNotFoundException extends PopolingException {
  ProjectNotFoundException(this.projectId) : super('등록된 프로젝트가 아니에요: $projectId');

  final String projectId;
}

/// popoling.yaml 의 형식(필수값, 타입, 허용 값)이 잘못됐을 때. 찾은 문제를 모두 담는다.
class ConfigFormatException extends PopolingException {
  ConfigFormatException(List<ConfigIssue> issues)
      : issues = List.unmodifiable(issues),
        super('popoling.yaml 에서 고칠 곳이 ${issues.length}군데 있어요.');

  final List<ConfigIssue> issues;
}

/// Docker 데몬에 연결할 수 없어 Compose 항목을 다룰 수 없을 때(AT-08).
class DockerNotRunningException extends PopolingException {
  DockerNotRunningException() : super('Docker 가 꺼져 있어요. Docker Desktop 을 실행한 뒤 다시 시도해 주세요.');
}

/// `docker compose` 명령이 실패했을 때. 예: compose 파일 오류, 이미지를 받지 못함.
class ComposeCommandException extends PopolingException {
  ComposeCommandException({required this.action, required this.exitCode, this.output = ''})
      : super('Compose 를 $action 못했어요 (종료 코드 $exitCode).');

  /// 하려던 일. 메시지에 그대로 들어간다. 예: `시작하지`, `멈추지`
  final String action;

  final int exitCode;

  /// 명령 출력의 마지막 부분. 원인을 보여줄 때 쓴다. `.env` 값이 섞이지 않게 가린 뒤 담는다.
  final String output;
}

/// AI(LlmClient) 호출이 실패했을 때. [failure] 로 이유를 구분한다.
class LlmException extends PopolingException {
  LlmException(this.failure) : super(_messages[failure]!);

  final LlmFailure failure;

  static const _messages = {
    LlmFailure.missingKey: 'AI를 쓰려면 API 키를 먼저 넣어 주세요.',
    LlmFailure.invalidKey: 'API 키가 맞지 않아요. 키를 다시 확인해 주세요.',
    LlmFailure.quotaExceeded: 'AI 사용량 제한을 넘었어요. 잠시 뒤 다시 시도해 주세요.',
    LlmFailure.network: 'AI 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
  };
}

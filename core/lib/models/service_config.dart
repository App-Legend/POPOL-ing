import '../src/map_writer.dart';
import 'ready_condition.dart';

/// 실행 항목 하나. ppoling.yaml 의 `services` 목록 한 칸이다.
///
/// 종류마다 하위 클래스가 있다: [ProcessService], [ComposeService], [RemoteService].
/// 종류별로 다르게 처리할 때는 `switch` 로 나눈다.
sealed class ServiceConfig {
  const ServiceConfig({required this.id, this.dependsOn = const [], this.ready = const NoneReady()});

  /// 프로젝트 안에서 겹치지 않는 이름. 영문·숫자·-·_ 만 쓴다. 예: `api`
  final String id;

  /// 이 항목보다 먼저 준비돼야 하는 항목들의 id. 전체 실행은 이 순서를 지킨다.
  final List<String> dependsOn;

  /// 준비 완료로 보는 기준.
  final ReadyCondition ready;

  /// [ProjectConfig.fromMap] 이 읽는 services 한 칸 모양으로 되돌린다. 기본값·빈 값은 뺀다.
  Map<String, Object?> toMap();

  /// 공통 항목. ready 는 기본값(NoneReady, 기본 timeout·interval)이면 뺀다.
  Map<String, Object?> _common(String type) => {
        'id': id,
        'type': type,
        if (dependsOn.isNotEmpty) 'dependsOn': List<String>.of(dependsOn),
        if (!(ready is NoneReady &&
            ready.timeout == ReadyCondition.defaultTimeout &&
            ready.interval == ReadyCondition.defaultInterval))
          'ready': ready.toMap(),
      };
}

/// 내 컴퓨터에서 명령으로 띄우는 항목. `type: process`
///
/// ```yaml
/// - id: api
///   type: process
///   cwd: ./backend
///   command: ["./gradlew", "bootRun"]
///   env: { SPRING_PROFILES_ACTIVE: local }
///   envFile: ./backend/.env
///   ports: [8080]
///   dependsOn: [db]
///   stopTimeout: 15
/// ```
final class ProcessService extends ServiceConfig {
  const ProcessService({
    required super.id,
    required this.command,
    super.dependsOn,
    super.ready,
    this.cwd = '.',
    this.env = const {},
    this.envFile,
    this.ports = const [],
    this.stopTimeout = defaultStopTimeout,
  });

  static const defaultStopTimeout = Duration(seconds: 10);

  /// 실행 파일과 인자. 셸을 거치지 않고 그대로 넘긴다. 예: `["npm", "run", "dev"]`
  final List<String> command;

  /// 명령을 실행할 폴더. 프로젝트 폴더 기준 상대 경로.
  final String cwd;

  /// 환경변수. 비밀값은 여기 쓰지 말고 [envFile] 에 둔다.
  final Map<String, String> env;

  /// 환경변수를 읽을 `.env` 파일. 프로젝트 폴더 기준 상대 경로. 값은 로그·화면에 내보내지 않는다.
  final String? envFile;

  /// 이 항목이 쓰는 포트. 시작 전에 비어 있는지 확인한다.
  final List<int> ports;

  /// 종료 신호를 보낸 뒤 이 시간을 기다리고, 그래도 살아 있으면 강제 종료한다.
  final Duration stopTimeout;

  @override
  Map<String, Object?> toMap() => {
        ..._common('process'),
        if (cwd != '.') 'cwd': cwd,
        'command': List<String>.of(command),
        if (env.isNotEmpty) 'env': Map<String, String>.of(env),
        if (envFile != null) 'envFile': envFile,
        if (ports.isNotEmpty) 'ports': List<int>.of(ports),
        if (stopTimeout != defaultStopTimeout) 'stopTimeout': durationToSeconds(stopTimeout),
      };
}

/// Docker Compose 로 띄우는 항목. `type: compose`
///
/// ```yaml
/// - id: db
///   type: compose
///   file: ./docker-compose.yml
///   services: [mysql]     # 비우면 파일 전체
/// ```
final class ComposeService extends ServiceConfig {
  const ComposeService({
    required super.id,
    required this.file,
    super.dependsOn,
    super.ready,
    this.services = const [],
  });

  /// compose 파일. 프로젝트 폴더 기준 상대 경로.
  final String file;

  /// 띄울 compose 서비스 이름. 비어 있으면 파일 전체.
  final List<String> services;

  @override
  Map<String, Object?> toMap() => {
        ..._common('compose'),
        'file': file,
        if (services.isNotEmpty) 'services': List<String>.of(services),
      };
}

/// 클라우드·배포 서버처럼 내 컴퓨터 밖에서 도는 항목. `type: remote`
///
/// 켜고 끄지 않고 [ready] 로 연결 여부만 확인한다(FR-18). [ready] 는 [HttpReady] 또는
/// host 가 있는 [PortReady] 만 쓸 수 있다.
final class RemoteService extends ServiceConfig {
  const RemoteService({required super.id, required super.ready, super.dependsOn});

  @override
  Map<String, Object?> toMap() => _common('remote');
}

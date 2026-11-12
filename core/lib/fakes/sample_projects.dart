import '../models/check_config.dart';
import '../models/project.dart';
import '../models/project_config.dart';
import '../models/ready_condition.dart';
import '../models/requirement.dart';
import '../models/service_config.dart';

/// 화면 목업(개발 홈·QA 결과)과 같은 프로젝트 5개.
/// 가짜 구현의 기본 데이터이자, 화면을 개발할 때 쓰는 예시다.
abstract final class SampleProjects {
  static final _registeredAt = DateTime(2026, 11, 1);

  /// 기획서 §7 스키마 예시 그대로인 프로젝트. QA 결과 화면의 검사 3개(통과·실패·설정 필요용)를 가진다.
  static final myTeamProject = Project(
    id: 'my-team-project',
    name: 'my-team-project',
    folderPath: '/projects/my-team-project',
    registeredAt: _registeredAt,
    config: const ProjectConfig(
      name: 'my-team-project',
      about: About(
        summary: '동아리 행사 예약 웹서비스 (2025 캡스톤)',
        stack: ['Spring Boot', 'React', 'MySQL'],
        links: {'repo': 'https://github.com/example/my-team-project'},
        memo: '관리자 계정은 .env 의 ADMIN_* 참고',
      ),
      requires: [
        CliRequirement('node', version: '>=20'),
        CliRequirement('java', version: '>=17'),
        DockerRequirement(),
      ],
      services: [
        ComposeService(
          id: 'db',
          file: './docker-compose.yml',
          services: ['mysql'],
          ready: ComposeHealthyReady(timeout: Duration(seconds: 90)),
        ),
        ProcessService(
          id: 'api',
          cwd: './backend',
          command: ['./gradlew', 'bootRun'],
          env: {'SPRING_PROFILES_ACTIVE': 'local'},
          envFile: './backend/.env',
          ports: [8080],
          dependsOn: ['db'],
          ready: HttpReady(url: 'http://localhost:8080/actuator/health', timeout: Duration(seconds: 120)),
          stopTimeout: Duration(seconds: 15),
        ),
        ProcessService(
          id: 'web',
          cwd: './frontend',
          command: ['npm', 'run', 'dev'],
          ports: [5173],
          dependsOn: ['api'],
          ready: PortReady(port: 5173),
        ),
        RemoteService(
          id: 'storage',
          ready: HttpReady(url: 'https://storage.my-team.dev/health', timeout: Duration(seconds: 10)),
        ),
      ],
      checks: [
        CheckConfig(name: 'API 헬스', url: 'http://localhost:8080/actuator/health', expectStatus: 200),
        CheckConfig(name: '프론트 메인', url: 'http://localhost:5173'),
        CheckConfig(name: '관리자 페이지'),
      ],
    ),
  );

  static final ppoling = Project(
    id: 'ppoling',
    name: 'ppoling',
    folderPath: '/projects/ppoling',
    registeredAt: _registeredAt,
    config: const ProjectConfig(
      about: About(summary: '포폴링 데스크톱 앱', stack: ['Flutter']),
      requires: [CliRequirement('flutter')],
      services: [
        ProcessService(id: 'app', cwd: './app', command: ['flutter', 'run', '-d', 'windows']),
      ],
    ),
  );

  static final weatherBot = Project(
    id: 'weather-bot',
    name: 'weather-bot',
    folderPath: '/projects/weather-bot',
    registeredAt: _registeredAt,
    config: const ProjectConfig(
      about: About(summary: '날씨 알림 디스코드 봇', stack: ['Node.js']),
      requires: [CliRequirement('node', version: '>=18')],
      services: [
        ProcessService(id: 'bot', command: ['node', 'index.js'], envFile: './.env'),
      ],
    ),
  );

  /// web 이 5173 포트를 쓴다(AT-17 포트 충돌 예시).
  static final shopClone = Project(
    id: 'shop-clone',
    name: 'shop-clone',
    folderPath: '/projects/shop-clone',
    registeredAt: _registeredAt,
    config: const ProjectConfig(
      about: About(summary: '쇼핑몰 클론 코딩', stack: ['Next.js', 'PostgreSQL']),
      requires: [CliRequirement('node', version: '>=20'), DockerRequirement()],
      services: [
        ComposeService(id: 'db', file: './docker-compose.yml'),
        ProcessService(
          id: 'web',
          command: ['npm', 'run', 'dev'],
          ports: [5173],
          dependsOn: ['db'],
          ready: PortReady(port: 5173),
        ),
      ],
      checks: [CheckConfig(name: '메인 페이지', url: 'http://localhost:5173')],
    ),
  );

  /// 설명과 실행 항목이 아직 없는 프로젝트(빈 상태 화면 확인용).
  static final algoStudy = Project(
    id: 'algo-study',
    name: 'algo-study',
    folderPath: '/projects/algo-study',
    registeredAt: _registeredAt,
    config: const ProjectConfig(about: About(stack: ['Python'])),
  );

  static final all = [myTeamProject, ppoling, weatherBot, shopClone, algoStudy];
}

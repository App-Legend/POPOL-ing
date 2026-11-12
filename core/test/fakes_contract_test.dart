import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/models.dart';
import 'package:ppoling_core/testing.dart';

/// 가짜 구현이 약속 테스트를 통과하는지 확인한다.
/// 진짜 구현도 각자 기능 폴더에서 같은 묶음을 돌린다.
void main() {
  group('FakeProjectRepository', () {
    projectRepositoryContract(() async => ProjectRepositoryFixture(
          repository: FakeProjectRepository(existingFolders: ['/projects/alpha', r'C:\projects\Beta Project']),
          existingFolder: '/projects/alpha',
          anotherFolder: r'C:\projects\Beta Project',
          missingFolder: '/projects/missing',
        ));
  });

  group('FakeConfigValidator', () {
    configValidatorContract(() => FakeConfigValidator());
  });

  group('FakeQaRunner', () {
    qaRunnerContract(() async => QaRunnerFixture(
          runner: FakeQaRunner(FakeProjectRepository.withSamples()),
          projectId: SampleProjects.myTeamProject.id,
          checks: SampleProjects.myTeamProject.config!.checks,
        ));
  });

  group('FakeLlmClient', () {
    llmClientContract(() async => LlmClientFixture(
          configured: FakeLlmClient(),
          unconfigured: FakeLlmClient(configured: false),
        ));
  });

  group('FakeLogExcerpt', () {
    const log = ['DB_PASSWORD=hunter2', 'Started', 'Connection refused: localhost:3306'];
    logExcerptContract(() async => LogExcerptFixture(
          excerpt: FakeLogExcerpt(FakeProjectRepository.withSamples(),
              logs: {('my-team-project', 'api'): log}, secrets: {'hunter2'}),
          projectId: 'my-team-project',
          serviceId: 'api',
          logLines: log,
          secret: 'hunter2',
        ));
  });

  group('FakeEnvDiff', () {
    envDiffContract(() async => EnvDiffFixture(
          diff: FakeEnvDiff(FakeProjectRepository.withSamples(), changes: {
            'my-team-project': const [EnvChange(name: 'node', before: '20.11.0', after: '22.3.0')],
          }),
          changedProjectId: 'my-team-project',
          changedNames: {'node'},
          noRecordProjectId: 'ppoling',
        ));
  });

  group('FakePortProbe', () {
    portProbeContract(() async => PortProbeFixture(
          probe: FakePortProbe(inUse: [const PortInUse(8080, pid: 4321, processName: 'java')]),
          freePort: 5173,
          busyPort: 8080,
        ));
  });

  group('FakeHttpProbe', () {
    httpProbeContract(() async => HttpProbeFixture(
          probe: FakeHttpProbe(responses: {'http://localhost:8080/health': 200, 'http://localhost:8080/boom': 500}),
          okUrl: 'http://localhost:8080/health',
          errorUrl: 'http://localhost:8080/boom',
          downUrl: 'http://localhost:9/health',
        ));
  });

  group('FakeEnvChecker', () {
    envCheckerContract(() async => EnvCheckerFixture(
          checker: FakeEnvChecker(installed: {'node': '22.3.0'}),
          installedCli: 'node',
          dockerRunning: true,
        ));
  });

  group('FakeEnvChecker (Docker 꺼짐)', () {
    envCheckerContract(() async => EnvCheckerFixture(
          checker: FakeEnvChecker(installed: {'node': '22.3.0'}, dockerRunning: false),
          installedCli: 'node',
          dockerRunning: false,
        ));
  });

  group('가짜 구현만의 동작', () {
    test('FakeLlmClient 는 보낸 prompt 를 남기고, 키가 없으면 보내지 않는다', () async {
      final ai = FakeLlmClient(failWith: LlmFailure.quotaExceeded);
      await expectLater(ai.complete('a'), throwsA(isA<LlmException>()));
      ai.configured = false;
      await expectLater(ai.complete('b'), throwsA(isA<LlmException>()));
      expect(ai.sent, ['a']);
    });

    test('FakeEnvChecker 는 버전 범위를 규칙대로 비교한다', () async {
      final env = FakeEnvChecker(installed: {'node': 'v20.11.1'});
      Future<EnvStatus> status(String range) async =>
          (await env.check([CliRequirement('node', version: range)])).single.status;
      expect(await status('>=20'), EnvStatus.passed);
      expect(await status('20'), EnvStatus.passed);
      expect(await status('=20.11'), EnvStatus.passed);
      expect(await status('>=17 <20'), EnvStatus.versionMismatch);
      expect(await status('>20.11.1'), EnvStatus.versionMismatch);
      expect(await status('<=20.11.1'), EnvStatus.passed);
      expect(await status('18'), EnvStatus.versionMismatch);
    });

    test('FakePortProbe 는 포트를 비우면 바로 PortFree 가 되고, 원격은 넣은 주소만 연결된다', () async {
      final ports = FakePortProbe(inUse: [const PortInUse(5173)], reachableRemotes: {'db.example.com:3306'});
      ports.inUse.remove(5173);
      expect(await ports.whoUses(5173), isA<PortFree>());
      expect((await ports.connect(3306, host: 'db.example.com')).ok, isTrue);
      expect((await ports.connect(3307, host: 'db.example.com')).ok, isFalse);
    });

    test('FakeProjectRepository 는 폴더 이름으로 ID 를 만들고, 겹치면 숫자를 붙인다', () async {
      final repo = FakeProjectRepository(existingFolders: [r'C:\work\My App', '/home/me/my-app', '/x/포폴링']);
      expect((await repo.addProject(r'C:\work\My App')).id, 'my-app');
      expect((await repo.addProject('/home/me/my-app')).id, 'my-app-2');
      expect((await repo.addProject('/x/포폴링')).id, 'project');
    });

    test('FakeProjectRepository 는 addFolder 로 넣은 ppoling.yaml 을 등록 때 읽는다', () async {
      final repo = FakeProjectRepository();
      repo.addFolder('/projects/new', config: const ProjectConfig(about: About(summary: '새 프로젝트')));
      final project = await repo.addProject('/projects/new');
      expect(project.about.summary, '새 프로젝트');
    });

    test('FakeQaRunner 는 목업처럼 통과·실패·설정 필요를 꾸민다', () async {
      final qa = FakeQaRunner(FakeProjectRepository.withSamples(), failing: {'프론트 메인'});
      final run = await qa.runChecks('my-team-project');
      expect([for (final r in run.results) r.status], [QaStatus.passed, QaStatus.failed, QaStatus.needsSetup]);
      expect((run.passed, run.failed, run.needsSetup), (1, 1, 1));
      expect(run.results.first.statusCode, 200);
    });

    test('FakeConfigValidator 는 넣어 둔 문제를 돌려주고, 받은 설정을 기록한다', () {
      const issue = ConfigIssue(path: 'services[0].id', message: '겹쳐요');
      final validator = FakeConfigValidator(issues: [issue]);
      expect(validator.validate(const ProjectConfig()), [issue]);
      expect(validator.validated, hasLength(1));
    });
  });
}

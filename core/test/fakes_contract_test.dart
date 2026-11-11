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

  group('가짜 구현만의 동작', () {
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

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/src/failure_analysis.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';

ItemRef ref(String id, [String projectId = 'my-team-project']) => ItemRef(projectId: projectId, serviceId: id);

final api = ItemResult(item: ref('api'), outcome: ItemOutcome.failed, reason: '시작하자마자 종료됐어요 (종료 코드 1).', exitCode: 1);
final run = RunSummary(
  projectId: 'my-team-project',
  startedAt: DateTime(2026, 11, 22, 14),
  finishedAt: DateTime(2026, 11, 22, 14, 0, 30),
  items: [
    ItemResult(item: ref('db'), outcome: ItemOutcome.ok),
    ItemResult(item: ref('storage'), outcome: ItemOutcome.ok),
    api,
    ItemResult(item: ref('web'), outcome: ItemOutcome.skipped, reason: 'api 가 실패해서 시작하지 않았어요.'),
  ],
);
const nodeChange = EnvChange(name: 'node', before: '20.11.0', after: '22.3.0');
const apiLogs = ['Starting backend', 'Error: The module was compiled against a different Node.js version'];

Future<ServiceConfig> sample(String id) async =>
    (await FakeProjectRepository.withSamples().getProject('my-team-project')).config!.services.firstWhere((s) => s.id == id);

void main() {
  group('보낼 글', () {
    test('실패 이유·실행 설정·다른 항목·환경 차이·로그에 번호', () async {
      final input = FailureAnalysisInput(item: api, run: run, service: await sample('api'), envChanges: [nodeChange], logs: apiLogs);
      expect(input.prompt, '''
[실패한 항목] api · 내 컴퓨터에서 실행 · 11/22 14:00 전체 실행
#R 시작하자마자 종료됐어요 (종료 코드 1).
[실행 설정] 명령 ./gradlew bootRun · 폴더 ./backend · 포트 8080 · .env 파일 씀(내용은 보내지 않음)
  준비 조건 HTTP /actuator/health 응답(120초 안) · 먼저 떠야 하는 항목 db
[같은 실행의 다른 항목] db 성공 · storage 성공 · web 건너뜀(api 가 실패해서 시작하지 않았어요.)
[환경 차이] 마지막 성공 실행과 비교
#E1 node 20.11.0 → 22.3.0
[로그] api 마지막 2줄
#L1 Starting backend
#L2 Error: The module was compiled against a different Node.js version''');
      expect(input.prompt, isNot(contains('SPRING_PROFILES_ACTIVE')));
      expect(input.prompt, isNot(contains('localhost')));
    });

    test('compose 항목', () async {
      final db = ItemResult(item: ref('db'), outcome: ItemOutcome.failed, reason: '준비 시간(90초)을 넘겼어요.');
      final prompt = FailureAnalysisInput(item: db, run: run, service: await sample('db'), envChanges: const []).prompt;
      expect(prompt, contains('[실패한 항목] db · Docker Compose · 11/22 14:00 전체 실행'));
      expect(prompt, contains('[실행 설정] compose 파일 ./docker-compose.yml · 서비스 mysql\n  준비 조건 compose healthy(90초 안)\n'));
    });

    test('원격 항목은 호스트를 빼고 준비 조건만', () async {
      final storage = ItemResult(item: ref('storage'), outcome: ItemOutcome.failed, reason: '연결할 수 없어요.');
      final prompt = FailureAnalysisInput(item: storage, run: run, service: await sample('storage'), envChanges: const []).prompt;
      expect(prompt, contains('[실패한 항목] storage · 원격 연결 · 11/22 14:00 전체 실행'));
      expect(prompt, contains('[실행 설정] 원격 항목(켜고 끄지 않고 연결만 확인)\n  준비 조건 HTTP /health 응답(10초 안)\n'));
      expect(prompt, isNot(contains('storage.my-team.dev')));
    });

    test('공백이 든 인자는 따옴표, 포트 준비 조건은 호스트를 빼고', () {
      const bot = ProcessService(
        id: 'api',
        command: [r'C:\Program Files\nodejs\node.exe', 'index.js'],
        ready: PortReady(port: 5432, host: 'db.internal'),
      );
      final prompt = FailureAnalysisInput(item: api, run: run, service: bot, envChanges: const []).prompt;
      expect(prompt, contains(r'명령 "C:\Program Files\nodejs\node.exe" index.js'));
      expect(prompt, contains('  준비 조건 포트 5432 연결(60초 안)\n'));
      expect(prompt, isNot(contains('db.internal')));
    });

    test('준비 조건 없음과 로그 준비 조건', () {
      final none = FailureAnalysisInput(item: api, run: run, service: const ProcessService(id: 'api', command: ['a'])).prompt;
      expect(none, contains('  준비 조건 없음\n'));
      final log = FailureAnalysisInput(
        item: api,
        run: run,
        service: const ProcessService(id: 'api', command: ['a'], ready: LogReady(pattern: 'Started .* in')),
      ).prompt;
      expect(log, contains('  준비 조건 로그에 "Started .* in" 출력(60초 안)\n'));
    });

    test('설정에서 못 찾은 항목', () {
      final prompt = FailureAnalysisInput(item: api, run: run).prompt;
      expect(prompt, startsWith('[실패한 항목] api · 11/22 14:00 전체 실행\n'));
      expect(prompt, contains('[실행 설정] 설정에서 이 항목을 찾지 못했어요.\n'));
    });

    test('환경 차이 네 경우', () {
      String env(FailureAnalysisInput i) => i.prompt.split('\n').firstWhere((l) => l.startsWith('[환경 차이]'));
      expect(env(FailureAnalysisInput(item: api, run: run, envAvailable: false)), '[환경 차이] 환경 비교를 아직 쓸 수 없어요.');
      expect(env(FailureAnalysisInput(item: api, run: run)), '[환경 차이] 마지막 성공 실행 기록이 없어요.');
      expect(env(FailureAnalysisInput(item: api, run: run, envChanges: const [])), '[환경 차이] 마지막 성공 실행과 달라진 것이 없어요.');
      final added = FailureAnalysisInput(item: api, run: run, envChanges: const [EnvChange(name: 'docker', after: '24.0.7')]).prompt;
      expect(added, contains('[환경 차이] 마지막 성공 실행과 비교\n#E1 docker 없음 → 24.0.7\n'));
    });

    test('로그 못 읽음·없음·긴 줄', () {
      expect(FailureAnalysisInput(item: api, run: run).prompt, endsWith('[로그] 로그를 읽지 못했어요.'));
      expect(FailureAnalysisInput(item: api, run: run, logs: const []).prompt, endsWith('[로그] 남은 로그가 없어요.'));
      final long = FailureAnalysisInput(item: api, run: run, logs: ['x' * 400]);
      expect(long.logs!.single.length, 301);
      expect(long.logs!.single, endsWith('…'));
      expect(long.prompt, contains('#L1 ${'x' * 300}…'));
    });

    test('다른 항목이 없으면 그 줄을 뺀다', () {
      final alone = RunSummary(projectId: 'my-team-project', startedAt: run.startedAt, finishedAt: run.finishedAt, items: [api]);
      expect(FailureAnalysisInput(item: api, run: alone).prompt, isNot(contains('[같은 실행의 다른 항목]')));
    });
  });

  test('failureReasonText', () {
    expect(failureReasonText(api), '시작하자마자 종료됐어요 (종료 코드 1).');
    expect(
      failureReasonText(ItemResult(item: ref('api'), outcome: ItemOutcome.failed, reason: '준비 시간(120초)을 넘겼어요.', exitCode: 143)),
      '준비 시간(120초)을 넘겼어요. · 종료 코드 143',
    );
    expect(failureReasonText(ItemResult(item: ref('api'), outcome: ItemOutcome.failed, exitCode: 2)), '종료 코드 2');
    expect(failureReasonText(ItemResult(item: ref('api'), outcome: ItemOutcome.failed)), '이유를 알 수 없어요.');
  });

  test('envChangeLabel', () {
    expect(envChangeLabel(nodeChange), 'node 20.11.0 → 22.3.0');
    expect(envChangeLabel(const EnvChange(name: 'java', before: '17')), 'java 17 → 없음');
  });

  group('collect', () {
    final projects = FakeProjectRepository.withSamples();

    test('가짜 로그·환경 차이를 모은다', () async {
      final input = await FailureAnalysisInput.collect(
        item: api,
        run: run,
        projects: projects,
        logs: FakeLogExcerpt(projects, logs: {('my-team-project', 'api'): apiLogs}),
        envDiff: FakeEnvDiff(projects, changes: {'my-team-project': [nodeChange]}),
      );
      expect(input.service?.id, 'api');
      expect(input.logs, apiLogs);
      expect(input.envAvailable, isTrue);
      expect(input.envChanges?.single.name, 'node');
    });

    test('EnvDiff·LogExcerpt 가 없으면 못 읽음으로', () async {
      final input = await FailureAnalysisInput.collect(item: api, run: run, projects: projects);
      expect(input.service?.id, 'api');
      expect(input.logs, isNull);
      expect(input.envAvailable, isFalse);
    });

    test('지워진 프로젝트여도 던지지 않는다', () async {
      final gone = ItemResult(item: ref('api', 'gone'), outcome: ItemOutcome.failed);
      final goneRun = RunSummary(projectId: 'gone', startedAt: run.startedAt, finishedAt: run.finishedAt, items: [gone]);
      final input = await FailureAnalysisInput.collect(
        item: gone,
        run: goneRun,
        projects: projects,
        logs: FakeLogExcerpt(projects),
        envDiff: FakeEnvDiff(projects),
      );
      expect(input.service, isNull);
      expect(input.logs, isNull);
      expect(input.envAvailable, isFalse);
    });
  });
}

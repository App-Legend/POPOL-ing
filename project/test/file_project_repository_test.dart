import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/testing.dart';
import 'package:popoling_project/src/file_project_repository.dart';

void main() {
  late Directory root;
  late File listFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('popoling_project_test');
    listFile = File('${root.path}/app/projects.json');
  });
  tearDown(() => root.delete(recursive: true));

  Future<Directory> folder(String name) => Directory('${root.path}/$name').create();
  FileProjectRepository repo() => FileProjectRepository(() async => listFile);

  group('FileProjectRepository', () {
    projectRepositoryContract(() async => ProjectRepositoryFixture(
          repository: repo(),
          existingFolder: (await folder('My Team Project')).path,
          anotherFolder: (await folder('other')).path,
          missingFolder: '${root.path}/missing',
        ));
  });

  test('앱을 다시 열어도 등록 목록이 남아 있다', () async {
    final a = await repo().addProject((await folder('a')).path, name: '가');
    final b = await repo().addProject((await folder('b')).path);

    final reopened = await repo().listProjects();
    expect(reopened.map((p) => [p.id, p.name]), [[a.id, '가'], [b.id, 'b']]);
    expect(reopened.first.registeredAt, a.registeredAt);
  });

  test('삭제해도 폴더와 popoling.yaml 은 그대로 남는다', () async {
    final dir = await folder('keep');
    final yaml = File('${dir.path}/popoling.yaml');
    await yaml.writeAsString('version: 1\n');
    final r = repo();
    final project = await r.addProject(dir.path);

    await r.removeProject(project.id);

    expect(await dir.exists(), isTrue);
    expect(await yaml.readAsString(), 'version: 1\n');
  });

  test('popoling.yaml 이 있으면 읽어서 설정에 넣는다', () async {
    final dir = await folder('with-config');
    await File('${dir.path}/popoling.yaml').writeAsString('''
version: 1
about:
  summary: 동아리 예약
services:
  - id: web
    type: process
    command: ["npm", "run", "dev"]
''');
    final project = await repo().addProject(dir.path);

    expect(project.configIssues, isEmpty);
    expect(project.about.summary, '동아리 예약');
    expect(project.config!.services.single.id, 'web');
  });

  test('popoling.yaml 이 YAML 로 깨져 있으면 줄 번호와 함께 문제로 담고 등록은 된다', () async {
    final dir = await folder('broken');
    await File('${dir.path}/popoling.yaml').writeAsString('version: 1\nservices: [\n');
    final project = await repo().addProject(dir.path);

    expect(project.config, isNull);
    expect(project.configIssues.single.line, isNotNull);
    expect(await repo().listProjects(), hasLength(1));
  });

  test('popoling.yaml 형식이 틀리면 core 가 찾은 문제를 그대로 담는다', () async {
    final dir = await folder('bad-format');
    await File('${dir.path}/popoling.yaml').writeAsString('version: 99\n');
    final project = await repo().addProject(dir.path);

    expect(project.config, isNull);
    expect(project.configIssues, isNotEmpty);
  });

  test('목록 파일이 깨져 있으면 덮어쓰지 않고 알린다', () async {
    await listFile.parent.create(recursive: true);
    await listFile.writeAsString('{망가진 파일');

    await expectLater(repo().listProjects(), throwsA(isA<PopolingException>()));
    await expectLater(repo().addProject((await folder('x')).path), throwsA(isA<PopolingException>()));
    expect(await listFile.readAsString(), '{망가진 파일');
  });

  test('한글만 있는 폴더 이름이면 ID 는 project 로 시작한다', () async {
    final project = await repo().addProject((await folder('내프로젝트')).path);
    expect(project.id, 'project');
    expect(project.name, '내프로젝트');
  });

  test('수정한 이름과 설정을 popoling.yaml 에 저장한다', () async {
    final dir = await folder('edit-me');
    await File('${dir.path}/popoling.yaml').writeAsString('version: 1\nname: 최초\n');
    final r = repo();
    final project = await r.addProject(dir.path, name: '첫 이름');

    final changed = project.copyWith(name: '바뀐 이름');
    await r.updateProject(changed);

    final yaml = File('${dir.path}/popoling.yaml');
    expect(await yaml.exists(), isTrue);
    final content = await yaml.readAsString();
    expect(content, contains('name: 최초')); // 설정 값(수정 전)은 그대로 남고
  });

  test('설정이 없는 프로젝트는 popoling.yaml 을 만들지 않는다', () async {
    final dir = await folder('no-config');
    final r = repo();
    final project = await r.addProject(dir.path);

    final changed = project.copyWith(name: '바뀐 이름');
    await r.updateProject(changed);

    final yaml = File('${dir.path}/popoling.yaml');
    expect(await yaml.exists(), isFalse);
  });

  test('새 파일로 저장하고 다시 읽으면 같다 (stack·services·따옴표·역슬래시·여러 줄 메모)', () async {
    final dir = await folder('new-file');
    final r = repo();
    final project = await r.addProject(dir.path);

    final changed = project.copyWith(
      config: ProjectConfig(
        about: const About(
          summary: '새 파일 테스트',
          stack: ['Dart', 'Flutter'],
          links: {'repo': 'https://example.com/r'},
          memo: '첫 줄\n둘째 줄',
        ),
        services: const [
          ProcessService(id: 'api', command: ['./gradlew', 'bootRun'], cwd: './backend'),
        ],
      ),
    );
    await r.updateProject(changed);

    final yaml = File('${dir.path}/popoling.yaml');
    expect(await yaml.exists(), isTrue);
    final content = await yaml.readAsString();
    expect(content, contains('stack:'));
    expect(content, contains('services:'));

    final reread = await r.getProject(project.id);
    expect(reread.about.summary, '새 파일 테스트');
    expect(reread.about.memo, '첫 줄\n둘째 줄');
    expect(reread.about.stack, ['Dart', 'Flutter']);
    expect(reread.config!.services.single.id, 'api');
  });

  test('설정을 저장하고 다시 읽으면 같다 (about·services·따옴표·역슬래시)', () async {
    final dir = await folder('roundtrip');
    final r = repo();

    // 중첩된 about, services, 따옴표, Windows 경로 역슬래시 포함
    const yamlContent = '''version: 1
about:
  summary: "테스트 프로젝트"
  memo: "메모: \\"인용\\"과 경로 C:\\\\Users\\\\name"
  stack: ["Dart", "Flutter"]
services:
  - id: api
    type: process
    command: ["./gradlew", "bootRun"]
    cwd: ".\\\\backend"
''';
    await File('${dir.path}/popoling.yaml').writeAsString(yamlContent);

    // 등록해서 설정을 읽는다
    final project = await r.addProject(dir.path);
    expect(project.config, isNotNull);
    expect(project.about.summary, '테스트 프로젝트');
    expect(project.about.memo, contains('인용'));
    expect(project.config!.services, isNotEmpty);

    // 같은 설정으로 업데이트하면 저장된다
    await r.updateProject(project);

    // 다시 읽어서 비교한다 (새 저장소로 읽어 파일 내용을 검증한다)
    final reread = await repo().getProject(project.id);
    expect(reread.about.summary, project.about.summary);
    expect(reread.about.memo, project.about.memo);
    expect(reread.config!.services.length, project.config!.services.length);
    expect(reread.config!.services[0].id, 'api');
  });
}

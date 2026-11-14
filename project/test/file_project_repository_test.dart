import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/models.dart';
import 'package:ppoling_core/testing.dart';
import 'package:ppoling_project/src/file_project_repository.dart';

void main() {
  late Directory root;
  late File listFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ppoling_project_test');
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

  test('삭제해도 폴더와 ppoling.yaml 은 그대로 남는다', () async {
    final dir = await folder('keep');
    final yaml = File('${dir.path}/ppoling.yaml');
    await yaml.writeAsString('version: 1\n');
    final r = repo();
    final project = await r.addProject(dir.path);

    await r.removeProject(project.id);

    expect(await dir.exists(), isTrue);
    expect(await yaml.readAsString(), 'version: 1\n');
  });

  test('ppoling.yaml 이 있으면 읽어서 설정에 넣는다', () async {
    final dir = await folder('with-config');
    await File('${dir.path}/ppoling.yaml').writeAsString('''
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

  test('ppoling.yaml 이 YAML 로 깨져 있으면 줄 번호와 함께 문제로 담고 등록은 된다', () async {
    final dir = await folder('broken');
    await File('${dir.path}/ppoling.yaml').writeAsString('version: 1\nservices: [\n');
    final project = await repo().addProject(dir.path);

    expect(project.config, isNull);
    expect(project.configIssues.single.line, isNotNull);
    expect(await repo().listProjects(), hasLength(1));
  });

  test('ppoling.yaml 형식이 틀리면 core 가 찾은 문제를 그대로 담는다', () async {
    final dir = await folder('bad-format');
    await File('${dir.path}/ppoling.yaml').writeAsString('version: 99\n');
    final project = await repo().addProject(dir.path);

    expect(project.config, isNull);
    expect(project.configIssues, isNotEmpty);
  });

  test('목록 파일이 깨져 있으면 덮어쓰지 않고 알린다', () async {
    await listFile.parent.create(recursive: true);
    await listFile.writeAsString('{망가진 파일');

    await expectLater(repo().listProjects(), throwsA(isA<PpolingException>()));
    await expectLater(repo().addProject((await folder('x')).path), throwsA(isA<PpolingException>()));
    expect(await listFile.readAsString(), '{망가진 파일');
  });

  test('한글만 있는 폴더 이름이면 ID 는 project 로 시작한다', () async {
    final project = await repo().addProject((await folder('내프로젝트')).path);
    expect(project.id, 'project');
    expect(project.name, '내프로젝트');
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../contracts/project_repository.dart';
import '../models/errors.dart';
import '../models/project.dart';

/// [projectRepositoryContract] 가 테스트마다 받는 준비물.
class ProjectRepositoryFixture {
  ProjectRepositoryFixture({
    required this.repository,
    required this.existingFolder,
    required this.anotherFolder,
    required this.missingFolder,
  });

  /// 아무 프로젝트도 등록되지 않은 저장소.
  final ProjectRepository repository;

  /// 있는 폴더 두 개. ppoling.yaml 은 없어야 한다.
  final String existingFolder;
  final String anotherFolder;

  /// 없는 폴더.
  final String missingFolder;
}

/// [ProjectRepository] 구현이 계약을 지키는지 확인하는 테스트 묶음.
///
/// 가짜 구현과 진짜 구현이 같은 묶음을 통과해야 한다. [setUp] 은 테스트마다 불린다.
/// ```dart
/// group('YamlProjectRepository', () {
///   projectRepositoryContract(() async {
///     final dir = await Directory.systemTemp.createTemp();
///     ...
///     return ProjectRepositoryFixture(repository: ..., existingFolder: ..., ...);
///   });
/// });
/// ```
/// 폴더와 ppoling.yaml 을 지우지 않는지는 파일을 다루는 진짜 구현의 테스트에서 따로 확인한다.
void projectRepositoryContract(Future<ProjectRepositoryFixture> Function() setUp) {
  String folderName(String path) => path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;

  test('처음에는 목록이 비어 있다', () async {
    final f = await setUp();
    expect(await f.repository.listProjects(), isEmpty);
  });

  test('폴더를 등록하면 목록에 나오고, 이름을 주지 않으면 폴더 이름을 쓴다', () async {
    final f = await setUp();
    final project = await f.repository.addProject(f.existingFolder);

    expect(project.folderPath, f.existingFolder);
    expect(project.name, folderName(f.existingFolder));
    expect(project.category, ProjectCategory.dev);
    expect((await f.repository.listProjects()).map((p) => p.id), [project.id]);
  });

  test('이름을 주면 그 이름을 쓴다', () async {
    final f = await setUp();
    final project = await f.repository.addProject(f.existingFolder, name: '우리 팀 프로젝트');
    expect(project.name, '우리 팀 프로젝트');
  });

  test('ID 는 소문자·숫자·- 만 쓰고, 프로젝트마다 다르다', () async {
    final f = await setUp();
    final a = await f.repository.addProject(f.existingFolder);
    final b = await f.repository.addProject(f.anotherFolder);

    expect(Project.idPattern.hasMatch(a.id), isTrue, reason: a.id);
    expect(Project.idPattern.hasMatch(b.id), isTrue, reason: b.id);
    expect(a.id, isNot(b.id));
  });

  test('목록은 등록한 순서대로다', () async {
    final f = await setUp();
    final a = await f.repository.addProject(f.existingFolder);
    final b = await f.repository.addProject(f.anotherFolder);
    expect((await f.repository.listProjects()).map((p) => p.id), [a.id, b.id]);
  });

  test('없는 폴더를 등록하면 FolderNotFoundException', () async {
    final f = await setUp();
    await expectLater(f.repository.addProject(f.missingFolder), throwsA(isA<FolderNotFoundException>()));
    expect(await f.repository.listProjects(), isEmpty);
  });

  test('같은 폴더를 두 번 등록하면 ProjectAlreadyRegisteredException', () async {
    final f = await setUp();
    final first = await f.repository.addProject(f.existingFolder);
    await expectLater(
      f.repository.addProject(f.existingFolder),
      throwsA(isA<ProjectAlreadyRegisteredException>().having((e) => e.projectId, 'projectId', first.id)),
    );
  });

  test('getProject 는 등록한 프로젝트를 돌려주고, 없는 ID 면 ProjectNotFoundException', () async {
    final f = await setUp();
    final project = await f.repository.addProject(f.existingFolder);

    expect((await f.repository.getProject(project.id)).folderPath, f.existingFolder);
    await expectLater(f.repository.getProject('no-such-project'), throwsA(isA<ProjectNotFoundException>()));
  });

  test('updateProject 는 이름을 바꾸지만 ID·폴더·등록 시각은 그대로 둔다', () async {
    final f = await setUp();
    final original = await f.repository.addProject(f.existingFolder);

    final updated = await f.repository.updateProject(Project(
      id: original.id,
      name: '새 이름',
      folderPath: f.anotherFolder, // 바꾸려 해도 무시돼야 한다
      registeredAt: DateTime(2000),
    ));

    expect(updated.name, '새 이름');
    expect(updated.id, original.id);
    expect(updated.folderPath, f.existingFolder);
    expect(updated.registeredAt, original.registeredAt);
    expect((await f.repository.getProject(original.id)).name, '새 이름');
  });

  test('없는 프로젝트를 updateProject 하면 ProjectNotFoundException', () async {
    final f = await setUp();
    await expectLater(
      f.repository.updateProject(Project(id: 'no-such-project', name: 'x', folderPath: f.existingFolder, registeredAt: DateTime(2000))),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });

  test('removeProject 는 목록에서 빼고, 같은 폴더를 다시 등록할 수 있다', () async {
    final f = await setUp();
    final project = await f.repository.addProject(f.existingFolder);

    await f.repository.removeProject(project.id);

    expect(await f.repository.listProjects(), isEmpty);
    await expectLater(f.repository.getProject(project.id), throwsA(isA<ProjectNotFoundException>()));
    final again = await f.repository.addProject(f.existingFolder);
    expect(again.folderPath, f.existingFolder);
  });

  test('없는 프로젝트를 removeProject 하면 ProjectNotFoundException', () async {
    final f = await setUp();
    await expectLater(f.repository.removeProject('no-such-project'), throwsA(isA<ProjectNotFoundException>()));
  });

  test('watchProjects 는 지금 목록부터 보내고, 바뀔 때마다 다시 보낸다', () async {
    final f = await setUp();
    final seen = <List<String>>[];
    final subscription = f.repository.watchProjects().listen((list) => seen.add([for (final p in list) p.id]));
    await Future<void>.delayed(Duration.zero);

    final a = await f.repository.addProject(f.existingFolder);
    await Future<void>.delayed(Duration.zero);
    await f.repository.removeProject(a.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(seen.first, isEmpty);
    expect(seen, contains(equals([a.id])));
    expect(seen.last, isEmpty);
  });
}

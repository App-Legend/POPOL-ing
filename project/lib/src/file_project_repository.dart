import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';
import 'package:yaml/yaml.dart';

/// [ProjectRepository] 의 진짜 구현.
///
/// 등록 목록(ID·이름·폴더·등록 시각)은 앱 데이터 폴더의 JSON 파일 하나에 두고,
/// 각 프로젝트의 설정은 그 폴더의 ppoling.yaml 에서 읽는다. 폴더와 ppoling.yaml 은 지우지 않는다.
class FileProjectRepository implements ProjectRepository {
  /// [listFile] 은 등록 목록 파일을 돌려준다. 처음 쓸 때 한 번만 부른다.
  FileProjectRepository(this._listFile, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const configFileName = 'ppoling.yaml';

  final Future<File> Function() _listFile;
  final DateTime Function() _clock;
  final List<StreamController<List<Project>>> _watchers = [];
  Future<List<Project>>? _loading;

  @override
  Future<List<Project>> listProjects() async => List.unmodifiable(await _projects());

  @override
  Stream<List<Project>> watchProjects() {
    late final StreamController<List<Project>> controller;
    controller = StreamController(
      onListen: () {
        // 먼저 등록해 첫 목록을 읽는 사이의 변경도 놓치지 않는다.
        _watchers.add(controller);
        listProjects().then(controller.add, onError: controller.addError);
      },
      onCancel: () => _watchers.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<Project> getProject(String id) async {
    final projects = await _projects();
    return projects[_indexOf(projects, id)];
  }

  @override
  Future<Project> addProject(String folderPath, {String? name}) async {
    final projects = await _projects();
    if (!await Directory(folderPath).exists()) {
      throw FolderNotFoundException(folderPath);
    }
    for (final p in projects) {
      if (p.folderPath == folderPath) {
        throw ProjectAlreadyRegisteredException(folderPath, projectId: p.id);
      }
    }
    final folderName = _folderName(folderPath);
    final project = await _withConfig(Project(
      id: _newId(projects, folderName),
      name: (name == null || name.trim().isEmpty) ? folderName : name.trim(),
      folderPath: folderPath,
      registeredAt: _clock(),
    ));
    await _save([...projects, project]);
    projects.add(project);
    _notify(projects);
    return project;
  }

  @override
  Future<Project> updateProject(Project project) async {
    final projects = await _projects();
    final i = _indexOf(projects, project.id);
    // shortcut: 설정은 메모리에만 바꾸고 ppoling.yaml 에는 아직 쓰지 않는다. core 1.0 의 toMap() 이 dev 에 들어오면 yaml_edit 로 저장한다.
    final updated = projects[i].copyWith(name: project.name, config: project.config);
    final next = [...projects]..[i] = updated;
    await _save(next);
    projects[i] = updated;
    _notify(projects);
    return updated;
  }

  @override
  Future<void> removeProject(String id) async {
    final projects = await _projects();
    final i = _indexOf(projects, id);
    await _save([...projects]..removeAt(i)); // 목록 파일에서만 뺀다. 폴더는 건드리지 않는다.
    projects.removeAt(i);
    _notify(projects);
  }

  Future<List<Project>> _projects() => _loading ??= _load();

  Future<List<Project>> _load() async {
    final file = await _listFile();
    if (!await file.exists()) {
      return [];
    }
    final List<Object?> raw;
    try {
      raw = jsonDecode(await file.readAsString()) as List<Object?>;
    } on FormatException {
      // 덮어쓰면 등록 목록을 잃으므로 고치지 않고 알린다.
      throw PpolingException('등록한 프로젝트 목록 파일을 읽지 못했어요: ${file.path}');
    } on TypeError {
      throw PpolingException('등록한 프로젝트 목록 파일을 읽지 못했어요: ${file.path}');
    }
    return [
      for (final item in raw.cast<Map<String, Object?>>())
        await _withConfig(Project(
          id: item['id']! as String,
          name: item['name']! as String,
          folderPath: item['folderPath']! as String,
          registeredAt: DateTime.parse(item['registeredAt']! as String),
        )),
    ];
  }

  /// 임시 파일에 다 쓴 뒤 바꿔 끼워, 쓰다가 멈춰도 기존 목록이 깨지지 않게 한다.
  Future<void> _save(List<Project> projects) async {
    final file = await _listFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode([
      for (final p in projects)
        {'id': p.id, 'name': p.name, 'folderPath': p.folderPath, 'registeredAt': p.registeredAt.toIso8601String()},
    ]), flush: true);
    await temp.rename(file.path);
  }

  /// 폴더의 ppoling.yaml 을 읽어 붙인다. 없으면 설정 없음, 형식이 틀리면 문제 목록에 담는다(등록은 된다).
  Future<Project> _withConfig(Project project) async {
    final file = File('${project.folderPath}${Platform.pathSeparator}$configFileName');
    if (!await file.exists()) {
      return project;
    }
    try {
      final doc = loadYaml(await file.readAsString(), sourceUrl: file.uri);
      if (doc is! Map) {
        return project.copyWith(configIssues: const [
          ConfigIssue(path: '', message: 'ppoling.yaml 의 맨 위는 "이름: 값" 형태여야 해요.'),
        ]);
      }
      return project.copyWith(config: ProjectConfig.fromMap(doc));
    } on YamlException catch (e) {
      return project.copyWith(configIssues: [
        ConfigIssue(path: '', message: 'ppoling.yaml 을 읽지 못했어요: ${e.message}', line: e.span == null ? null : e.span!.start.line + 1),
      ]);
    } on ConfigFormatException catch (e) {
      return project.copyWith(configIssues: e.issues);
    } on FileSystemException catch (e) {
      return project.copyWith(configIssues: [
        ConfigIssue(path: '', message: 'ppoling.yaml 을 열지 못했어요: ${e.message}'),
      ]);
    }
  }

  void _notify(List<Project> projects) {
    final snapshot = List<Project>.unmodifiable(projects);
    for (final watcher in [..._watchers]) {
      watcher.add(snapshot);
    }
  }

  static int _indexOf(List<Project> projects, String id) {
    final i = projects.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw ProjectNotFoundException(id);
    }
    return i;
  }

  /// 폴더 이름으로 ID 를 만든다. 예: 'My Team Project' → 'my-team-project'. 겹치면 -2, -3 을 붙인다.
  static String _newId(List<Project> projects, String folderName) {
    var base = folderName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) {
      base = 'project'; // 한글만 있는 폴더 이름 등
    }
    var id = base;
    for (var n = 2; projects.any((p) => p.id == id); n++) {
      id = '$base-$n';
    }
    return id;
  }

  static String _folderName(String path) {
    final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:popoling_core/contracts.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// [ProjectRepository] 의 진짜 구현.
///
/// 등록 목록(ID·이름·폴더·등록 시각)은 앱 데이터 폴더의 JSON 파일 하나에 두고,
/// 각 프로젝트의 설정은 그 폴더의 popoling.yaml 에서 읽는다. 폴더와 popoling.yaml 은 지우지 않는다.
class FileProjectRepository implements ProjectRepository {
  /// [listFile] 은 등록 목록 파일을 돌려준다. 처음 쓸 때 한 번만 부른다.
  FileProjectRepository(this._listFile, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const configFileName = 'popoling.yaml';

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
    final project = await withFolderConfig(Project(
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
    final before = projects[i];
    if (project.config != null && before.configIssues.isNotEmpty) {
      // 읽지 못한 설정 위에 새 설정을 쓰면 services 등 원래 내용이 지워진다. 파일을 먼저 고치게 한다.
      throw PopolingException('popoling.yaml 에 문제가 있어 저장하지 않았어요. 파일을 먼저 고쳐 주세요.');
    }
    final updated = before.copyWith(name: project.name, config: project.config);

    // 설정 파일을 먼저 저장하고, 성공하면 목록 파일을 바꾼다. 설정 저장이 실패하면 목록은 바꾸지 않는다.
    await _saveConfig(before.config, updated);
    final next = [...projects]..[i] = updated;
    await _save(next);
    projects[i] = updated;
    _notify(projects);
    return updated;
  }

  /// 수정한 설정을 그 폴더의 popoling.yaml 에 저장한다. 설정이 없으면 쓰지 않는다.
  /// 원자적 저장: 임시 파일에 다 쓴 뒤 바꿔 끼워, 쓰다가 멈춰도 원본을 잃지 않는다.
  /// 기존 파일이 있으면 [before] 와 달라진 값만 고쳐 주석·형식·모르는 값을 그대로 둔다.
  Future<void> _saveConfig(ProjectConfig? before, Project project) async {
    final config = project.config;
    if (config == null) return;
    final file = File('${project.folderPath}${Platform.pathSeparator}$configFileName');
    await file.parent.create(recursive: true);

    final exists = await file.exists();
    final doc = YamlEditor(exists ? await file.readAsString() : '');
    if (exists && before != null) {
      _applyChanges(doc, const [], before.toMap(), config.toMap());
    } else {
      doc.update(const [], config.toMap()); // 새 파일은 빈 문서에서 시작해 여러 줄 YAML 이 된다
    }
    final content = doc.toString();

    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      if (await temp.exists()) await temp.delete(); // 지우다 실패해 원래 오류를 가리지 않게
      rethrow;
    }
  }

  /// [before] 와 [after] 가 다른 곳만 [doc] 에 고친다. 맵은 키마다 내려가고, 목록·값은 통째로 바꾼다.
  static void _applyChanges(YamlEditor doc, List<Object> path, Object? before, Object? after) {
    if (before is Map && after is Map) {
      for (final key in {...before.keys, ...after.keys}) {
        final at = [...path, key as Object];
        final inFile = _hasKey(doc, path, key);
        if (!after.containsKey(key)) {
          if (inFile) doc.remove(at);
        } else if (!inFile) {
          doc.update(at, after[key]);
        } else {
          _applyChanges(doc, at, before[key], after[key]);
        }
      }
    } else if (!_same(before, after)) {
      doc.update(path, after);
    }
  }

  static bool _hasKey(YamlEditor doc, List<Object> path, Object key) {
    final parent = doc.parseAt(path, orElse: () => wrapAsYamlNode(null));
    return parent is YamlMap && parent.containsKey(key);
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    if (a is List && b is List) return a.length == b.length && [for (var i = 0; i < a.length; i++) i].every((i) => _same(a[i], b[i]));
    return a == b;
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
      throw PopolingException('등록한 프로젝트 목록 파일을 읽지 못했어요: ${file.path}');
    } on TypeError {
      throw PopolingException('등록한 프로젝트 목록 파일을 읽지 못했어요: ${file.path}');
    }
    return [
      for (final item in raw.cast<Map<String, Object?>>())
        await withFolderConfig(Project(
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

  /// 폴더의 popoling.yaml 을 읽어 붙인다. 없으면 설정 없음, 형식이 틀리면 문제 목록에 담는다(등록은 된다).
  /// 프로젝트 추가 화면이 등록 전에 실행할 명령을 보여 줄 때도 쓴다.
  static Future<Project> withFolderConfig(Project project) async {
    final file = File('${project.folderPath}${Platform.pathSeparator}$configFileName');
    if (!await file.exists()) {
      return project;
    }
    try {
      final doc = loadYaml(await file.readAsString(), sourceUrl: file.uri);
      if (doc is! Map) {
        return project.copyWith(configIssues: const [
          ConfigIssue(path: '', message: 'popoling.yaml 의 맨 위는 "이름: 값" 형태여야 해요.'),
        ]);
      }
      return project.copyWith(config: ProjectConfig.fromMap(doc));
    } on YamlException catch (e) {
      return project.copyWith(configIssues: [
        ConfigIssue(path: '', message: 'popoling.yaml 을 읽지 못했어요: ${e.message}', line: e.span == null ? null : e.span!.start.line + 1),
      ]);
    } on ConfigFormatException catch (e) {
      return project.copyWith(configIssues: e.issues);
    } on FileSystemException catch (e) {
      return project.copyWith(configIssues: [
        ConfigIssue(path: '', message: 'popoling.yaml 을 열지 못했어요: ${e.message}'),
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

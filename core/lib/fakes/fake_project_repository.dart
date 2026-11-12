import 'dart:async';

import '../contracts/project_repository.dart';
import '../models/errors.dart';
import '../models/project.dart';
import '../models/project_config.dart';
import 'sample_projects.dart';

/// [ProjectRepository] 의 가짜 구현. 파일을 읽거나 쓰지 않고 메모리에만 둔다.
///
/// 진짜 폴더 대신 [existingFolders] 에 적은 경로만 "있는 폴더"로 친다.
/// ```dart
/// final repo = FakeProjectRepository.withSamples();   // 목업과 같은 5개
/// final empty = FakeProjectRepository(existingFolders: ['/projects/new']);
/// ```
class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository({
    Iterable<Project> projects = const [],
    Iterable<String> existingFolders = const [],
    Map<String, ProjectConfig> configFiles = const {},
    DateTime Function()? clock,
  })  : _projects = [...projects],
        _folders = {...existingFolders, for (final p in projects) p.folderPath},
        _configFiles = {...configFiles},
        _clock = clock ?? DateTime.now;

  /// 목업 화면과 같은 프로젝트 5개가 등록된 상태로 시작한다.
  factory FakeProjectRepository.withSamples({Iterable<String> existingFolders = const []}) =>
      FakeProjectRepository(projects: SampleProjects.all, existingFolders: existingFolders);

  final List<Project> _projects;
  final Set<String> _folders;
  final Map<String, ProjectConfig> _configFiles;
  final DateTime Function() _clock;
  final List<StreamController<List<Project>>> _watchers = [];

  /// "있는 폴더"를 더한다. [config] 를 주면 그 폴더에 ppoling.yaml 이 있는 것으로 친다.
  void addFolder(String path, {ProjectConfig? config}) {
    _folders.add(path);
    if (config != null) {
      _configFiles[path] = config;
    }
  }

  @override
  Future<List<Project>> listProjects() async => _snapshot();

  @override
  Stream<List<Project>> watchProjects() {
    late final StreamController<List<Project>> controller;
    controller = StreamController(
      onListen: () {
        controller.add(_snapshot());
        _watchers.add(controller);
      },
      onCancel: () => _watchers.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<Project> getProject(String id) async => _projects[_indexOf(id)];

  @override
  Future<Project> addProject(String folderPath, {String? name}) async {
    if (!_folders.contains(folderPath)) {
      throw FolderNotFoundException(folderPath);
    }
    for (final p in _projects) {
      if (p.folderPath == folderPath) {
        throw ProjectAlreadyRegisteredException(folderPath, projectId: p.id);
      }
    }
    final folderName = _folderName(folderPath);
    final project = Project(
      id: _newId(folderName),
      name: (name == null || name.trim().isEmpty) ? folderName : name.trim(),
      folderPath: folderPath,
      registeredAt: _clock(),
      config: _configFiles[folderPath],
    );
    _projects.add(project);
    _notify();
    return project;
  }

  @override
  Future<Project> updateProject(Project project) async {
    final i = _indexOf(project.id);
    final updated = _projects[i].copyWith(name: project.name, config: project.config);
    _projects[i] = updated;
    final config = updated.config;
    if (config != null) {
      _configFiles[updated.folderPath] = config; // ppoling.yaml 에 저장한 것으로 친다.
    }
    _notify();
    return updated;
  }

  @override
  Future<void> removeProject(String id) async {
    _projects.removeAt(_indexOf(id)); // 목록에서만 뺀다. "폴더"는 그대로 남는다.
    _notify();
  }

  int _indexOf(String id) {
    final i = _projects.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw ProjectNotFoundException(id);
    }
    return i;
  }

  List<Project> _snapshot() => List.unmodifiable(_projects);

  void _notify() {
    for (final watcher in [..._watchers]) {
      watcher.add(_snapshot());
    }
  }

  /// 폴더 이름으로 ID 를 만든다. 예: 'My Team Project' → 'my-team-project'. 겹치면 -2, -3 을 붙인다.
  String _newId(String folderName) {
    var base = folderName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) {
      base = 'project';
    }
    var id = base;
    for (var n = 2; _projects.any((p) => p.id == id); n++) {
      id = '$base-$n';
    }
    return id;
  }

  static String _folderName(String path) {
    final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}

import 'dart:io';

import 'package:popoling_core/contracts.dart';

import 'git_adapter.dart';

/// [FileHistory] 의 진짜 구현. 프로젝트 폴더 안 파일만 Git 으로 읽는다.
class RunnerFileHistory implements FileHistory {
  RunnerFileHistory({required this.projects, required this.git});

  final ProjectRepository Function() projects;
  final GitAdapter git;

  @override
  Future<FileCommit?> lastCommit(String projectId, String path) async {
    final relative = _relative(path);
    final project = await projects().getProject(projectId); // 없으면 ProjectNotFoundException
    if (!_existsInside(project.folderPath, relative)) return null;
    return git.lastCommit(project.folderPath, relative);
  }

  /// `/` 로 이은 상대 경로. 절대 경로·`..`·빈 경로는 [ArgumentError].
  static String _relative(String path) {
    final absolute = path.startsWith('/') || path.startsWith(r'\') || RegExp(r'^[A-Za-z]:').hasMatch(path);
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty && p != '.').toList();
    if (absolute || parts.isEmpty || parts.contains('..')) {
      throw ArgumentError.value(path, 'path', '프로젝트 폴더 안의 상대 경로여야 해요');
    }
    return parts.join('/');
  }

  /// 파일이 있고, 링크를 따라가도 프로젝트 폴더 안이다.
  static bool _existsInside(String folder, String relative) {
    try {
      final root = Directory(folder).resolveSymbolicLinksSync();
      final file = File('$root${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
      if (!file.existsSync()) return false;
      return file.resolveSymbolicLinksSync().startsWith('$root${Platform.pathSeparator}');
    } on FileSystemException {
      return false;
    }
  }
}

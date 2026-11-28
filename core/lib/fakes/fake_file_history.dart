import '../contracts/file_history.dart';
import '../contracts/project_repository.dart';
import '../models/file_commit.dart';

/// [FileHistory] 의 가짜 구현. [commits] 에 넣어 둔 커밋을 돌려준다. 키의 경로는 `/` 로 쓴다.
/// ```dart
/// final history = FakeFileHistory(FakeProjectRepository.withSamples(), commits: {
///   ('my-team-project', 'popoling.yaml'): FileCommit(
///       shortHash: '4d6153a', author: '민지', committedAt: DateTime(2026, 11, 27, 14, 2), subject: 'api 포트 8080 으로'),
/// });
/// ```
class FakeFileHistory implements FileHistory {
  FakeFileHistory(this._projects, {Map<(String, String), FileCommit> commits = const {}}) : _commits = {...commits};

  final ProjectRepository _projects;
  final Map<(String, String), FileCommit> _commits;

  @override
  Future<FileCommit?> lastCommit(String projectId, String path) async {
    final key = _relativeInside(path);
    await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    return _commits[(projectId, key)];
  }
}

/// 프로젝트 폴더 기준 상대 경로를 `/` 로 이은 모양으로. 폴더 밖을 가리키면 [ArgumentError].
String _relativeInside(String path) {
  final absolute = path.startsWith('/') || path.startsWith(r'\') || RegExp(r'^[A-Za-z]:').hasMatch(path);
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty && p != '.').toList();
  if (absolute || parts.isEmpty || parts.contains('..')) {
    throw ArgumentError.value(path, 'path', '프로젝트 폴더 안의 상대 경로여야 해요');
  }
  return parts.join('/');
}

import '../contracts/log_excerpt.dart';
import '../contracts/project_repository.dart';

/// [LogExcerpt] 의 가짜 구현. [logs] 에 넣어 둔 줄을 돌려주고, [secrets] 는 `****` 로 가린다.
/// ```dart
/// final logs = FakeLogExcerpt(FakeProjectRepository.withSamples(), logs: {
///   ('my-team-project', 'api'): ['Started', 'DB_PASSWORD=hunter2', 'Connection refused'],
/// }, secrets: {'hunter2'});
/// ```
class FakeLogExcerpt implements LogExcerpt {
  FakeLogExcerpt(this._projects, {Map<(String, String), List<String>> logs = const {}, Set<String> secrets = const {}})
      : _logs = {...logs},
        _secrets = {...secrets};

  final ProjectRepository _projects;
  final Map<(String, String), List<String>> _logs;
  final Set<String> _secrets;

  @override
  Future<List<String>> tail(String projectId, String serviceId, {int lines = 50}) async {
    await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    final all = _logs[(projectId, serviceId)] ?? const <String>[];
    final start = all.length > lines ? all.length - lines : 0;
    return List.unmodifiable([for (final line in all.skip(start)) _mask(line)]);
  }

  String _mask(String line) => _secrets.fold(line, (l, secret) => l.replaceAll(secret, '****'));
}

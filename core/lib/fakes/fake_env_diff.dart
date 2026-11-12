import '../contracts/env_diff.dart';
import '../contracts/project_repository.dart';
import '../models/env_change.dart';

/// [EnvDiff] 의 가짜 구현. [changes] 에 없는 프로젝트는 성공 기록이 없는 것(null)으로 친다.
/// ```dart
/// final diff = FakeEnvDiff(FakeProjectRepository.withSamples(), changes: {
///   'my-team-project': [EnvChange(name: 'node', before: '20.11.0', after: '22.3.0')],
/// });
/// ```
class FakeEnvDiff implements EnvDiff {
  FakeEnvDiff(this._projects, {Map<String, List<EnvChange>> changes = const {}}) : _changes = {...changes};

  final ProjectRepository _projects;
  final Map<String, List<EnvChange>> _changes;

  @override
  Future<List<EnvChange>?> sinceLastSuccess(String projectId) async {
    await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    final changes = _changes[projectId];
    return changes == null ? null : List.unmodifiable(changes);
  }
}

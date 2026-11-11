import '../contracts/project_repository.dart';
import '../contracts/qa_runner.dart';
import '../models/check_config.dart';
import '../models/qa.dart';

/// [QaRunner] 의 가짜 구현. 실제로 요청을 보내지 않는다.
///
/// 프로젝트의 checks 를 읽어, 주소가 없으면 '설정 필요', [failing] 에 든 이름이면 '실패',
/// 나머지는 '통과'로 꾸민다. 이력은 메모리에만 둔다.
/// ```dart
/// final qa = FakeQaRunner(FakeProjectRepository.withSamples(), failing: {'프론트 메인'});
/// final run = await qa.runChecks('my-team-project');   // 통과 1 · 실패 1 · 설정 필요 1
/// ```
class FakeQaRunner implements QaRunner {
  FakeQaRunner(this._projects, {Set<String> failing = const {}, DateTime Function()? clock})
      : failing = {...failing},
        _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final DateTime Function() _clock;
  final Map<String, List<QaRun>> _history = {};

  /// 실패로 꾸밀 check 이름. 테스트 중에 바꿔도 된다.
  final Set<String> failing;

  @override
  Future<QaRun> runChecks(String projectId, {QaTrigger trigger = QaTrigger.manual}) async {
    final project = await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    final startedAt = _clock();
    final checks = project.config?.checks ?? const <CheckConfig>[];
    final run = QaRun(
      projectId: projectId,
      startedAt: startedAt,
      trigger: trigger,
      results: List.unmodifiable([for (final check in checks) _pretend(check, startedAt)]),
    );
    _history.putIfAbsent(projectId, () => []).insert(0, run);
    return run;
  }

  @override
  Future<List<QaRun>> history(String projectId) async => List.unmodifiable(_history[projectId] ?? const <QaRun>[]);

  QaResult _pretend(CheckConfig check, DateTime at) {
    if (!check.hasTarget) {
      return QaResult(name: check.name, status: QaStatus.needsSetup, checkedAt: at);
    }
    final url = check.url;
    final target = url != null ? 'GET $url' : '${check.host ?? 'localhost'}:${check.port}';
    if (failing.contains(check.name)) {
      return QaResult(name: check.name, status: QaStatus.failed, checkedAt: at, target: target, failureReason: '연결 거부');
    }
    return QaResult(
      name: check.name,
      status: QaStatus.passed,
      checkedAt: at,
      target: target,
      statusCode: url != null ? (check.expectStatus ?? 200) : null,
      elapsed: const Duration(milliseconds: 84),
    );
  }
}

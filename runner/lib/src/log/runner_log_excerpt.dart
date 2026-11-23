import 'package:popoling_core/contracts.dart';

import 'log_store.dart';

/// [LogExcerpt] 의 진짜 구현. 중계가 쓴 로그 끝부분을 줄 앞의 시각·`out`/`err` 를 떼고 돌려준다.
///
/// `.env` 값은 중계가 쓸 때 이미 가렸다. 실행마다 들어가는 `--- 시작 … ---` 줄은 그대로 둔다.
class RunnerLogExcerpt implements LogExcerpt {
  RunnerLogExcerpt({required this.projects, required this.logs});

  final ProjectRepository Function() projects;
  final LogStore logs;

  static final _prefix = RegExp(r'^\S+ (?:out|err) \| ');

  @override
  Future<List<String>> tail(String projectId, String serviceId, {int lines = 50}) async {
    await projects().getProject(projectId); // 없으면 ProjectNotFoundException
    final item = ItemRef(projectId: projectId, serviceId: serviceId);
    return [for (final line in await logs.tail(item, lines: lines)) line.replaceFirst(_prefix, '')];
  }
}

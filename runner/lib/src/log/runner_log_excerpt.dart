import 'dart:async';

import 'package:ppoling_core/contracts.dart';

import 'log_store.dart';

/// [LogExcerpt] 의 진짜 구현. [LogStore] 가 쓴 로그 끝부분을 줄 앞의 시각·`out`/`err` 를 떼고 돌려준다.
///
/// `.env` 값은 [LogStore] 가 쓸 때 이미 가렸다. 실행마다 들어가는 `--- 시작 … ---` 줄은 그대로 둔다.
class RunnerLogExcerpt implements LogExcerpt {
  RunnerLogExcerpt({required this.projects, required this.logs, this.wait = const Duration(seconds: 2)});

  final ProjectRepository Function() projects;
  final LogStore logs;

  /// 기록이 다 써지길 기다리는 최대 시간. 아직 실행 중인 항목은 기록이 끝나지 않으므로 이만큼만 기다린다.
  final Duration wait;

  static final _prefix = RegExp(r'^\S+ (?:out|err) \| ');

  @override
  Future<List<String>> tail(String projectId, String serviceId, {int lines = 50}) async {
    await projects().getProject(projectId); // 없으면 ProjectNotFoundException
    final item = ItemRef(projectId: projectId, serviceId: serviceId);
    await logs.idle(item).timeout(wait, onTimeout: () {});
    return [for (final line in await logs.tail(item, lines: lines)) line.replaceFirst(_prefix, '')];
  }
}

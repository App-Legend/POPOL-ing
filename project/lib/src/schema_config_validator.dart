import 'package:ppoling_core/contracts.dart';

/// [ConfigValidator] 의 진짜 구현. 실행 항목끼리의 관계(중복 id, 없는 의존 대상, 순환 의존)를 찾는다.
class SchemaConfigValidator implements ConfigValidator {
  const SchemaConfigValidator();

  @override
  List<ConfigIssue> validate(ProjectConfig config) {
    final services = config.services;
    final issues = <ConfigIssue>[];

    // id → 처음 나온 위치. 겹치면 뒤에 나온 쪽을 알린다.
    final indexOf = <String, int>{};
    for (var i = 0; i < services.length; i++) {
      final id = services[i].id;
      final first = indexOf[id];
      if (first != null) {
        issues.add(ConfigIssue(
          path: 'services[$i].id',
          message: '${first + 1}번째 항목과 이름이 같아요: $id. 다른 이름으로 바꿔 주세요.',
        ));
      } else {
        indexOf[id] = i;
      }
    }

    for (var i = 0; i < services.length; i++) {
      final deps = services[i].dependsOn;
      for (var j = 0; j < deps.length; j++) {
        if (!indexOf.containsKey(deps[j])) {
          issues.add(ConfigIssue(
            path: 'services[$i].dependsOn[$j]',
            message: '먼저 실행할 항목으로 적은 ${deps[j]} 항목이 없어요. 이름을 확인해 주세요.',
          ));
        }
      }
    }

    // 깊이 우선으로 따라가다 지금 따라가는 길 위의 항목을 다시 만나면 순환이다.
    final cycleOf = <int, String>{};
    final visiting = <int>[];
    final done = <int>{};
    void visit(int i) {
      visiting.add(i);
      for (final dep in services[i].dependsOn) {
        final k = indexOf[dep];
        if (k == null || done.contains(k)) continue;
        final at = visiting.indexOf(k);
        if (at >= 0) {
          final cycle = visiting.sublist(at);
          final route = [for (final c in cycle) services[c].id, dep].join(' → ');
          for (final c in cycle) {
            cycleOf.putIfAbsent(c, () => route);
          }
        } else {
          visit(k);
        }
      }
      visiting.removeLast();
      done.add(i);
    }

    for (final i in indexOf.values) {
      if (!done.contains(i)) visit(i);
    }
    for (final i in cycleOf.keys.toList()..sort()) {
      issues.add(ConfigIssue(
        path: 'services[$i].dependsOn',
        message: '항목끼리 서로 먼저 실행되기를 기다려서 시작할 수 없어요(${cycleOf[i]}). 이 중 한 곳의 먼저 실행할 항목을 빼 주세요.',
      ));
    }
    return issues;
  }
}

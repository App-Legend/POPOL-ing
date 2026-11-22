import 'package:popoling_core/models.dart';

/// 의존하는 항목이 앞에 오도록 줄 세운다(전체 실행 순서. 전체 종료는 이 역순).
/// 없는 의존 대상은 무시하고, 순환은 설정 검증이 막으므로 남으면 그대로 뒤에 붙인다.
List<ServiceConfig> inStartOrder(List<ServiceConfig> services) {
  final ids = {for (final s in services) s.id};
  final done = <String>{};
  final order = <ServiceConfig>[];
  var rest = [...services];
  while (rest.isNotEmpty) {
    final next = rest.where((s) => s.dependsOn.every((d) => done.contains(d) || !ids.contains(d))).toList();
    if (next.isEmpty) return order..addAll(rest);
    order.addAll(next);
    done.addAll(next.map((s) => s.id));
    rest = rest.where((s) => !done.contains(s.id)).toList();
  }
  return order;
}

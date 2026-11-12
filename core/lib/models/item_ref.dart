/// 프로젝트의 실행 항목 하나를 가리키는 ID. 화면에 보여줄 이름은 `ProjectRepository` 에서 찾는다.
final class ItemRef {
  const ItemRef({required this.projectId, required this.serviceId});

  final String projectId;
  final String serviceId;

  @override
  bool operator ==(Object other) => other is ItemRef && other.projectId == projectId && other.serviceId == serviceId;

  @override
  int get hashCode => Object.hash(projectId, serviceId);

  @override
  String toString() => '$projectId / $serviceId';
}

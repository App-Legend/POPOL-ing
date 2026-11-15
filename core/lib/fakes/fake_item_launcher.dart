import '../contracts/item_launcher.dart';
import '../contracts/project_repository.dart';
import '../models/errors.dart';
import '../models/item_ref.dart';
import '../models/launch.dart';
import '../models/probe.dart';
import '../models/ready_condition.dart';
import '../models/service_config.dart';

/// [ItemLauncher] 의 가짜 구현. 실제로 Docker 를 부르거나 연결하지 않는다.
///
/// - Compose: 시작하면 `services` 마다 실행 중인 컨테이너를 하나씩 꾸민다. `services` 가 비어 있으면
///   항목 id 를 서비스 이름으로 쓴다. 열어 둔 포트는 [ports] 에서 서비스 이름으로 찾는다.
/// - 원격: [reachable] 에 든 항목 id 만 연결된다.
/// - [dockerRunning]·[reachable] 은 테스트 중에 바꿔도 된다(예: Docker 끄기, 원격 끊기).
/// ```dart
/// final launcher = FakeItemLauncher(FakeProjectRepository.withSamples(), ports: {'mysql': [3306]});
/// await launcher.start('my-team-project', db);   // ComposeStatus, running
/// await launcher.composeOwnerOf(3306);           // my-team-project / db
/// ```
class FakeItemLauncher implements ItemLauncher {
  FakeItemLauncher(
    this._projects, {
    Map<String, List<int>> ports = const {},
    Set<String> reachable = const {},
    this.dockerRunning = true,
  })  : ports = {...ports},
        reachable = {...reachable};

  final ProjectRepository _projects;
  final Map<ItemRef, List<ContainerStatus>> _running = {};

  /// compose 서비스 이름 → 열어 둘 포트.
  final Map<String, List<int>> ports;

  /// 연결되는 원격 항목 id.
  final Set<String> reachable;

  bool dockerRunning;

  @override
  Future<LaunchStatus> start(String projectId, ServiceConfig service) async {
    await _projects.getProject(projectId); // 없으면 ProjectNotFoundException
    switch (service) {
      case ProcessService():
        throw _processError(service);
      case RemoteService():
        return _remote(service);
      case ComposeService():
        _checkDocker();
        final names = service.services.isEmpty ? [service.id] : service.services;
        _running[ItemRef(projectId: projectId, serviceId: service.id)] = [
          for (final name in names)
            ContainerStatus(
              service: name,
              name: 'ppoling-$projectId-$name-1',
              state: ContainerState.running,
              ports: List.unmodifiable(ports[name] ?? const <int>[]),
            ),
        ];
        return _compose(projectId, service);
    }
  }

  @override
  Future<void> stop(String projectId, ServiceConfig service) async {
    await _projects.getProject(projectId);
    switch (service) {
      case ProcessService():
        throw _processError(service);
      case RemoteService():
        return;
      case ComposeService():
        _checkDocker();
        _running.remove(ItemRef(projectId: projectId, serviceId: service.id));
    }
  }

  @override
  Future<LaunchStatus> status(String projectId, ServiceConfig service) async {
    await _projects.getProject(projectId);
    switch (service) {
      case ProcessService():
        throw _processError(service);
      case RemoteService():
        return _remote(service);
      case ComposeService():
        _checkDocker();
        return _compose(projectId, service);
    }
  }

  @override
  Stream<String> logs(String projectId, ComposeService service, {int tail = 200}) async* {
    await _projects.getProject(projectId);
    _checkDocker();
    for (final c in _running[ItemRef(projectId: projectId, serviceId: service.id)] ?? const <ContainerStatus>[]) {
      yield '${c.service}  | ready for connections';
    }
  }

  @override
  Future<ItemRef?> composeOwnerOf(int port) async {
    if (!dockerRunning) return null;
    for (final MapEntry(key: item, value: containers) in _running.entries) {
      if (containers.any((c) => c.ports.contains(port))) return item;
    }
    return null;
  }

  ComposeStatus _compose(String projectId, ComposeService service) => ComposeStatus(
      List.unmodifiable(_running[ItemRef(projectId: projectId, serviceId: service.id)] ?? const <ContainerStatus>[]));

  RemoteStatus _remote(RemoteService service) {
    final target = switch (service.ready) {
      HttpReady(:final url) => 'GET $url',
      PortReady(:final host, :final port) => '${host ?? 'localhost'}:$port',
      _ => service.id,
    };
    return RemoteStatus(reachable.contains(service.id)
        ? ProbeResult(target: target, ok: true, elapsed: const Duration(milliseconds: 120))
        : ProbeResult(target: target, ok: false, failureReason: '연결 거부'));
  }

  void _checkDocker() {
    if (!dockerRunning) throw DockerNotRunningException();
  }

  static ArgumentError _processError(ProcessService s) =>
      ArgumentError.value(s.id, 'service', 'process 항목은 ItemLauncher 가 아니라 runner 가 다뤄요');
}

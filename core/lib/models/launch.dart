import 'probe.dart';

/// Compose·원격 항목의 지금 상태. `ItemLauncher.start`·`status` 의 결과.
///
/// 종류마다 하위 클래스가 있다: [ComposeStatus], [RemoteStatus]. 화면에서는 `switch` 로 나눈다.
sealed class LaunchStatus {
  const LaunchStatus();
}

/// Compose 항목의 컨테이너 상태(FR-08). 포폴링이 `ppoling-<프로젝트ID>` 로 띄운 컨테이너만 담는다.
final class ComposeStatus extends LaunchStatus {
  const ComposeStatus(this.containers);

  /// 이 항목의 컨테이너. 띄운 적이 없거나 멈췄으면 빈 목록.
  final List<ContainerStatus> containers;

  /// 컨테이너가 하나 이상 있고 모두 실행 중이다.
  bool get running => containers.isNotEmpty && containers.every((c) => c.state == ContainerState.running);

  /// 실행 중이고, healthcheck 가 있는 컨테이너는 모두 healthy 다. `compose-healthy` 준비 조건이 이걸 본다.
  bool get healthy =>
      running && containers.every((c) => c.health == ContainerHealth.none || c.health == ContainerHealth.healthy);
}

/// Compose 컨테이너 하나.
class ContainerStatus {
  const ContainerStatus({
    required this.service,
    required this.name,
    required this.state,
    this.health = ContainerHealth.none,
    this.ports = const [],
    this.exitCode,
  });

  /// compose 파일 안의 서비스 이름. 예: `mysql`
  final String service;

  /// 컨테이너 이름. 예: `ppoling-my-team-project-mysql-1`
  final String name;

  final ContainerState state;
  final ContainerHealth health;

  /// 이 컴퓨터에 열어 둔(published) 포트. 예: `[3306]`
  final List<int> ports;

  /// 멈춘 컨테이너의 종료 코드. 실행 중이면 null.
  final int? exitCode;
}

/// 컨테이너 상태. Docker 의 상태 이름과 같다.
enum ContainerState { created, running, restarting, paused, exited, dead }

/// 컨테이너 healthcheck 결과. compose 파일에 healthcheck 가 없으면 [none].
enum ContainerHealth { none, starting, healthy, unhealthy }

/// 원격 항목의 연결 상태(FR-18). 화면에는 `연결됨` / `연결 안 됨` 으로 보인다.
final class RemoteStatus extends LaunchStatus {
  const RemoteStatus(this.probe);

  /// 항목의 ready(http 또는 host 가 있는 port)로 확인한 결과.
  final ProbeResult probe;

  bool get connected => probe.ok;
}

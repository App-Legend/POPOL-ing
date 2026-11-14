import '../models/errors.dart';
import '../models/item_ref.dart';
import '../models/launch.dart';
import '../models/service_config.dart';

/// Compose 항목(FR-08)과 원격 항목(FR-18)을 다룬다. 프로세스 항목은 A(`runner/`)가 직접 다룬다.
///
/// - 진짜 구현: C (`compose/`)
/// - 쓰는 곳: A(전체 실행·종료, `compose-healthy` 준비 대기, `RuntimeQuery` 의 Compose 포트 주인 판단),
///   C(화면 5 Docker 상태)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [itemLauncherContract] 로 확인한다.
/// 1. Compose 는 `docker compose -p ppoling-<프로젝트ID>` 로만 다룬다. 사용자가 직접 띄운 같은 compose 는 건드리지 않는다.
/// 2. 멈출 때 이 항목의 컨테이너만 멈추고 지운다. 같은 compose 파일의 다른 항목과 볼륨은 그대로 둔다(`down -v` 금지).
/// 3. 원격 항목은 켜고 끄지 않는다. 연결만 확인하고, [stop] 은 아무것도 하지 않는다.
/// 4. [ProcessService] 를 받으면 [ArgumentError]. 그 밖의 실패는 [PpolingException] 계열로 알린다.
/// 5. 준비 완료를 기다리지 않는다. 기다리는 일은 전체 실행(A)이 [status] 를 되풀이해 부르며 한다.
abstract interface class ItemLauncher {
  /// 항목을 시작한다. Compose 는 `up -d`, 원격은 연결 확인만 한다. 시작 직후 상태를 돌려준다.
  ///
  /// - 등록되지 않은 프로젝트면 [ProjectNotFoundException]
  /// - Compose 인데 Docker 가 꺼져 있으면 [DockerNotRunningException]
  /// - `docker compose` 가 실패하면 [ComposeCommandException]
  /// - 원격 연결이 안 되는 건 예외가 아니라 [RemoteStatus.connected] 가 false 인 결과다
  Future<LaunchStatus> start(String projectId, ServiceConfig service);

  /// 항목을 멈춘다. 이미 멈췄으면 아무것도 하지 않는다. 예외는 [start] 와 같다.
  Future<void> stop(String projectId, ServiceConfig service);

  /// 지금 상태. 띄운 적이 없는 Compose 항목은 컨테이너가 빈 [ComposeStatus] 다. 예외는 [start] 와 같다.
  Future<LaunchStatus> status(String projectId, ServiceConfig service);

  /// Compose 항목의 컨테이너 로그. 최근 [tail] 줄부터 보내고, 구독을 끊을 때까지 새 줄을 이어 보낸다.
  /// 컨테이너가 없으면 바로 끝난다. Docker 가 꺼져 있으면 [DockerNotRunningException] 으로 끝난다.
  Stream<String> logs(String projectId, ComposeService service, {int tail = 200});

  /// 포폴링이 띄운 Compose 컨테이너 중 [port] 를 열어 둔 것의 항목. 없으면 null.
  ///
  /// A 의 `RuntimeQuery.ownerOf` 가 Compose 항목을 판단할 때 부른다. 예외를 던지지 않고,
  /// Docker 가 꺼져 있거나 확인할 수 없으면 null 을 돌려준다.
  Future<ItemRef?> composeOwnerOf(int port);
}

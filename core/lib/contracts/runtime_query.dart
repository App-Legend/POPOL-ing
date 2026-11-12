import '../models/item_ref.dart';
import '../models/probe.dart';

/// 포트를 쓰는 프로세스가 포폴링이 띄운 내 항목인지(FR-06, AT-03·17).
///
/// - 진짜 구현: A (`runner/`)
/// - 쓰는 곳: C(포트 확인. `PortProbe.whoUses` 결과를 그대로 넘기고, 내 항목이면 [이동]·[그 항목 중지],
///   null 이면 외부 프로그램으로 이름·PID 만 보여준다)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [runtimeQueryContract] 로 확인한다.
/// 1. 프로세스 항목은 포트가 맞고, PID 가 실행 기록의 프로세스 그룹(띄운 프로세스와 그 자식)에 들어 있을 때만
///    내 항목이다. 예: `npm run dev` 로 띄웠으면 포트를 잡은 `node` 도 내 항목. 포트만 맞으면 null.
/// 2. PID 를 모르면(`pid == null`) 프로세스 항목은 null. 확인할 수 없으면 내 것이라고 하지 않는다.
/// 3. Compose 항목은 PID 가 docker 쪽이라 `ppoling-<프로젝트ID>` 의 포트 매핑으로 판단한다.
///    포트 매핑은 C 의 `ItemLauncher` 로 조회한다(`runner/` 는 `compose/` 를 import 하지 않는다).
/// 4. 프로세스를 종료하지 않는다. 예외를 던지지 않고, 모르면 null 을 돌려준다.
abstract interface class RuntimeQuery {
  /// [usage] 의 포트를 포폴링이 띄운 내 항목이 쓰고 있으면 그 항목, 아니면 null.
  Future<ItemRef?> ownerOf(PortInUse usage);
}

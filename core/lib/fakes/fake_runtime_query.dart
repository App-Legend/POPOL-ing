import '../contracts/runtime_query.dart';
import '../models/item_ref.dart';
import '../models/probe.dart';

/// [FakeRuntimeQuery] 에 넣는 실행 기록 한 줄. [pid] 가 null 이면 Compose 항목이라 포트만으로 판단한다.
typedef OwnedPort = ({int port, int? pid, ItemRef item});

/// [RuntimeQuery] 의 가짜 구현. [owned] 에 넣은 기록으로만 답한다.
///
/// 테스트 중에 [owned] 를 바꿔도 된다(예: 항목을 중지하면 목록에서 빼기).
/// ```dart
/// final runtime = FakeRuntimeQuery(owned: [
///   (port: 5173, pid: 4321, item: const ItemRef(projectId: 'shop-clone', serviceId: 'web')),
/// ]);
/// await runtime.ownerOf(const PortInUse(5173, pid: 4321));   // shop-clone / web
/// await runtime.ownerOf(const PortInUse(5173, pid: 999));    // null (외부 프로그램)
/// ```
class FakeRuntimeQuery implements RuntimeQuery {
  FakeRuntimeQuery({Iterable<OwnedPort> owned = const []}) : owned = [...owned];

  final List<OwnedPort> owned;

  @override
  Future<ItemRef?> ownerOf(PortInUse usage) async {
    for (final o in owned) {
      if (o.port == usage.port && (o.pid == null || (usage.pid != null && o.pid == usage.pid))) return o.item;
    }
    return null;
  }
}

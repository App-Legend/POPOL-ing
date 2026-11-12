import '../contracts/port_probe.dart';
import '../models/probe.dart';

/// [PortProbe] 의 가짜 구현. 실제로 포트를 확인하지 않는다.
///
/// [inUse] 에 넣은 포트는 사용 중이고 localhost 연결이 된다. 원격은 [reachableRemotes] 에
/// `host:port` 로 넣은 것만 연결된다. 둘 다 테스트 중에 바꿔도 된다(예: 항목을 멈춘 뒤 포트 비우기).
/// ```dart
/// final ports = FakePortProbe(inUse: [PortInUse(8080, pid: 4321, processName: 'java')]);
/// await ports.whoUses(8080);   // PortInUse
/// ports.inUse.remove(8080);
/// await ports.whoUses(8080);   // PortFree
/// ```
class FakePortProbe implements PortProbe {
  FakePortProbe({Iterable<PortInUse> inUse = const [], Set<String> reachableRemotes = const {}})
      : inUse = {for (final p in inUse) p.port: p},
        reachableRemotes = {...reachableRemotes};

  /// 사용 중인 포트.
  final Map<int, PortInUse> inUse;

  /// 연결되는 원격 주소. 예: `db.example.com:3306`
  final Set<String> reachableRemotes;

  @override
  Future<PortUsage> whoUses(int port) async {
    _checkPort(port);
    return inUse[port] ?? PortFree(port);
  }

  @override
  Future<ProbeResult> connect(int port, {String? host, Duration timeout = PortProbe.defaultTimeout}) async {
    _checkPort(port);
    final target = '${host ?? 'localhost'}:$port';
    final ok = host == null || host == 'localhost' || host == '127.0.0.1'
        ? inUse.containsKey(port)
        : reachableRemotes.contains(target);
    return ok
        ? ProbeResult(target: target, ok: true, elapsed: const Duration(milliseconds: 3))
        : ProbeResult(target: target, ok: false, failureReason: '연결 거부');
  }

  static void _checkPort(int port) {
    if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port', '1~65535 사이여야 해요');
  }
}

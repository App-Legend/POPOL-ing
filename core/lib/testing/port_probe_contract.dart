import 'package:flutter_test/flutter_test.dart';

import '../contracts/port_probe.dart';
import '../models/probe.dart';

/// [portProbeContract] 가 테스트마다 받는 준비물.
class PortProbeFixture {
  PortProbeFixture({required this.probe, required this.freePort, required this.busyPort});

  final PortProbe probe;

  /// 이 컴퓨터에서 아무도 쓰지 않는 포트.
  final int freePort;

  /// 이 컴퓨터에서 누군가 연결을 받고 있는 포트. 진짜 구현 테스트에서는 `ServerSocket.bind` 로 연다.
  final int busyPort;
}

/// [PortProbe] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
/// ```dart
/// group('SystemPortProbe', () {
///   portProbeContract(() async => PortProbeFixture(probe: ..., freePort: ..., busyPort: ...));
/// });
/// ```
void portProbeContract(Future<PortProbeFixture> Function() setUp) {
  test('비어 있는 포트는 PortFree 다', () async {
    final f = await setUp();
    final usage = await f.probe.whoUses(f.freePort);
    expect(usage, isA<PortFree>());
    expect(usage.port, f.freePort);
  });

  test('쓰고 있는 포트는 PortInUse 다', () async {
    final f = await setUp();
    final usage = await f.probe.whoUses(f.busyPort);
    expect(usage, isA<PortInUse>());
    expect(usage.port, f.busyPort);
  });

  test('쓰고 있는 포트는 연결되고, 응답 시간이 있다', () async {
    final f = await setUp();
    final result = await f.probe.connect(f.busyPort);
    expect(result.ok, isTrue);
    expect(result.target, 'localhost:${f.busyPort}');
    expect(result.elapsed, isNotNull);
    expect(result.failureReason, isNull);
    expect(result.statusCode, isNull);
  });

  test('비어 있는 포트는 연결되지 않고, 예외 대신 실패 이유를 돌려준다', () async {
    final f = await setUp();
    final result = await f.probe.connect(f.freePort);
    expect(result.ok, isFalse);
    expect(result.failureReason, isNotNull);
    expect(result.elapsed, isNull);
  });

  test('포트 번호가 1~65535 밖이면 ArgumentError', () async {
    final f = await setUp();
    for (final port in [0, 65536]) {
      await expectLater(f.probe.whoUses(port), throwsArgumentError, reason: '$port');
      await expectLater(f.probe.connect(port), throwsArgumentError, reason: '$port');
    }
  });
}

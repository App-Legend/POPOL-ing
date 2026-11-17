import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_checks/src/system_port_probe.dart';

// whoUses 를 채우면 이 파일을 portProbeContract 로 바꾼다. 아래 connect 테스트는 계약과 같은 내용이다.
void main() {
  final probe = SystemPortProbe();
  late ServerSocket server;
  late int freePort;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) => client.destroy());
    final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    freePort = spare.port;
    await spare.close();
  });
  tearDown(() => server.close());

  test('쓰고 있는 포트는 연결되고, 응답 시간이 있다', () async {
    final result = await probe.connect(server.port);
    expect(result.ok, isTrue);
    expect(result.target, 'localhost:${server.port}');
    expect(result.elapsed, isNotNull);
    expect(result.failureReason, isNull);
    expect(result.statusCode, isNull);
  });

  test('비어 있는 포트는 연결되지 않고, 예외 대신 실패 이유를 돌려준다', () async {
    final result = await probe.connect(freePort);
    expect(result.ok, isFalse);
    expect(result.failureReason, isNotNull);
    expect(result.elapsed, isNull);
  });

  test('충분히 기다리면 비어 있는 포트는 연결 거부다', () async {
    // Windows 는 거부를 약 2초 뒤에 알려서 기본 대기 시간으로는 응답 없음이 될 수 있다.
    final result = await probe.connect(freePort, timeout: const Duration(seconds: 5));
    expect(result.failureReason, '연결 거부');
  });

  test('host 를 주면 그 주소로 연결하고 대상에 적는다', () async {
    final result = await probe.connect(server.port, host: '127.0.0.1');
    expect((result.ok, result.target), (true, '127.0.0.1:${server.port}'));
  });

  test('없는 주소는 주소를 찾을 수 없음', () async {
    final result = await probe.connect(80, host: 'no-such-host.invalid');
    expect((result.ok, result.failureReason), (false, '주소를 찾을 수 없음'));
  });

  test('포트 번호가 1~65535 밖이면 ArgumentError', () async {
    for (final port in [0, 65536]) {
      await expectLater(probe.connect(port), throwsArgumentError, reason: '$port');
      await expectLater(probe.whoUses(port), throwsArgumentError, reason: '$port');
    }
  });
}

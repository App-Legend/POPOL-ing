import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/system_http_probe.dart';
import 'package:popoling_core/testing.dart';

void main() {
  late HttpServer server;
  late String base;
  late int freePort;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/ok':
          response.statusCode = 200;
          response.write('hello');
        case '/error':
          response.statusCode = 500;
        case '/moved':
          response.statusCode = 302;
          response.headers.set('location', '/error');
        case '/slow':
          await Future<void>.delayed(const Duration(seconds: 2));
      }
      await response.close();
    });
    base = 'http://127.0.0.1:${server.port}';
    final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    freePort = spare.port;
    await spare.close();
  });
  tearDown(() => server.close(force: true));

  final probe = SystemHttpProbe();

  group('SystemHttpProbe', () {
    httpProbeContract(() async => HttpProbeFixture(
          probe: probe,
          okUrl: '$base/ok',
          errorUrl: '$base/error',
          downUrl: 'http://127.0.0.1:$freePort/health',
        ));
  });

  test('리다이렉트는 따라가지 않고 3xx 를 응답으로 본다', () async {
    final result = await probe.get('$base/moved');
    expect((result.ok, result.statusCode), (true, 302));
  });

  test('기대 코드가 다르면 이유에 기대·받은 코드를 적는다', () async {
    final result = await probe.get('$base/error');
    expect(result.failureReason, '기대 200~399, 받은 500');
  });

  test('대기 시간 안에 답이 없으면 응답 없음', () async {
    final result = await probe.get('$base/slow', timeout: const Duration(milliseconds: 300));
    expect((result.ok, result.statusCode, result.failureReason), (false, null, '응답 없음 (0.3초 안에 답이 없음)'));
  });

  test('연결이 거부되면 연결 거부', () async {
    final result = await probe.get('http://127.0.0.1:$freePort/');
    expect(result.failureReason, '연결 거부');
  });

  test('없는 주소는 주소를 찾을 수 없음', () async {
    final result = await probe.get('http://no-such-host.invalid/');
    expect(result.failureReason, '주소를 찾을 수 없음');
  });
}

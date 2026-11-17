import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_runner/src/ready/readiness.dart';

void main() {
  late FakePortProbe ports;
  late FakeHttpProbe http;
  late Readiness readiness;

  setUp(() {
    ports = FakePortProbe();
    http = FakeHttpProbe();
    readiness = Readiness(ports: ports, http: http);
  });

  /// [delay] 뒤에 [change] 를 한다.
  void later(Duration delay, void Function() change) => Timer(delay, change);

  test('none 은 바로 준비 완료', () async {
    expect((await readiness.wait(const NoneReady())).ok, isTrue);
  });

  test('port 는 연결될 때까지 되풀이해 확인한다', () async {
    later(Duration(milliseconds: 50), () => ports.inUse[5173] = const PortInUse(5173));
    final r = await readiness.wait(const PortReady(port: 5173, timeout: Duration(milliseconds: 1000), interval: Duration(milliseconds: 10)));
    expect(r.ok, isTrue);
  });

  test('http 는 기대한 응답 코드가 오면 준비 완료', () async {
    const url = 'http://localhost:8080/health';
    http.responses[url] = 503;
    later(Duration(milliseconds: 50), () => http.responses[url] = 200);
    final r = await readiness.wait(const HttpReady(url: url, timeout: Duration(milliseconds: 1000), interval: Duration(milliseconds: 10)));
    expect(r.ok, isTrue);
  });

  test('제한 시간을 넘기면 실패하고, 이유에 시간과 마지막 확인 결과를 담는다', () async {
    final r = await readiness.wait(const PortReady(port: 5173, timeout: Duration(milliseconds: 100), interval: Duration(milliseconds: 10)));
    expect(r.ok, isFalse);
    expect(r.reason, contains('준비 시간'));
    expect(r.reason, contains('5173'));
  });

  test('log 는 출력에 정규식이 나타나면 준비 완료', () async {
    final lines = StreamController<String>();
    later(Duration(milliseconds: 20), () => lines..add('Booting')..add('Started App in 2.1 seconds'));
    final r = await readiness.wait(const LogReady(pattern: r'Started .* in', timeout: Duration(milliseconds: 1000)), lines: lines.stream);
    expect(r.ok, isTrue);
  });

  test('log 는 제한 시간 안에 안 나타나면 실패', () async {
    final lines = StreamController<String>()..add('Booting');
    final r = await readiness.wait(const LogReady(pattern: 'Started', timeout: Duration(milliseconds: 100)), lines: lines.stream);
    expect(r.ok, isFalse);
  });

  test('compose-healthy 는 healthy 가 될 때까지 되풀이해 묻는다', () async {
    var healthy = false;
    later(Duration(milliseconds: 50), () => healthy = true);
    final r = await readiness.wait(const ComposeHealthyReady(timeout: Duration(milliseconds: 1000), interval: Duration(milliseconds: 10)),
        composeHealthy: () async => healthy);
    expect(r.ok, isTrue);
  });

  test('준비되기 전에 프로세스가 끝나면 기다리지 않고 바로 실패한다', () async {
    final exited = Completer<int>();
    later(Duration(milliseconds: 20), () => exited.complete(1));
    final watch = Stopwatch()..start();
    final r = await readiness.wait(const PortReady(port: 5173, timeout: Duration(seconds: 10), interval: Duration(milliseconds: 10)),
        exited: exited.future);
    expect(r.ok, isFalse);
    expect(r.reason, contains('종료 코드 1'));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('필요한 재료가 없으면 ArgumentError', () {
    expect(() => readiness.wait(const LogReady(pattern: 'x')), throwsArgumentError);
    expect(() => readiness.wait(const ComposeHealthyReady()), throwsArgumentError);
  });

  test('확인 중에 예외가 나도 멈추지 않고 제한 시간에 실패로 끝난다', () async {
    final r = await Readiness(ports: ports, http: _ThrowingHttpProbe())
        .wait(const HttpReady(url: 'http://localhost:1/x', timeout: Duration(milliseconds: 200), interval: Duration(milliseconds: 20)))
        .timeout(const Duration(seconds: 3));
    expect(r.ok, isFalse);
    expect(r.reason, contains('확인하지 못했어요'));
  });

  test('멈추면 기다리지 않고 바로 실패한다', () async {
    final cancel = Completer<void>();
    later(const Duration(milliseconds: 20), cancel.complete);
    final r = await readiness.wait(const PortReady(port: 5173, timeout: Duration(seconds: 10)), cancelled: cancel.future)
        .timeout(const Duration(seconds: 2));
    expect(r.ok, isFalse);
    expect(r.reason, contains('멈췄어요'));
  });
}

class _ThrowingHttpProbe extends FakeHttpProbe {
  @override
  Future<ProbeResult> get(String url, {int? expectStatus, Duration timeout = HttpProbe.defaultTimeout}) =>
      throw const SocketException('연결 실패');
}

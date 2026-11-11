import 'package:flutter_test/flutter_test.dart';

import '../contracts/http_probe.dart';

/// [httpProbeContract] 가 테스트마다 받는 준비물.
/// 진짜 구현 테스트에서는 `HttpServer.bind` 로 띄운 로컬 서버 주소를 쓴다.
class HttpProbeFixture {
  HttpProbeFixture({required this.probe, required this.okUrl, required this.errorUrl, required this.downUrl});

  final HttpProbe probe;

  /// 200 으로 답하는 주소.
  final String okUrl;

  /// 500 으로 답하는 주소.
  final String errorUrl;

  /// 연결이 안 되는 주소. 예: 아무도 쓰지 않는 포트의 localhost
  final String downUrl;
}

/// [HttpProbe] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void httpProbeContract(Future<HttpProbeFixture> Function() setUp) {
  test('200 이면 성공이고, 응답 코드·응답 시간이 있다', () async {
    final f = await setUp();
    final result = await f.probe.get(f.okUrl);
    expect(result.ok, isTrue);
    expect(result.target, 'GET ${f.okUrl}');
    expect(result.statusCode, 200);
    expect(result.elapsed, isNotNull);
    expect(result.failureReason, isNull);
  });

  test('기대 코드와 다르면 실패이고, 받은 코드와 이유를 남긴다', () async {
    final f = await setUp();
    final result = await f.probe.get(f.okUrl, expectStatus: 204);
    expect(result.ok, isFalse);
    expect(result.statusCode, 200);
    expect(result.failureReason, isNotNull);
  });

  test('기대 코드를 안 주면 500 은 실패다', () async {
    final f = await setUp();
    final result = await f.probe.get(f.errorUrl);
    expect(result.ok, isFalse);
    expect(result.statusCode, 500);
    expect(result.failureReason, isNotNull);
  });

  test('기대 코드가 500 이면 500 은 성공이다', () async {
    final f = await setUp();
    expect((await f.probe.get(f.errorUrl, expectStatus: 500)).ok, isTrue);
  });

  test('연결이 안 되면 예외 대신 실패 결과이고, 응답 코드는 없다', () async {
    final f = await setUp();
    final result = await f.probe.get(f.downUrl);
    expect(result.ok, isFalse);
    expect(result.statusCode, isNull);
    expect(result.elapsed, isNull);
    expect(result.failureReason, isNotNull);
  });

  test('주소 형식이 잘못돼도 예외 대신 실패 결과다', () async {
    final f = await setUp();
    for (final url in ['not a url', 'ftp://localhost/x', '']) {
      final result = await f.probe.get(url);
      expect(result.ok, isFalse, reason: url);
      expect(result.failureReason, isNotNull, reason: url);
    }
  });
}

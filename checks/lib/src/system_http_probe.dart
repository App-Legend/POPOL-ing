import 'dart:async';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

import 'failure_reason.dart';

/// [HttpProbe] 진짜 구현. GET 을 한 번 보내고 응답 코드만 본다(본문은 읽고 버린다).
///
/// 리다이렉트는 따라가지 않는다. 모든 실패는 예외 대신 `ok: false` 결과로 돌려준다.
class SystemHttpProbe implements HttpProbe {
  @override
  Future<ProbeResult> get(String url, {int? expectStatus, Duration timeout = HttpProbe.defaultTimeout}) async {
    final target = 'GET $url';
    ProbeResult fail(String reason) => ProbeResult(target: target, ok: false, failureReason: reason);

    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return fail('주소 형식이 잘못됐어요');
    }

    final client = HttpClient()..connectionTimeout = timeout;
    final watch = Stopwatch()..start();
    try {
      final status = await _send(client, uri).timeout(timeout);
      final elapsed = watch.elapsed;
      final ok = expectStatus == null ? status >= 200 && status < 400 : status == expectStatus;
      return ProbeResult(
        target: target,
        ok: ok,
        statusCode: status,
        elapsed: elapsed,
        failureReason: ok ? null : '기대 ${expectStatus ?? '200~399'}, 받은 $status',
      );
    } on TimeoutException {
      return fail(timedOutReason(timeout));
    } on SocketException catch (e) {
      return fail(connectFailureReason(e, watch.elapsed, timeout));
    } on HandshakeException {
      return fail('보안 연결(HTTPS) 실패');
    } on HttpException {
      return fail('HTTP 응답을 읽지 못함');
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _send(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }
}

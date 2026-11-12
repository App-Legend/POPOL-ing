import '../contracts/http_probe.dart';
import '../models/probe.dart';

/// [HttpProbe] 의 가짜 구현. 실제로 요청을 보내지 않는다.
///
/// [responses] 에 넣은 주소는 그 응답 코드로 답하고, 없는 주소는 연결 거부로 꾸민다.
/// 테스트 중에 바꿔도 된다(예: 원격 서버 끊기).
/// ```dart
/// final http = FakeHttpProbe(responses: {'http://localhost:8080/health': 200});
/// await http.get('http://localhost:8080/health');   // ok
/// ```
class FakeHttpProbe implements HttpProbe {
  FakeHttpProbe({Map<String, int> responses = const {}}) : responses = {...responses};

  /// 주소 → 응답 코드.
  final Map<String, int> responses;

  @override
  Future<ProbeResult> get(String url, {int? expectStatus, Duration timeout = HttpProbe.defaultTimeout}) async {
    final target = 'GET $url';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return ProbeResult(target: target, ok: false, failureReason: '주소 형식이 잘못됐어요');
    }
    final status = responses[url];
    if (status == null) return ProbeResult(target: target, ok: false, failureReason: '연결 거부');

    final ok = expectStatus == null ? status >= 200 && status < 400 : status == expectStatus;
    return ProbeResult(
      target: target,
      ok: ok,
      statusCode: status,
      elapsed: const Duration(milliseconds: 84),
      failureReason: ok ? null : '기대 ${expectStatus ?? '200~399'}, 받은 $status',
    );
  }
}

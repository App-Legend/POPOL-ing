import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/ai.dart';
import 'package:ppoling_core/models.dart';
import 'package:ppoling_core/testing.dart';

/// 보낸 요청을 남기고, 정해 둔 응답을 차례로 돌려주는 가짜 HTTP.
class FakeHttp {
  FakeHttp(this.responses);

  /// 차례로 돌려줄 응답. 함수면 불러서 던지거나 기다리게 할 수 있다.
  final List<Object> responses;
  final List<({Uri url, Map<String, String> headers, Map<String, Object?> body})> sent = [];

  Future<GeminiHttpResponse> call(Uri url, Map<String, String> headers, String body) async {
    sent.add((url: url, headers: headers, body: jsonDecode(body) as Map<String, Object?>));
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    return switch (next) {
      final GeminiHttpResponse r => r,
      final Future<GeminiHttpResponse> Function() f => f(),
      _ => throw StateError('$next'),
    };
  }
}

GeminiHttpResponse answer(String text, {String modelVersion = 'gemini-3.8-flash'}) => GeminiHttpResponse(
      200,
      jsonEncode({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': text},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'modelVersion': modelVersion,
      }),
    );

GeminiHttpResponse error(int status, String statusText, {String message = '', String? reason}) => GeminiHttpResponse(
      status,
      jsonEncode({
        'error': {
          'code': status,
          'status': statusText,
          'message': message,
          if (reason != null)
            'details': [
              {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', 'reason': reason},
            ],
        },
      }),
    );

GeminiLlmClient clientWith(FakeHttp http, {String? key = 'test-key-1234'}) => GeminiLlmClient(
      keys: MemoryApiKeyStore(key),
      transport: http.call,
      retryDelay: Duration.zero,
      timeout: const Duration(milliseconds: 200),
    );

Matcher failsWith(LlmFailure failure) => throwsA(isA<LlmException>().having((e) => e.failure, 'failure', failure));

void main() {
  group('LlmClient 약속', () {
    llmClientContract(() async => LlmClientFixture(
          configured: clientWith(FakeHttp([answer('API 헬스가 503으로 실패했어요.')])),
          unconfigured: clientWith(FakeHttp([answer('보내면 안 돼요')]), key: null),
        ));
  });

  test('요청: 키는 헤더로만 보내고 주소에는 넣지 않는다. 역할 지시와 내용을 나눠 보낸다', () async {
    final http = FakeHttp([answer('요약')]);
    await clientWith(http).complete('검사 결과', system: '두세 문장으로');

    final req = http.sent.single;
    expect(req.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent');
    expect(req.url.query, isEmpty);
    expect(req.headers['x-goog-api-key'], 'test-key-1234');
    expect(req.body['systemInstruction'], {
      'parts': [
        {'text': '두세 문장으로'},
      ],
    });
    expect(req.body['contents'], [
      {
        'role': 'user',
        'parts': [
          {'text': '검사 결과'},
        ],
      },
    ]);
  });

  test('키가 없으면 아무것도 보내지 않는다', () async {
    final http = FakeHttp([answer('x')]);
    await expectLater(clientWith(http, key: null).complete('a'), failsWith(LlmFailure.missingKey));
    expect(http.sent, isEmpty);
  });

  test('답의 여러 조각을 이어 붙이고, 실제로 답한 모델 이름을 남긴다', () async {
    final http = FakeHttp([
      GeminiHttpResponse(
        200,
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '첫 문장. '},
                  {'text': '둘째 문장.'},
                ],
              },
            },
          ],
          'modelVersion': 'gemini-3.8-flash',
        }),
      ),
    ]);
    final client = clientWith(http);
    expect(client.modelName, 'gemini-flash-latest');
    expect(await client.complete('a'), '첫 문장. 둘째 문장.');
    expect(client.modelName, 'gemini-3.8-flash');
  });

  group('실패 이유를 나눈다', () {
    final cases = <String, (Object, LlmFailure)>{
      '400 + API_KEY_INVALID → 키 오류': (error(400, 'INVALID_ARGUMENT', message: 'API key not valid.', reason: 'API_KEY_INVALID'), LlmFailure.invalidKey),
      '401 → 키 오류': (error(401, 'UNAUTHENTICATED', reason: 'ACCESS_TOKEN_TYPE_UNSUPPORTED'), LlmFailure.invalidKey),
      '403 → 키 오류': (error(403, 'PERMISSION_DENIED'), LlmFailure.invalidKey),
      '429 → 사용량 초과': (error(429, 'RESOURCE_EXHAUSTED'), LlmFailure.quotaExceeded),
      '400 (키와 무관) → 서버 응답 문제': (error(400, 'INVALID_ARGUMENT', message: 'Request contains an invalid argument.'), LlmFailure.network),
      '404 → 서버 응답 문제': (error(404, 'NOT_FOUND'), LlmFailure.network),
      '빈 답 → 서버 응답 문제': (const GeminiHttpResponse(200, '{"candidates":[]}'), LlmFailure.network),
      'JSON 이 아닌 응답 → 서버 응답 문제': (const GeminiHttpResponse(502, '<html>Bad Gateway</html>'), LlmFailure.network),
    };
    for (final MapEntry(key: name, value: (response, failure)) in cases.entries) {
      test(name, () async {
        await expectLater(clientWith(FakeHttp([response])).complete('a'), failsWith(failure));
      });
    }

    test('인터넷이 끊기면 한 번 더 해 보고 네트워크', () async {
      final http = FakeHttp([() async => throw const SocketException('Failed host lookup')]);
      await expectLater(clientWith(http).complete('a'), failsWith(LlmFailure.network));
      expect(http.sent, hasLength(2));
    });

    test('제한 시간 안에 답이 없으면 한 번 더 해 보고 네트워크', () async {
      final http = FakeHttp([() => Completer<GeminiHttpResponse>().future]);
      await expectLater(clientWith(http).complete('a'), failsWith(LlmFailure.network));
      expect(http.sent, hasLength(2));
    });
  });

  group('서버가 붐비면(503·시간 초과) 가벼운 모델로 한 번만 다시 보낸다', () {
    test('두 번째에 되면 답을 돌려주고, 답한 모델 이름을 남긴다', () async {
      final http = FakeHttp([error(503, 'UNAVAILABLE', message: 'high demand'), answer('됐어요', modelVersion: 'gemini-3.5-flash-lite')]);
      final client = clientWith(http);
      expect(await client.complete('a'), '됐어요');
      expect([for (final r in http.sent) r.url.pathSegments.last], [
        'gemini-flash-latest:generateContent',
        'gemini-flash-lite-latest:generateContent',
      ]);
      expect(client.modelName, 'gemini-3.5-flash-lite');
    });

    test('첫 요청이 시간 초과여도 가벼운 모델로 다시 보낸다', () async {
      final http = FakeHttp([() => Completer<GeminiHttpResponse>().future, answer('됐어요')]);
      expect(await clientWith(http).complete('a'), '됐어요');
      expect(http.sent.last.url.pathSegments.last, 'gemini-flash-lite-latest:generateContent');
    });

    test('대신할 모델을 끄면 같은 모델로 다시 보낸다', () async {
      final http = FakeHttp([error(503, 'UNAVAILABLE'), answer('됐어요')]);
      final client = GeminiLlmClient(keys: MemoryApiKeyStore('k-1234'), transport: http.call, fallbackModel: null, retryDelay: Duration.zero);
      expect(await client.complete('a'), '됐어요');
      expect({for (final r in http.sent) r.url.pathSegments.last}, {'gemini-flash-latest:generateContent'});
    });

    test('두 번 다 붐비면 네트워크로 알리고 더 보내지 않는다', () async {
      final http = FakeHttp([error(503, 'UNAVAILABLE')]);
      await expectLater(clientWith(http).complete('a'), failsWith(LlmFailure.network));
      expect(http.sent, hasLength(2));
    });

    test('키 오류·사용량 초과는 다시 보내지 않는다', () async {
      for (final status in [401, 429]) {
        final http = FakeHttp([error(status, 'X')]);
        await expectLater(clientWith(http).complete('a'), throwsA(isA<LlmException>()));
        expect(http.sent, hasLength(1));
      }
    });
  });

  test('예외 문장에 API 키가 들어가지 않는다', () async {
    final http = FakeHttp([error(400, 'INVALID_ARGUMENT', message: 'API key not valid.', reason: 'API_KEY_INVALID')]);
    try {
      await clientWith(http, key: 'secret-key-9876').complete('a');
      fail('실패해야 해요');
    } on LlmException catch (e) {
      expect('$e ${e.message}', isNot(contains('secret-key-9876')));
    }
  });
}

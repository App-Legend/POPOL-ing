import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

import 'api_key_store.dart';

/// HTTP 응답 하나.
class GeminiHttpResponse {
  const GeminiHttpResponse(this.status, this.body);

  final int status;
  final String body;
}

/// POST 한 번을 보내는 함수. 테스트에서는 실제 서버 대신 가짜를 넣는다.
typedef GeminiTransport = Future<GeminiHttpResponse> Function(Uri url, Map<String, String> headers, String body);

/// Gemini API 로 보내는 [LlmClient]. 포폴링에서 Gemini 를 부르는 곳은 여기 하나뿐이다.
///
/// - 키는 [ApiKeyStore] 에서 꺼내 `x-goog-api-key` 헤더로만 보낸다. 주소·로그·예외에는 넣지 않는다.
/// - 키가 없으면 아무것도 보내지 않고 [LlmFailure.missingKey].
/// - 서버가 붐비거나(503 등) 제한 시간 안에 답이 없으면 [fallbackModel] 로 한 번만 더 보낸다.
///   그래도 안 되면 [LlmFailure.network]. 무료 등급은 붐빌 때가 잦아서다.
/// - 실패 이유는 [LlmException] 하나로 알린다. 화면 문구는 `llmErrorText` 가 고른다.
class GeminiLlmClient implements LlmClient {
  GeminiLlmClient({
    required this.keys,
    GeminiTransport? transport,
    this.model = defaultModel,
    this.fallbackModel = defaultFallbackModel,
    this.timeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(seconds: 2),
  }) : _transport = transport ?? _httpPost;

  /// 항상 최신 Flash 를 가리키는 이름. 옛 모델이 막혀도 앱을 고치지 않아도 된다.
  static const defaultModel = 'gemini-flash-latest';

  /// [defaultModel] 이 붐빌 때 쓰는 가벼운 모델. 같은 키로 쓸 수 있다.
  static const defaultFallbackModel = 'gemini-flash-lite-latest';

  static final _api = Uri.parse('https://generativelanguage.googleapis.com/v1beta/');

  final ApiKeyStore keys;

  /// 요청에 쓰는 모델 이름.
  final String model;

  /// [model] 이 붐빌 때 한 번 더 보낼 모델. null 이면 같은 모델로 한 번 더 보낸다.
  final String? fallbackModel;

  /// 요청 하나를 기다리는 시간.
  final Duration timeout;

  /// 서버가 붐빌 때 다시 보내기 전에 기다리는 시간.
  final Duration retryDelay;

  final GeminiTransport _transport;

  String? _answeredBy;

  /// 마지막으로 답한 실제 모델(예: `gemini-3.8-flash`). 아직 답을 받은 적이 없으면 [model].
  @override
  String get modelName => _answeredBy ?? model;

  @override
  Future<bool> isConfigured() async => await keys.read() != null;

  @override
  Future<String> complete(String prompt, {String? system}) async {
    final key = await keys.read();
    if (key == null) {
      throw LlmException(LlmFailure.missingKey);
    }
    final headers = {'content-type': 'application/json; charset=utf-8', 'x-goog-api-key': key};
    final body = jsonEncode({
      if (system != null)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });

    GeminiHttpResponse? first;
    try {
      first = await _send(_url(model), headers, body);
    } on LlmException {
      first = null; // 제한 시간 초과·연결 실패. 아래에서 한 번만 더 해 본다.
    }
    if (first != null && !_isBusy(first.status)) {
      return _answer(first); // 키 오류·사용량 초과는 다시 보내지 않는다.
    }
    await Future<void>.delayed(retryDelay);
    return _answer(await _send(_url(fallbackModel ?? model), headers, body));
  }

  static Uri _url(String model) => _api.resolve('models/$model:generateContent');

  Future<GeminiHttpResponse> _send(Uri url, Map<String, String> headers, String body) async {
    try {
      return await _transport(url, headers, body).timeout(timeout);
    } on TimeoutException {
      throw LlmException(LlmFailure.network);
    } on IOException {
      throw LlmException(LlmFailure.network); // 인터넷 끊김, 이름 풀이 실패, TLS 오류
    }
  }

  static bool _isBusy(int status) => status == 500 || status == 502 || status == 503 || status == 504;

  String _answer(GeminiHttpResponse response) {
    final json = _decode(response.body);
    switch (response.status) {
      case 200:
        final text = _text(json);
        if (text.trim().isEmpty) {
          // 안전 필터 등으로 답이 비었다. 서버 응답 문제로 묶어 다시 해 보게 한다.
          throw LlmException(LlmFailure.network);
        }
        if (json?['modelVersion'] case final String version when version.isNotEmpty) {
          _answeredBy = version;
        }
        return text;
      case 401 || 403:
        throw LlmException(LlmFailure.invalidKey);
      case 400 when _mentionsKey(json):
        throw LlmException(LlmFailure.invalidKey);
      case 429:
        throw LlmException(LlmFailure.quotaExceeded);
      default:
        // 붐빔이 이어지거나 알 수 없는 응답. 키와 사용량 문제는 아니니 잠시 뒤 다시 해 보게 한다.
        throw LlmException(LlmFailure.network);
    }
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  static String _text(Map<String, Object?>? json) {
    final candidates = json?['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return '';
    }
    final parts = switch (candidates.first) {
      {'content': {'parts': final List<Object?> parts}} => parts,
      _ => const <Object?>[],
    };
    return [
      for (final part in parts)
        if (part case {'text': final String text}) text,
    ].join();
  }

  /// 400 이 키 문제인지. Google 은 키가 틀리면 400 에 `API_KEY_INVALID` 를 넣기도 한다.
  static bool _mentionsKey(Map<String, Object?>? json) {
    final error = json?['error'];
    if (error is! Map) {
      return false;
    }
    final details = error['details'];
    final reasons = [
      if (details is List)
        for (final d in details)
          if (d case {'reason': final String reason}) reason,
    ];
    final message = '${error['message'] ?? ''}';
    return reasons.any((r) => r.startsWith('API_KEY')) || message.contains('API key');
  }
}

Future<GeminiHttpResponse> _httpPost(Uri url, Map<String, String> headers, String body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return GeminiHttpResponse(response.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

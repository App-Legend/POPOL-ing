/// 비밀값을 가린 결과. [text] 가 곧 보낼 내용이고, 보내기 전 확인 창에도 이것을 그대로 보여준다.
class Redacted {
  const Redacted(this.text, this.count);

  final String text;

  /// 가린 곳의 수.
  final int count;
}

const mask = '••••••';

/// 이름에 이 말이 들어간 `이름=값`·`이름: 값` 은 값을 가린다. 예: `DB_PASSWORD=...`, `Authorization: Bearer ...`
final _secretAssignment = RegExp(
  r'''\b([A-Za-z0-9_.-]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD|CREDENTIAL|AUTH|PRIVATE)[A-Za-z0-9_.-]*)(\s*[=:]\s*)((?:Bearer\s+)?(?:"[^"\n]*"|'[^'\n]*'|[^\s"',;]+))''',
  caseSensitive: false,
);

/// 이름 없이 나와도 모양만으로 알 수 있는 비밀값.
final _secretShapes = [
  RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'),
  RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]{8,}'),
  RegExp(r'\bAIza[0-9A-Za-z_-]{30,}'), // Google API 키
  RegExp(r'\bAQ\.[0-9A-Za-z_-]{20,}'), // Google API 키(새 모양)
  RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}'), // GitHub 토큰
  RegExp(r'\bsk-[A-Za-z0-9_-]{20,}'),
  RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'), // JWT
];

/// 주소 안의 `사용자:비밀번호@`.
final _urlCredentials = RegExp(r'(://)[^/\s:@]+:[^/\s@]+@');

/// [text] 에서 비밀값으로 보이는 곳을 [mask] 로 가린다.
///
/// [secrets] 는 꼭 가려야 하는 값(저장된 API 키, `.env` 값 등)이다. 4글자보다 짧은 값은 흔한 글자를 지우지 않게 건너뛴다.
/// 넉넉하게 가리는 쪽을 택한다. 보낼 내용에서 조금 더 가려지는 것은 괜찮지만 비밀값이 나가면 안 되기 때문이다.
Redacted redactSecrets(String text, {Iterable<String> secrets = const []}) {
  var count = 0;
  var out = text;

  for (final secret in {...secrets.map((s) => s.trim())}.where((s) => s.length >= 4)) {
    final parts = out.split(secret);
    if (parts.length > 1) {
      count += parts.length - 1;
      out = parts.join(mask);
    }
  }

  out = out.replaceAllMapped(_urlCredentials, (m) {
    count++;
    return '${m[1]}$mask@';
  });

  for (final shape in _secretShapes) {
    out = out.replaceAllMapped(shape, (m) {
      count++;
      return m[0]!.startsWith('Bearer') ? 'Bearer $mask' : mask;
    });
  }

  out = out.replaceAllMapped(_secretAssignment, (m) {
    final value = m[3]!;
    if (value.contains(mask)) {
      return m[0]!; // 이미 가렸다.
    }
    count++;
    return '${m[1]}${m[2]}$mask';
  });

  return Redacted(out, count);
}

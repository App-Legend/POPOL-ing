/// 버전 출력 읽기와 버전 범위 비교. 범위 규칙은 `EnvChecker` 계약 주석을 따른다.
library;

/// 점으로 이은 숫자가 두 자리 이상인 것만 버전으로 본다. `build 7` 같은 숫자 하나는 건너뛴다.
final _version = RegExp(r'\d+(?:\.\d+)+');

/// 버전 출력([output])에서 처음 나오는 버전. 예: `v22.3.0` → `22.3.0`, `go1.22.5` → `1.22.5`. 없으면 null.
String? readVersion(String output) => _version.firstMatch(output)?.group(0);

final _condition = RegExp(r'^(>=|<=|>|<|=)?(\d+(?:\.\d+)*)$');

/// [version] 이 [range] 를 만족하는지. [range] 를 해석할 수 없으면 null.
///
/// 공백으로 이은 조건을 모두 만족해야 한다. 연산자가 없으면 `=` 이고, `=` 는 적은 자리까지만 비교한다.
/// 나머지 연산자는 빠진 자리를 0 으로 보고 비교한다.
bool? versionAllows(String range, String version) {
  final have = _parts(version);
  final conditions = range.trim().split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();
  if (have == null || conditions.isEmpty) return null;
  var allowed = true;
  for (final c in conditions) {
    final m = _condition.firstMatch(c);
    if (m == null) return null; // 하나라도 못 읽으면 결과를 믿을 수 없다
    final want = _parts(m[2]!)!;
    final ok = switch (m[1] ?? '=') {
      '=' => [for (var i = 0; i < want.length; i++) i < have.length ? have[i] : 0].join('.') == want.join('.'),
      '>=' => _compare(have, want) >= 0,
      '>' => _compare(have, want) > 0,
      '<=' => _compare(have, want) <= 0,
      _ => _compare(have, want) < 0,
    };
    allowed = allowed && ok;
  }
  return allowed;
}

List<int>? _parts(String v) => RegExp(r'^v?(\d+(?:\.\d+)*)').firstMatch(v.trim())?[1]!.split('.').map(int.parse).toList();

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final d = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

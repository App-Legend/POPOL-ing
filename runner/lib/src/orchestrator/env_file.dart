import 'dart:io';

/// `.env` 파일을 읽는다. `KEY=VALUE` 줄만 보고, 빈 줄·`#` 주석·`export ` 앞말은 건너뛴다. 값의 양끝 따옴표와 값 뒤 ` #` 주석은 뗀다.
/// 파일이 없으면 [FileSystemException]. 값은 로그·화면에 내보내지 않는다(호출하는 쪽 책임).
// shortcut: 변수 치환(`${A}`)·여러 줄 값은 지원하지 않는다. 샘플 프로젝트에서 필요해지면 추가한다.
Map<String, String> readEnvFile(String path) {
  final env = <String, String>{};
  for (var line in File(path).readAsLinesSync()) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trimLeft();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final raw = line.substring(eq + 1);
    var value = raw.trim();
    final close = value.startsWith('"') || value.startsWith("'") ? value.indexOf(value[0], 1) : -1;
    if (close > 0) {
      value = value.substring(1, close); // 닫는 따옴표 뒤(주석 등)는 버린다
    } else if (raw.indexOf(RegExp(r'\s#')) case final hash when hash >= 0) {
      value = raw.substring(0, hash).trim(); // `PORT=3000 # dev`. 공백 없이 붙은 `#` 는 값이다
    }
    env[line.substring(0, eq).trim()] = value;
  }
  return env;
}

import 'dart:convert';
import 'dart:io';

/// 실행 항목 로그 파일의 줄 형식과 회전 쓰기. 중계(`popoling-relay`)가 쓰고, 앱은 같은 형식으로 읽는다.

/// [secrets] 를 모두 `****` 로 가린다. 빈 값은 무시하고, 긴 값부터 가린다.
String maskSecrets(String text, Iterable<String> secrets) {
  // 긴 값부터 가려야 짧은 값이 긴 값의 일부를 먼저 갉아먹지 않는다.
  final masks = secrets.where((s) => s.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  return masks.fold(text, (acc, s) => acc.replaceAll(s, '****'));
}

/// 실행마다 맨 앞에 넣는 구분 줄.
String startLine(DateTime at) => '--- 시작 ${at.toIso8601String()} ---';

/// 출력 한 줄. stderr 는 `err`.
String outputLine(DateTime at, String text, {required bool isError}) =>
    '${at.toIso8601String()} ${isError ? 'err' : 'out'} | $text';

/// 실행이 끝났을 때 남기는 줄. 앱을 다시 켠 뒤 되살린 항목의 종료 코드를 여기서 읽는다.
String endLine(int exitCode) => '--- 끝 (종료 코드 $exitCode) ---';

final _end = RegExp(r'^--- 끝 \(종료 코드 (-?\d+)\) ---$');

/// [line] 이 [endLine] 이면 그 종료 코드, 아니면 null.
int? exitCodeOf(String line) => switch (_end.firstMatch(line)) {
      final m? => int.parse(m[1]!),
      null => null,
    };

/// 크기가 [maxBytes] 를 넘으면 `.log.1`, `.log.2` 로 밀어내며 줄을 쓰는 파일.
///
/// 로그를 못 써도 실행은 멈추지 않는다. 실패는 삼키고, 그 뒤 쓰기는 버린다.
class RotatingLogFile {
  RotatingLogFile(this.file, {this.maxBytes = 10 * 1024 * 1024, this.keep = 3});

  final File file;

  /// 파일 하나의 최대 크기(바이트).
  final int maxBytes;

  /// `.log` 를 포함해 남기는 파일 수.
  final int keep;

  IOSink? _sink;
  var _size = 0;

  Future<void> open() async {
    try {
      await file.parent.create(recursive: true);
      _size = file.existsSync() ? await file.length() : 0;
      _sink = file.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
  }

  Future<void> write(String line) async {
    if (_sink == null) return;
    try {
      final bytes = utf8.encode('$line\n');
      if (_size > 0 && _size + bytes.length > maxBytes) {
        await _sink!.close();
        _sink = null;
        try {
          await _rotate();
        } catch (_) {} // 다른 프로그램이 파일을 잡고 있으면 밀지 못한다. 그대로 이어 쓰고 maxBytes 뒤에 다시 시도한다.
        _size = 0;
        _sink = file.openWrite(mode: FileMode.append);
      }
      _sink!.add(bytes);
      _size += bytes.length;
      await _sink!.flush();
    } catch (_) {
      _sink = null;
    }
  }

  Future<void> close() async {
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  /// `.log.(keep-2)` … `.log.1` 을 한 칸씩 뒤로 밀고 `.log` 를 `.log.1` 로 옮긴다. 가장 오래된 것은 덮어쓴다.
  Future<void> _rotate() async {
    for (var i = keep - 2; i >= 1; i--) {
      final older = File('${file.path}.$i');
      if (older.existsSync()) await older.rename('${file.path}.${i + 1}');
    }
    await file.rename('${file.path}.1');
  }
}

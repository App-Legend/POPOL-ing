import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_runner_relay/log_file.dart';

void main() {
  late Directory tmp;
  final at = DateTime(2026, 11, 18, 10);

  setUp(() => tmp = Directory.systemTemp.createTempSync('log_file_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File logOf(String suffix) => File('${tmp.path}/p1/s1.log$suffix');

  Future<void> writeAll(List<String> lines, {int maxBytes = 10 * 1024 * 1024}) async {
    final f = RotatingLogFile(logOf(''), maxBytes: maxBytes);
    await f.open();
    for (final l in lines) {
      await f.write(l);
    }
    await f.close();
  }

  test('줄 형식: 시작 줄, 시각과 out/err, 끝 줄', () {
    expect(startLine(at), '--- 시작 ${at.toIso8601String()} ---');
    expect(outputLine(at, 'hello', isError: false), '${at.toIso8601String()} out | hello');
    expect(outputLine(at, 'boom', isError: true), '${at.toIso8601String()} err | boom');
    expect(endLine(3), '--- 끝 (종료 코드 3) ---');
    expect(exitCodeOf(endLine(3)), 3);
    expect(exitCodeOf(endLine(-1)), -1);
    expect(exitCodeOf('아무 줄'), isNull);
  });

  test('.env 값은 가리고, 빈 값은 무시하고, 긴 값부터 가린다', () {
    final text = maskSecrets('x=abcdef y=abc', ['', 'abc', 'abcdef']);
    expect(text, 'x=**** y=****');
  });

  test('줄마다 끝에 줄바꿈을 붙여 이어 쓴다', () async {
    await writeAll(['a', 'b']);
    await writeAll(['c']);
    expect(logOf('').readAsLinesSync(), ['a', 'b', 'c']);
  });

  test('10MB 를 넘으면 밀어내고 3개까지 남긴다', () async {
    await writeAll([for (var i = 0; i < 20; i++) 'line-${i.toString().padLeft(2, '0')}'], maxBytes: 30);
    expect(logOf('').existsSync(), isTrue);
    expect(logOf('.1').existsSync(), isTrue);
    expect(logOf('.2').existsSync(), isTrue);
    expect(logOf('.3').existsSync(), isFalse);
    expect(logOf('').readAsLinesSync().last, 'line-19');
    for (final f in [logOf(''), logOf('.1'), logOf('.2')]) {
      expect(f.lengthSync(), lessThanOrEqualTo(30));
    }
  });

  test('남아 있던 파일 크기부터 센다', () async {
    logOf('').createSync(recursive: true);
    logOf('').writeAsStringSync('a' * 90);
    await writeAll(['hi'], maxBytes: 92); // 90 + 'hi\n'(3) = 93 > 92
    expect(logOf('.1').readAsStringSync(), 'a' * 90);
    expect(logOf('').readAsStringSync(), 'hi\n');
  });

  test('크기는 문자 수가 아니라 UTF-8 바이트로 센다', () async {
    // 한 줄 '가나다라\n' 은 13바이트(5자). 두 줄이면 26바이트라 20 을 넘고, 글자로는 10자라 넘지 않는다.
    await writeAll(['가나다라', '가나다라'], maxBytes: 20);
    expect(logOf('.1').existsSync(), isTrue);
    expect(utf8.encode(logOf('.1').readAsStringSync()).length, lessThanOrEqualTo(20));
  });

  test('회전에 실패해도 줄을 잃지 않고 계속 쓴다', () async {
    Directory('${tmp.path}/p1/s1.log.1').createSync(recursive: true); // .log -> .log.1 이름 바꾸기가 막힌다
    await writeAll([for (var i = 0; i < 10; i++) 'line-$i'], maxBytes: 20);
    final text = logOf('').readAsStringSync();
    for (var i = 0; i < 10; i++) {
      expect(text, contains('line-$i'));
    }
  });

  test('폴더를 만들 수 없어도 예외 없이 끝난다', () async {
    final blocker = File('${tmp.path}/file')..writeAsStringSync('x');
    final f = RotatingLogFile(File('${blocker.path}/logs/s1.log'));
    await f.open();
    await f.write('a');
    await f.close();
  });
}

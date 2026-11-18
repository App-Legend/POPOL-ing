import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_runner/src/log/log_store.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';

void main() {
  late Directory tmp;
  const item = ItemRef(projectId: 'p1', serviceId: 's1');
  final at = DateTime(2026, 11, 18, 10);

  OutputLine out(String t) => OutputLine(t, isError: false, at: at);
  OutputLine err(String t) => OutputLine(t, isError: true, at: at);

  setUp(() => tmp = Directory.systemTemp.createTempSync('log_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LogStore store({int maxBytes = 10 * 1024 * 1024}) => LogStore(() async => tmp, maxBytes: maxBytes);

  File logOf(String suffix) => File('${tmp.path}/p1/s1.log$suffix');

  test('줄마다 시각과 out/err 를 붙이고 실행마다 구분 줄을 넣는다', () async {
    final s = store();
    await s.record(item, Stream.fromIterable([out('hello'), err('boom')]));
    await s.record(item, Stream.fromIterable([out('hello'), err('boom')]));
    final lines = (await s.fileOf(item)).readAsLinesSync();
    expect(lines.length, 6);
    for (var i = 0; i < 2; i++) {
      expect(lines[i * 3], matches(RegExp(r'^--- 시작 \S+ ---$')));
      expect(lines[i * 3 + 1], matches(RegExp(r'^\S+ out \| hello$')));
      expect(lines[i * 3 + 2], matches(RegExp(r'^\S+ err \| boom$')));
    }
    expect(lines[1], startsWith(at.toIso8601String()));
  });

  test('.env 값은 가리고, 빈 값은 무시하고, 긴 값부터 가린다', () async {
    final s = store();
    await s.record(item, Stream.fromIterable([out('x=abcdef y=abc')]), secrets: ['', 'abc', 'abcdef']);
    final text = logOf('').readAsStringSync();
    expect(text, contains('x=**** y=****'));
    expect(text, isNot(contains('abc')));
  });

  test('10MB 를 넘으면 밀어내고 3개까지 남긴다', () async {
    final s = store(maxBytes: 100);
    await s.record(item, Stream.fromIterable([for (var i = 0; i < 20; i++) out('line-${i.toString().padLeft(2, '0')}')]));
    expect(logOf('').existsSync(), isTrue);
    expect(logOf('.1').existsSync(), isTrue);
    expect(logOf('.2').existsSync(), isTrue);
    expect(logOf('.3').existsSync(), isFalse);
    expect(logOf('').readAsLinesSync().last, endsWith('line-19'));
    for (final f in [logOf(''), logOf('.1'), logOf('.2')]) {
      expect(f.lengthSync(), lessThanOrEqualTo(100 + 40));
    }
  });

  test('남아 있던 파일 크기부터 센다', () async {
    logOf('').createSync(recursive: true);
    logOf('').writeAsStringSync('a' * 90);
    await store(maxBytes: 100).record(item, Stream.fromIterable([out('hi')]));
    expect(logOf('.1').readAsStringSync(), 'a' * 90);
    expect(logOf('').readAsStringSync(), contains('hi'));
  });

  test('크기는 문자 수가 아니라 UTF-8 바이트로 센다', () async {
    // 구분 줄(시각 정밀도에 따라 35~38자, 39~42바이트) + 한 줄 43바이트(35자) 두 개.
    // 바이트로는 125 이상이라 110 을 넘고, 글자로는 105~108 이라 넘지 않는다.
    await store(maxBytes: 110).record(item, Stream.fromIterable([out('가나다라'), out('가나다라')]));
    expect(logOf('.1').existsSync(), isTrue);
    expect(utf8.encode(logOf('.1').readAsStringSync()).length, lessThanOrEqualTo(110));
  });

  test('같은 항목 기록 두 개가 겹쳐도 줄이 섞이거나 사라지지 않는다', () async {
    final s = store();
    final a = StreamController<OutputLine>();
    final b = StreamController<OutputLine>();
    final fa = s.record(item, a.stream);
    final fb = s.record(item, b.stream);
    a.add(out('a1'));
    b.add(out('b1'));
    a.add(out('a2'));
    b.add(out('b2'));
    await a.close();
    await b.close();
    await Future.wait([fa, fb]);
    final lines = logOf('').readAsLinesSync().where((l) => l.contains(' | ')).map((l) => l.split(' | ').last).toList();
    expect(lines, ['a1', 'a2', 'b1', 'b2']);
  });

  test('입력 스트림이 오류를 내도 예외 없이 끝나고 다음 기록이 이어진다', () async {
    final s = store();
    final bad = Stream<OutputLine>.multi((c) {
      c.add(out('before'));
      c.addError('boom');
      c.close();
    });
    await s.record(item, bad);
    await s.record(item, Stream.fromIterable([out('after')]));
    final text = logOf('').readAsStringSync();
    expect(text, contains('before'));
    expect(text, contains('after'));
  });

  test('회전에 실패해도 줄을 잃지 않고 계속 쓴다', () async {
    Directory('${tmp.path}/p1/s1.log.1').createSync(recursive: true); // .log -> .log.1 이름 바꾸기가 막힌다
    await store(maxBytes: 100).record(item, Stream.fromIterable([for (var i = 0; i < 10; i++) out('line-$i')]));
    final text = logOf('').readAsStringSync();
    for (var i = 0; i < 10; i++) {
      expect(text, contains('line-$i'));
    }
  });

  test('폴더를 만들 수 없어도 예외 없이 끝난다', () async {
    final blocker = File('${tmp.path}/file')..writeAsStringSync('x');
    final s = LogStore(() async => Directory('${blocker.path}/logs'));
    await s.record(item, Stream.fromIterable([out('a'), out('b')]));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_runner/src/log/log_store.dart';

void main() {
  late Directory tmp;
  const item = ItemRef(projectId: 'p1', serviceId: 's1');

  setUp(() => tmp = Directory.systemTemp.createTempSync('log_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LogStore store() => LogStore(() async => tmp);

  File logOf(String suffix) => File('${tmp.path}/p1/s1.log$suffix');

  test('로그 파일은 <root>/<프로젝트>/<항목>.log', () async {
    expect((await store().fileOf(item)).path, logOf('').path);
  });

  test('tail 은 마지막 줄들만 돌려주고, 중간부터 읽으면 잘린 첫 줄은 버린다', () async {
    final s = store();
    expect(await s.tail(item), isEmpty, reason: '파일이 없으면 빈 목록');
    logOf('').createSync(recursive: true);
    logOf('').writeAsStringSync([for (var i = 0; i < 100; i++) 'line $i\n'].join());
    expect(await s.tail(item, lines: 3), ['line 97', 'line 98', 'line 99']);
    final cut = await s.tail(item, maxRead: 50);
    expect(cut, isNotEmpty);
    expect(cut.every((l) => RegExp(r'^line \d+$').hasMatch(l)), isTrue);
  });

  test('tail 은 아주 긴 한 줄뿐이면 그 끝부분을 돌려준다', () async {
    logOf('').createSync(recursive: true);
    logOf('').writeAsStringSync('${'x' * 200}끝\n');
    expect((await store().tail(item, maxRead: 50)).single, endsWith('x끝'));
  });

  test('tail 은 지금 파일 줄이 모자라면 막 밀려난 .log.1 끝에서 채운다', () async {
    logOf('.1').createSync(recursive: true);
    logOf('.1').writeAsStringSync('old 1\nold 2\nold 3\n');
    logOf('').writeAsStringSync('new 1\nnew 2\n');
    final s = store();
    expect(await s.tail(item, lines: 4), ['old 2', 'old 3', 'new 1', 'new 2']);
    expect(await s.tail(item, lines: 2), ['new 1', 'new 2']);
    logOf('').deleteSync();
    expect(await s.tail(item, lines: 2), ['old 2', 'old 3'], reason: '.log 가 없어도 .log.1 은 읽는다');
  });

  test('lastExitCode 는 마지막 줄이 끝 줄이면 그 종료 코드, 아니면 null', () async {
    final s = store();
    expect(await s.lastExitCode(item), isNull, reason: '파일이 없음');
    logOf('').createSync(recursive: true);
    logOf('').writeAsStringSync('a\n--- 끝 (종료 코드 2) ---\n');
    expect(await s.lastExitCode(item), 2);
    logOf('').writeAsStringSync('--- 끝 (종료 코드 2) ---\n--- 시작 x ---\n');
    expect(await s.lastExitCode(item), isNull, reason: '다시 시작한 뒤 아직 안 끝남');
  });
}

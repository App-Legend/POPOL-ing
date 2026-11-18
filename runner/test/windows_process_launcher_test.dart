@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';
import 'package:ppoling_runner/src/process/windows_process_launcher.dart';

void main() {
  final launcher = WindowsProcessLauncher();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ppoling_win_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<RunningProcess> start(List<String> command, {Map<String, String> env = const {}}) async {
    final p = await launcher.start(command, workingDirectory: dir.path, environment: env);
    addTearDown(() => p.stop(Duration.zero));
    return p;
  }

  test('ProcessLauncher.forPlatform 은 Windows 실행기를 고른다', () {
    expect(ProcessLauncher.forPlatform(), isA<WindowsProcessLauncher>());
  });

  test('stdout·stderr 를 줄 단위로 나눠 보내고 종료 코드를 알려준다', () async {
    final p = await start(['cmd', '/d', '/c', 'echo hello& echo oops 1>&2& exit /b 3']);
    final lines = await p.output.toList();
    expect(await p.exitCode, 3);
    expect(lines.where((l) => !l.isError).map((l) => l.text.trim()), ['hello']);
    expect(lines.where((l) => l.isError).map((l) => l.text.trim()), ['oops']);
  });

  test('PATH 의 .cmd 를 확장자 없이 실행한다 (npm 처럼)', () async {
    File('${dir.path}\\hello.cmd').writeAsStringSync('@echo hi %1\r\n');
    final p = await start(['hello', 'there'], env: {'Path': dir.path});
    final lines = await p.output.toList();
    expect(await p.exitCode, 0);
    expect(lines.map((l) => l.text.trim()), ['hi there']);
  });

  test('.cmd 에 특수문자 인자를 넘기면 실행하지 않고 안내한다', () async {
    File('${dir.path}\\hello.cmd').writeAsStringSync('@echo hi %1\r\n');
    final p = await start(['hello', 'a&calc'], env: {'PATH': dir.path});
    final lines = await p.output.toList();
    expect(await p.exitCode, 1);
    expect(lines.single.isError, isTrue);
  });

  test('없는 명령은 예외 대신 종료 코드 127', () async {
    final p = await start(['no-such-command-ppoling']);
    expect(await p.exitCode, 127);
  });

  test('멈추면 Job 째 멈춘다: 부모가 먼저 끝나고 손자만 남아도 멈춘다', () async {
    // cmd 가 (Job 에 들어갈 때까지 1초쯤 기다린 뒤) ping 을 따로 띄우고 바로 끝난다.
    // 손자 ping 은 1초마다 ping.txt 에 한 줄씩 쓰니, 파일이 자라는지로 살아 있는지 Job 과 따로 확인한다.
    final out = File('${dir.path}\\ping.txt');
    final p = await start(['cmd', '/d', '/c', 'ping -n 2 127.0.0.1 > nul & start /b ping -n 60 127.0.0.1 > ping.txt']);
    await p.exitCode;
    expect(await p.groupAlive, isTrue);
    final before = out.lengthSync();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(out.lengthSync(), greaterThan(before), reason: '손자 ping 이 아직 돌고 있어야 한다');

    final r = await p.stop(const Duration(seconds: 1));
    expect(r.forced, isTrue);
    expect(await p.groupAlive, isFalse);
    final after = out.lengthSync();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(out.lengthSync(), after, reason: '멈춘 뒤에는 손자 ping 도 더 쓰지 않아야 한다');
  });

  test('이미 끝난 프로세스를 멈추면 아무것도 하지 않는다', () async {
    final p = await start(['cmd', '/d', '/c', 'exit /b 0']);
    await p.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect((await p.stop(Duration.zero)).forced, isFalse);
  });
}

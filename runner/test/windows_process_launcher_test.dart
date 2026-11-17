@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';
import 'package:ppoling_runner/src/process/windows_process_launcher.dart';

/// 명령줄에 [marker] 가 든 ping 프로세스의 수.
Future<int> countProcesses(String marker) async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "(Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$marker*' -and \$_.Name -eq 'ping.exe' }).Count",
  ]);
  return int.tryParse((r.stdout as String).trim()) ?? 0;
}

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
    final marker = '-l ${1000 + pid % 50000}'; // 이 테스트가 띄운 ping 만 세려고 보낼 크기를 표시로 쓴다
    // cmd 가 (Job 에 들어갈 때까지 1초쯤 기다린 뒤) ping 을 따로 띄우고 바로 끝난다. ping 은 손자로 남는다.
    final p = await start(['cmd', '/d', '/c', 'ping -n 2 127.0.0.1 > nul & start /b ping -n 60 $marker 127.0.0.1 > nul']);
    await p.exitCode;
    expect(await p.groupAlive, isTrue);
    expect(await countProcesses(marker), 1);

    final r = await p.stop(const Duration(seconds: 1));
    expect(r.forced, isTrue);
    expect(await p.groupAlive, isFalse);
    expect(await countProcesses(marker), 0);
  });

  test('이미 끝난 프로세스를 멈추면 아무것도 하지 않는다', () async {
    final p = await start(['cmd', '/d', '/c', 'exit /b 0']);
    await p.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect((await p.stop(Duration.zero)).forced, isFalse);
  });
}

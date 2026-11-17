@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_runner/src/process/posix_process_launcher.dart';
import 'package:ppoling_runner/src/process/shell_path.dart';

/// [body] 를 실행하는 가짜 셸 스크립트를 만든다.
String fakeShell(String body) {
  final dir = Directory.systemTemp.createTempSync('ppoling_shell_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/fake-shell')..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

void main() {
  test('로그인 셸의 PATH 를 앞에 두고, 지금 PATH 와 Homebrew 경로를 뒤에 붙인다', () async {
    final shell = fakeShell(r'printf "noise from .zshrc\n__PPOLING_PATH__/nvm/bin:/usr/bin__PPOLING_PATH__\n"');
    final path = await loginShellPath(environment: {'SHELL': shell, 'PATH': '/usr/bin:/bin'});
    expect(path.split(':'), ['/nvm/bin', '/usr/bin', '/bin', '/opt/homebrew/bin', '/usr/local/bin']);
  });

  test('셸이 제한 시간 안에 답하지 않으면 지금 PATH 와 Homebrew 경로만 쓴다', () async {
    final shell = fakeShell('sleep 10');
    final path = await loginShellPath(
        environment: {'SHELL': shell, 'PATH': '/usr/bin:/bin'}, timeout: const Duration(milliseconds: 300));
    expect(path.split(':'), ['/usr/bin', '/bin', '/opt/homebrew/bin', '/usr/local/bin']);
  });

  test('셸이 실패해도 예외 없이 기본 경로를 쓴다', () async {
    final path = await loginShellPath(environment: {'SHELL': '/no/such/shell', 'PATH': '/bin'});
    expect(path.split(':'), ['/bin', '/opt/homebrew/bin', '/usr/local/bin']);
  });

  test('이 컴퓨터의 진짜 로그인 셸에서도 PATH 를 받아온다', () async {
    final path = await loginShellPath();
    expect(path.split(':'), contains('/usr/bin'));
  });

  test('실행기는 받아온 PATH 로 명령을 찾고, 항목에 적은 PATH 가 있으면 그걸 쓴다', () async {
    final dir = Directory.systemTemp.createTempSync('ppoling_bin_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tool = File('${dir.path}/ppoling-hello')..writeAsStringSync('#!/bin/sh\necho hello from tool\n');
    Process.runSync('chmod', ['+x', tool.path]);

    final launcher = PosixProcessLauncher(searchPath: () async => '${dir.path}:/usr/bin:/bin');
    final found = await launcher.start(['ppoling-hello'], workingDirectory: dir.path);
    expect((await found.output.toList()).map((l) => l.text), ['hello from tool']);

    final overridden = await launcher.start(['ppoling-hello'], workingDirectory: dir.path, environment: {'PATH': '/usr/bin:/bin'});
    await overridden.output.drain<void>();
    expect(await overridden.exitCode, 127);
  });
}

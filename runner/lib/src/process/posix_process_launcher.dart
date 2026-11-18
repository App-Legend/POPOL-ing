import 'dart:async';
import 'dart:io';

import 'process_launcher.dart';
import 'shell_path.dart';

/// macOS(와 Linux) 구현. 새 프로세스 그룹으로 띄우고, 멈출 때 그룹 전체에 신호를 보낸다.
///
/// 일반 `Process.kill()` 은 띄운 프로세스 하나에만 신호를 보내 `npm` 이 띄운 `node` 같은 손자가 남는다.
/// Dart 에는 그룹을 만들며 띄우는 방법이 없어 perl 의 `setpgrp` 뒤에 명령으로 `exec` 한다(pid == pgid).
///
/// 명령은 [searchPath] 의 PATH 에서 찾는다(기본은 로그인 셸의 PATH, 처음 한 번만 구한다).
/// 항목 설정의 `env` 에 PATH 가 있으면 그걸 쓴다.
class PosixProcessLauncher implements ProcessLauncher {
  PosixProcessLauncher({this.searchPath = loginShellPath});

  // shortcut: macOS 기본 perl(/usr/bin/perl)에 기댄다. 빠지는 macOS 가 나오면 FFI posix_spawn 으로 바꾼다.
  static const _perl = '/usr/bin/perl';
  static const _script = r'setpgrp(0, 0); exec { $ARGV[0] } @ARGV or do { print STDERR "명령을 찾을 수 없어요: $ARGV[0]\n"; exit 127 }';

  final Future<String> Function() searchPath;
  Future<String>? _path;

  @override
  Future<RunningProcess> start(
    List<String> command, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    if (command.isEmpty) throw ArgumentError.value(command, 'command', '실행할 명령이 비어 있어요');
    final process = await Process.start(
      _perl,
      ['-e', _script, '--', ...command], // -- 가 없으면 '-' 로 시작하는 명령을 perl 이 스위치로 먹는다
      workingDirectory: workingDirectory,
      environment: {'PATH': await (_path ??= searchPath()), ...environment},
    );
    process.stdin.close().ignore(); // 입력을 기다리는 명령이 영영 멈춰 있지 않게 바로 EOF 를 준다
    return _PosixProcess(process, DateTime.now());
  }
}

class _PosixProcess implements RunningProcess {
  _PosixProcess(this._process, this.startedAt) : output = outputLines(_process) {
    _process.exitCode.then((_) => _exited = true);
  }

  final Process _process;

  /// 리더가 끝났다(Dart 가 거뒀다). 그 뒤로 그룹 번호를 지켜 주는 건 남은 자식뿐이다.
  var _exited = false;

  /// 리더가 끝난 뒤 그룹이 비었다. 그 번호는 남이 다시 쓸 수 있으니 다시는 신호를 보내지 않는다.
  var _gone = false;

  @override
  final DateTime startedAt;

  @override
  int get pid => _process.pid;

  @override
  int get pgid => _process.pid;

  @override
  final Stream<OutputLine> output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<StopResult> stop(Duration timeout) async {
    if (!_exited && !await groupAlive) {
      // 띄운 직후라 perl 이 아직 setpgrp 전이다. 리더는 아직 거두지 않은 내 자식이라 PID 로 멈춰도 남의 프로세스가 아니다.
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
    if (!await groupAlive) return const StopResult(forced: false);
    await _signalGroup('TERM');

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await groupAlive) return const StopResult(forced: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!await groupAlive) return const StopResult(forced: false);
    await _signalGroup('KILL');
    return const StopResult(forced: true);
  }

  // 그룹에 프로세스가 하나라도 남아 있는 동안은 같은 번호가 다른 프로세스에 재사용되지 않는다.
  @override
  Future<bool> get groupAlive async {
    if (_gone) return false;
    final alive = (await Process.run('kill', ['-0', '--', '-$pgid'])).exitCode == 0;
    if (!alive && _exited) _gone = true;
    return alive;
  }

  Future<void> _signalGroup(String signal) => Process.run('kill', ['-$signal', '--', '-$pgid']);
}

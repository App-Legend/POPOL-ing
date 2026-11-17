import 'dart:async';
import 'dart:io';

import 'process_launcher.dart';
import 'windows_command.dart';
import 'windows_job.dart';

/// Windows 구현. 띄운 프로세스를 Job Object 에 넣고, 멈출 때 Job 째 끝낸다.
///
/// 일반 `Process.kill()` 은 띄운 프로세스 하나만 멈춰 `npm` 이 띄운 `node` 같은 손자가 남는다.
/// Job 에 넣은 뒤 생긴 자식·손자는 부모가 먼저 끝나도 같은 Job 에 남는다.
///
/// 명령은 PATH·PATHEXT 로 찾는다([resolveWindowsCommand]). 항목 설정의 `env` 에 PATH 가 있으면 그걸 쓴다.
class WindowsProcessLauncher implements ProcessLauncher {
  @override
  Future<RunningProcess> start(
    List<String> command, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    if (command.isEmpty) throw ArgumentError.value(command, 'command', '실행할 명령이 비어 있어요');
    if (!Directory(workingDirectory).existsSync()) {
      throw ProcessException(command.first, command.sublist(1), '작업 폴더가 없어요: $workingDirectory');
    }
    String? env(String key) =>
        environment.entries.where((e) => e.key.toUpperCase() == key).map((e) => e.value).firstOrNull ??
        Platform.environment[key]; // Windows 의 Platform.environment 는 대소문자를 가리지 않는다

    // CreateProcess 는 상대 경로를 새 작업 폴더가 아니라 앱의 폴더 기준으로 찾으니 미리 붙인다.
    final name = command.first;
    final relative = name.contains(RegExp(r'[\\/]')) && !name.contains(RegExp(r'^([A-Za-z]:)?[\\/]'));
    final resolved = resolveWindowsCommand(
      [relative ? '$workingDirectory\\$name' : name, ...command.sublist(1)],
      path: env('PATH') ?? '',
      pathExt: env('PATHEXT') ?? '.COM;.EXE;.BAT;.CMD',
      comSpec: env('COMSPEC') ?? r'C:\Windows\System32\cmd.exe',
      exists: (f) => File(f).existsSync(),
    );
    switch (resolved) {
      case RefuseCommand(:final message, :final exitCode):
        return _RefusedProcess(message, exitCode);
      case RunCommand(:final executable, :final arguments):
        // Job 을 먼저 만든다. 띄운 뒤에 만들다 실패하면 띄운 프로세스를 아무도 모르게 된다.
        final job = WindowsJob();
        final Process process;
        try {
          process = await Process.start(executable, arguments, workingDirectory: workingDirectory, environment: environment);
        } catch (_) {
          job.close();
          rethrow;
        }
        process.stdin.close().ignore(); // 입력을 기다리는 명령이 영영 멈춰 있지 않게 바로 EOF 를 준다
        // shortcut: 띄운 뒤 Job 에 넣기까지의 아주 짧은 틈에 생긴 자식은 Job 밖에 남을 수 있다.
        // 문제가 되면 CreateProcessW(CREATE_SUSPENDED)로 띄워 Job 에 넣은 뒤 재개하도록 바꾼다.
        return _WindowsProcess(process, job, DateTime.now(), job.assign(process.pid));
    }
  }
}

class _WindowsProcess implements RunningProcess {
  _WindowsProcess(this._process, this._job, this.startedAt, this._assigned) : output = outputLines(_process) {
    _process.exitCode.then((_) => _exited = true);
  }

  final Process _process;
  final WindowsJob _job;

  /// Job 에 넣지 못했다(띄우자마자 끝났거나 권한이 없음). 그러면 띄운 프로세스 하나만 다룬다.
  final bool _assigned;
  var _exited = false;

  @override
  final DateTime startedAt;

  @override
  int get pid => _process.pid;

  /// Windows 에는 프로세스 그룹이 없다. 묶음은 Job 이 맡으니 PID 를 그대로 돌려준다.
  @override
  int get pgid => _process.pid;

  @override
  final Stream<OutputLine> output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<bool> get groupAlive async {
    // Job 에 묻지 못하면 띄운 프로세스가 끝났는지로 대신한다(영영 살아 있다고 보지 않게).
    final alive = _assigned ? (_job.activeProcesses ?? (_exited ? 0 : 1)) > 0 : !_exited;
    if (!alive && _exited) _job.close(); // 다 끝났으니 핸들을 돌려준다
    return alive;
  }

  // shortcut: 정상 종료 신호 없이 바로 Job 째 강제 종료하므로 [timeout] 을 쓰지 않고 항상 forced 다.
  // 콘솔 프로그램에 CTRL_BREAK 를 따로 보내려면 새 콘솔 그룹으로 띄워야 해서 CreateProcessW 로 바꿀 때 함께 한다.
  @override
  Future<StopResult> stop(Duration timeout) async {
    if (!await groupAlive) return const StopResult(forced: false);
    if (!_assigned || !_job.terminate()) {
      _process.kill(); // 아직 거두지 않은 내 자식이라 PID 가 재사용되지 않았다
    }
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await groupAlive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const StopResult(forced: true);
  }
}

/// 띄우지 않은 명령. 띄운 것처럼 안내 한 줄과 종료 코드를 알린다.
class _RefusedProcess implements RunningProcess {
  _RefusedProcess(String message, int code)
      : output = Stream.value(OutputLine(message, isError: true, at: DateTime.now())),
        exitCode = Future.value(code);

  @override
  int get pid => 0;

  @override
  int get pgid => 0;

  @override
  final DateTime startedAt = DateTime.now();

  @override
  final Stream<OutputLine> output;

  @override
  final Future<int> exitCode;

  @override
  Future<bool> get groupAlive async => false;

  @override
  Future<StopResult> stop(Duration timeout) async => const StopResult(forced: false);
}

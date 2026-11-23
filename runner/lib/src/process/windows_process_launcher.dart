import 'dart:async';
import 'dart:io';

import 'package:popoling_runner_relay/relay_request.dart';

import 'process_launcher.dart';
import 'windows_command.dart';
import 'windows_job.dart';

/// Windows 구현. 중계를 이름 붙은 Job Object 에 넣어 띄우고, 멈출 때 Job 째 끝낸다.
///
/// 일반 `Process.kill()` 은 띄운 프로세스 하나만 멈춰 `npm` 이 띄운 `node` 같은 손자가 남는다.
/// Job 에 넣은 뒤 생긴 자식·손자는 부모가 먼저 끝나도 같은 Job 에 남는다.
/// 중계도 같은 Job 핸들을 쥐고 있어서, 앱을 다시 켠 뒤 Job 이름으로 다시 붙는다.
///
/// 명령은 PATH·PATHEXT 로 찾는다([resolveWindowsCommand]). 항목 설정의 `env` 에 PATH 가 있으면 그걸 쓴다.
class WindowsProcessLauncher implements ProcessLauncher {
  WindowsProcessLauncher({required this.relay});

  final String relay;

  @override
  Future<AttachResult> attach({required int pid, required DateTime startedAt, String? jobName}) async {
    try {
      if (jobName != null) {
        if (WindowsJob.open(jobName) case final job?) {
          if (job.contains(pid)) return Attached(_AttachedProcess(job, pid, startedAt, jobName));
          job.close();
          return const Unverified();
        }
      }
      // Job 이 없으면(예전 기록, 중계가 죽음) 증명할 수 없다. 살아 있으면 확인 불가로만 알린다.
      return windowsProcessAlive(pid) ? const Unverified() : const Gone();
    } catch (_) {
      return const Unverified(); // 확인하지 못했으면 내 것이라고 하지 않는다
    }
  }

  @override
  Future<RunningProcess> start(
    List<String> command, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    required LogTarget log,
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
        return RefusedProcess(message, exitCode);
      case RunCommand(:final executable, :final arguments):
        if (!File(relay).existsSync()) return RefusedProcess('중계 프로그램을 찾을 수 없어요.', 127);
        // Job 을 먼저 만든다. 띄운 뒤에 만들다 실패하면 띄운 프로세스를 아무도 모르게 된다.
        final jobName = 'popoling-$pid-${DateTime.now().microsecondsSinceEpoch}';
        final job = WindowsJob(name: jobName);
        final Process process;
        try {
          process = await Process.start(relay, const [], workingDirectory: workingDirectory, environment: environment);
        } catch (_) {
          job.close();
          rethrow;
        }
        final startedAt = DateTime.now();
        // 요청을 넘기기 전에 Job 에 넣어야, 중계가 띄우는 명령이 처음부터 Job 안에서 생긴다.
        final assigned = job.assign(process.pid);
        process.stdin.writeln(RelayRequest(
          command: [executable, ...arguments],
          logFile: log.file.path,
          secrets: log.secrets,
          jobName: jobName,
          maxBytes: log.maxBytes,
          keep: log.keep,
        ).encode());
        process.stdin.close().ignore();
        return _WindowsProcess(process, job, startedAt, assigned, jobName);
    }
  }
}

class _WindowsProcess implements RunningProcess {
  _WindowsProcess(this._process, this._job, this.startedAt, this._assigned, this.jobName) : output = outputLines(_process) {
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
  final String jobName;

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

  // Job 핸들로 묻으니 PID 가 재사용돼도 남의 프로세스를 내 것으로 보지 않는다.
  @override
  Future<bool> contains(int pid) async => _assigned ? _job.contains(pid) : !_exited && pid == _process.pid;

  // shortcut: 정상 종료 신호 없이 바로 Job 째 강제 종료하므로 [timeout] 을 쓰지 않고 항상 forced 다.
  // 콘솔 프로그램에 CTRL_BREAK 를 따로 보내려면 새 콘솔 그룹으로 띄워야 해서 CreateProcessW 로 바꿀 때 함께 한다.
  @override
  Future<StopResult> stop(Duration timeout) async {
    if (!await groupAlive) return const StopResult(forced: false);
    // 이미 끝난 리더는 PID 로 다시 열려 남의 프로세스를 멈출 수 있으니, 살아 있을 때만 PID 로 멈춘다.
    if ((!_assigned || !_job.terminate()) && !_exited) _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await groupAlive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const StopResult(forced: true);
  }
}

/// 앱을 다시 켜기 전에 띄운 중계. Job 이름으로 다시 연 핸들로만 다룬다.
class _AttachedProcess implements RunningProcess {
  _AttachedProcess(this._job, this.pid, this.startedAt, this.jobName) {
    exitCode = () async {
      while (await groupAlive) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      _job.close();
      return -1;
    }();
  }

  final WindowsJob _job;

  @override
  final int pid;

  @override
  final DateTime startedAt;

  @override
  final String jobName;

  @override
  late final Future<int> exitCode;

  @override
  int get pgid => pid;

  @override
  Stream<OutputLine> get output => const Stream.empty();

  // 물어보지 못하면 살아 있다고 본다. 끝났다고 잘못 보면 [중지] 할 방법을 잃는다.
  @override
  Future<bool> get groupAlive async => (_job.activeProcesses ?? 1) > 0;

  @override
  Future<bool> contains(int pid) async => _job.contains(pid);

  // shortcut: 새로 띄운 것과 같이 정상 종료 신호 없이 Job 째 강제 종료한다.
  @override
  Future<StopResult> stop(Duration timeout) async {
    if (!await groupAlive) return const StopResult(forced: false);
    _job.terminate();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await groupAlive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const StopResult(forced: true);
  }
}

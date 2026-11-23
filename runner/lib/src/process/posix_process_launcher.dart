import 'dart:async';
import 'dart:io';

import 'package:popoling_runner_relay/relay_request.dart';

import 'process_launcher.dart';
import 'shell_path.dart';

/// macOS(와 Linux) 구현. 중계가 새 프로세스 그룹의 리더가 되어 명령을 띄우고, 멈출 때 그룹 전체에 신호를 보낸다.
///
/// 일반 `Process.kill()` 은 띄운 프로세스 하나에만 신호를 보내 `npm` 이 띄운 `node` 같은 손자가 남는다.
/// 중계는 명령이 끝날 때까지 살아 있으니(pid == pgid), 앱을 다시 켠 뒤에도 중계로 소유권을 증명한다.
///
/// 명령은 [searchPath] 의 PATH 에서 찾는다(기본은 로그인 셸의 PATH, 처음 한 번만 구한다).
/// 항목 설정의 `env` 에 PATH 가 있으면 그걸 쓴다.
class PosixProcessLauncher implements ProcessLauncher {
  PosixProcessLauncher({required this.relay, this.searchPath = loginShellPath});

  final String relay;
  final Future<String> Function() searchPath;
  Future<String>? _path;

  @override
  Future<RunningProcess> start(
    List<String> command, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    required LogTarget log,
  }) async {
    if (command.isEmpty) throw ArgumentError.value(command, 'command', '실행할 명령이 비어 있어요');
    if (!File(relay).existsSync()) return RefusedProcess('중계 프로그램을 찾을 수 없어요.', 127);
    final process = await Process.start(
      relay,
      const [],
      workingDirectory: workingDirectory,
      environment: {'PATH': await (_path ??= searchPath()), ...environment},
    );
    final startedAt = DateTime.now();
    process.stdin.writeln(RelayRequest(
      command: command,
      logFile: log.file.path,
      secrets: log.secrets,
      maxBytes: log.maxBytes,
      keep: log.keep,
    ).encode());
    process.stdin.close().ignore();
    return _PosixProcess(process, startedAt);
  }

  @override
  Future<AttachResult> attach({required int pid, required DateTime startedAt, String? jobName}) async {
    try {
      // comm 대신 명령줄(args)을 본다. Linux 에서 Dart 실행 파일은 comm 을 'dart:popoling-re' 로 바꾼다.
      // 중계는 인자 없이 띄우니 명령줄이 실행 파일 경로로 끝난다.
      final r = await Process.run('ps', ['-o', 'pgid=,lstart=,args=', '-p', '$pid'], environment: {'LC_ALL': 'C'});
      // 예: "  812 Sun Nov 22 10:00:00 2026     /Applications/포폴링.app/Contents/MacOS/popoling-relay"
      final f = (r.stdout as String).trim().split(RegExp(r'\s+'));
      if (r.exitCode == 0 && f.length >= 7) {
        final lstart = _parseLstart(f.sublist(1, 6));
        final mine = int.tryParse(f[0]) == pid &&
            f.sublist(6).join(' ').endsWith('popoling-relay') &&
            lstart != null &&
            lstart.difference(startedAt).abs() <= const Duration(seconds: 2);
        return mine ? Attached(_AttachedProcess(pid, startedAt)) : const Unverified();
      }
      return await _groupAlive(pid) ? const Unverified() : const Gone();
    } catch (_) {
      return const Unverified(); // 확인하지 못했으면 내 것이라고 하지 않는다
    }
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `ps -o lstart` 의 `Sun Nov 22 10:00:00 2026`(LC_ALL=C, 지역 시각). 읽지 못하면 null.
DateTime? _parseLstart(List<String> f) {
  final month = _months.indexOf(f[1]) + 1;
  final t = f[3].split(':').map(int.tryParse).toList();
  final day = int.tryParse(f[2]), year = int.tryParse(f[4]);
  if (month == 0 || day == null || year == null || t.length != 3 || t.contains(null)) return null;
  return DateTime(year, month, day, t[0]!, t[1]!, t[2]!);
}

// 그룹에 프로세스가 하나라도 남아 있는 동안은 같은 번호가 다른 프로세스에 재사용되지 않는다.
Future<bool> _groupAlive(int pgid) async => (await Process.run('kill', ['-0', '--', '-$pgid'])).exitCode == 0;

Future<void> _signalGroup(int pgid, String signal) => Process.run('kill', ['-$signal', '--', '-$pgid']);

// 그룹이 살아 있는 동안은 번호가 재사용되지 않으니, 그 번호의 그룹에 들었으면 내가 띄운 것이다.
Future<bool> _inGroup(int pid, int pgid) async {
  final r = await Process.run('ps', ['-o', 'pgid=', '-p', '$pid']);
  return r.exitCode == 0 && int.tryParse((r.stdout as String).trim()) == pgid;
}

/// 그룹 전체에 TERM 을 보내고 [timeout] 동안 기다린 뒤, 남아 있으면 KILL 한다.
Future<StopResult> _stopGroup(int pgid, Duration timeout, Future<bool> Function() alive) async {
  if (!await alive()) return const StopResult(forced: false);
  await _signalGroup(pgid, 'TERM');
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!await alive()) return const StopResult(forced: false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!await alive()) return const StopResult(forced: false);
  await _signalGroup(pgid, 'KILL');
  return const StopResult(forced: true);
}

/// 이번에 띄운 중계.
class _PosixProcess implements RunningProcess {
  _PosixProcess(this._process, this.startedAt) : output = outputLines(_process) {
    _process.exitCode.then((_) => _exited = true);
  }

  final Process _process;

  /// 중계가 끝났다(Dart 가 거뒀다). 그 뒤로 그룹 번호를 지켜 주는 건 남은 자식뿐이다.
  var _exited = false;

  /// 중계가 끝난 뒤 그룹이 비었다. 그 번호는 남이 다시 쓸 수 있으니 다시는 신호를 보내지 않는다.
  var _gone = false;

  @override
  final DateTime startedAt;

  @override
  String? get jobName => null;

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
      // 띄운 직후라 중계가 아직 그룹을 만들기 전이다. 중계는 아직 거두지 않은 내 자식이라 PID 로 멈춰도 남의 프로세스가 아니다.
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
    return _stopGroup(pgid, timeout, () => groupAlive);
  }

  @override
  Future<bool> get groupAlive async {
    if (_gone) return false;
    final alive = await _groupAlive(pgid);
    if (!alive && _exited) _gone = true;
    return alive;
  }

  @override
  Future<bool> contains(int pid) async => await groupAlive && await _inGroup(pid, pgid);
}

/// 앱을 다시 켜기 전에 띄운 중계. 내 자식이 아니라 종료 코드를 받을 수 없어 그룹이 빌 때까지 지켜본다.
class _AttachedProcess implements RunningProcess {
  _AttachedProcess(this.pid, this.startedAt) {
    exitCode = () async {
      while (await groupAlive) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return -1;
    }();
  }

  @override
  final int pid;

  @override
  final DateTime startedAt;

  /// 그룹이 비었다. 그 번호는 남이 다시 쓸 수 있으니 다시는 신호를 보내지 않는다.
  var _gone = false;

  @override
  late final Future<int> exitCode;

  @override
  String? get jobName => null;

  @override
  int get pgid => pid;

  @override
  Stream<OutputLine> get output => const Stream.empty();

  // shortcut: 그룹이 빈 뒤 다음 확인(1초) 전에 같은 번호가 재사용되면 놓친다(PID 한 바퀴가 1초 안에 돌 때만).
  @override
  Future<bool> get groupAlive async {
    if (_gone) return false;
    final alive = await _groupAlive(pgid);
    if (!alive) _gone = true;
    return alive;
  }

  @override
  Future<bool> contains(int pid) async => await groupAlive && await _inGroup(pid, pgid);

  @override
  Future<StopResult> stop(Duration timeout) => _stopGroup(pgid, timeout, () => groupAlive);
}

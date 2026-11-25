import 'dart:async';
import 'dart:io';

import 'package:popoling_core/contracts.dart';

import '../port_owner/port_owner_lookup.dart';
import 'version.dart';
import 'windows_cli.dart';

export '../port_owner/port_owner_lookup.dart' show RunProcess;

/// 명령 이름과 인자로 실제 실행할 `[실행 파일, ...인자]` 를 정한다. 못 찾으면 null(미설치).
/// 실행하면 안 되는 경로면 [FormatException].
typedef ResolveCli = List<String>? Function(String cli, List<String> args);

/// 환경 점검(FR-07)의 진짜 구현. `requires` 의 명령을 실제로 실행해 버전을 읽는다.
///
/// - 버전은 `<명령> --version` 의 출력(stdout·stderr)에서 처음 나오는 `x.y(.z)` 로 읽는다.
///   출력 방식이 다른 도구만 [_versionArgs] 에 따로 적는다.
/// - 명령 이름은 [_safeName] 만 실행한다. popoling.yaml 은 남이 만든 것일 수 있어서.
/// - 명령마다 [timeout] 안에 답이 없으면 점검 실패로 본다.
class SystemEnvChecker implements EnvChecker {
  SystemEnvChecker({RunProcess run = runProcess, ResolveCli? resolve, this.timeout = const Duration(seconds: 10)})
      // ignore: prefer_initializing_formals, 이름 있는 매개변수는 _ 로 시작할 수 없다
      : _run = run,
        _resolve = resolve ?? resolveCliForPlatform;

  final RunProcess _run;
  final ResolveCli _resolve;

  /// 명령 하나를 기다리는 시간.
  final Duration timeout;

  static final _safeName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// `--version` 이 아닌 도구. java 는 `-version` 으로 stderr 에, go 는 `version` 으로 답한다.
  static const _versionArgs = {
    'java': ['-version'],
    'go': ['version'],
  };

  @override
  Future<List<EnvCheckResult>> check(List<Requirement> requires) async =>
      List.unmodifiable(await Future.wait([for (final r in requires) _check(r)]));

  Future<EnvCheckResult> _check(Requirement requirement) async {
    try {
      return switch (requirement) {
        CliRequirement() => await _cli(requirement),
        DockerRequirement() => await _docker(requirement),
      };
    } on Object catch (e) {
      // 약속: 점검 중 문제는 예외 대신 결과로 돌려준다.
      return EnvCheckResult(requirement: requirement, status: EnvStatus.checkFailed, message: '점검하다 문제가 생겼어요: $e');
    }
  }

  Future<EnvCheckResult> _cli(CliRequirement r) async {
    EnvCheckResult result(EnvStatus status, {String? found, String? message}) =>
        EnvCheckResult(requirement: r, status: status, foundVersion: found, message: message);
    final cli = r.cli;

    if (!_safeName.hasMatch(cli) || cli.startsWith('.')) {
      return result(EnvStatus.checkFailed, message: '명령 이름에는 영문·숫자·. - _ 만 쓸 수 있어요: "$cli"');
    }
    final output = await _call(cli, _versionArgs[cli] ?? const ['--version']);
    switch (output) {
      case _NotFound():
        return result(EnvStatus.notInstalled, message: '$cli 명령을 찾을 수 없어요. 설치했다면 PATH 에 들어 있는지 확인해 주세요.');
      case _Failed(:final message):
        return result(EnvStatus.checkFailed, message: message);
      case _Output(:final text, :final exitCode):
        final found = readVersion(text);
        // 실패로 끝났고 버전도 없으면 설치됐다고 볼 수 없다(예: Java 가 없는 macOS 의 /usr/bin/java).
        if (exitCode != 0 && found == null) {
          final said = text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
          return result(EnvStatus.checkFailed, message: '$cli 가 실패했어요(종료 코드 $exitCode)${said.isEmpty ? '' : ': $said'}');
        }
        final range = r.version;
        if (range == null) return result(EnvStatus.passed, found: found);
        if (versionAllows(range, '0') == null) return result(EnvStatus.checkFailed, found: found, message: '버전 조건을 읽을 수 없어요: $range');
        if (found == null) return result(EnvStatus.checkFailed, message: '$cli 버전을 읽지 못했어요.');
        return versionAllows(range, found)!
            ? result(EnvStatus.passed, found: found)
            : result(EnvStatus.versionMismatch, found: found, message: '$range 이 필요한데 지금은 $found 이에요.');
    }
  }

  Future<EnvCheckResult> _docker(DockerRequirement r) async {
    final output = await _call('docker', const ['version', '--format', '{{.Server.Version}}'], requireSuccess: true);
    return switch (output) {
      _NotFound() => EnvCheckResult(
          requirement: r, status: EnvStatus.notInstalled, message: 'docker 명령을 찾을 수 없어요. Docker Desktop 을 설치해 주세요.'),
      _Failed() => EnvCheckResult(
          requirement: r, status: EnvStatus.daemonNotRunning, message: 'Docker 가 꺼져 있어요. Docker Desktop 을 실행해 주세요.'),
      _Output(:final text) => EnvCheckResult(
          requirement: r, status: EnvStatus.passed, foundVersion: readVersion(text) ?? text.trim()),
    };
  }

  /// [cli] 를 [args] 로 실행한다. [requireSuccess] 면 종료 코드가 0 이 아닐 때 [_Failed].
  Future<_CallResult> _call(String cli, List<String> args, {bool requireSuccess = false}) async {
    final List<String>? command;
    try {
      command = _resolve(cli, args);
    } on FormatException catch (e) {
      return _Failed(e.message);
    }
    if (command == null) return const _NotFound();
    try {
      // shortcut: 시간을 넘긴 명령은 기다리지 않을 뿐 끝까지 죽이지는 않는다. 버전 명령은 금방 끝나서.
      final r = await _run(command.first, command.sublist(1)).timeout(timeout);
      if (requireSuccess && r.exitCode != 0) return _Failed('${r.stderr}'.trim());
      return _Output('${r.stdout}\n${r.stderr}', r.exitCode);
    } on ProcessException {
      return const _NotFound();
    } on TimeoutException {
      return _Failed('$cli 가 ${timeout.inSeconds}초 안에 답하지 않았어요.');
    }
  }

}

/// 이 OS 에서 [cli] 를 [args] 로 실행할 `[실행 파일, ...인자]`. 못 찾으면 null(미설치).
/// Windows 에서 경로가 안전하지 않은 `.cmd`·`.bat` 이면 [FormatException].
List<String>? resolveCliForPlatform(String cli, List<String> args) {
  if (!Platform.isWindows) return [cli, ...args]; // macOS 는 Process.run 이 PATH 에서 찾고, 없으면 ProcessException
  final env = Platform.environment;
  return resolveWindowsCli(
    cli,
    args,
    path: env['PATH'] ?? env['Path'] ?? '',
    pathExt: env['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD',
    comSpec: env['ComSpec'] ?? env['COMSPEC'] ?? r'C:\Windows\System32\cmd.exe',
    exists: (f) => File(f).existsSync(),
  );
}

sealed class _CallResult {
  const _CallResult();
}

class _NotFound extends _CallResult {
  const _NotFound();
}

class _Failed extends _CallResult {
  const _Failed(this.message);
  final String message;
}

class _Output extends _CallResult {
  const _Output(this.text, this.exitCode);
  final String text;
  final int exitCode;
}

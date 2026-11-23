import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/env/system_env_checker.dart';
import 'package:popoling_checks/src/env/windows_cli.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/testing.dart';

void main() {
  group('SystemEnvChecker (이 컴퓨터)', () {
    late bool dockerRunning;
    setUpAll(() async {
      try {
        dockerRunning = (await Process.run('docker', ['version', '--format', '{{.Server.Version}}'])).exitCode == 0;
      } on ProcessException {
        dockerRunning = false;
      }
    });

    envCheckerContract(() async => EnvCheckerFixture(checker: SystemEnvChecker(), installedCli: 'git', dockerRunning: dockerRunning));
  });

  group('SystemEnvChecker (기록된 출력)', () {
    test('java 는 -version 으로 묻고 stderr 의 버전을 읽는다', () async {
      final calls = <List<String>>[];
      final checker = SystemEnvChecker(
        resolve: _direct,
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', 'openjdk version "17.0.9" 2023-10-17\n');
        },
      );
      final [r] = await checker.check([const CliRequirement('java', version: '>=17')]);
      expect(calls.single, ['java', '-version']);
      expect(r.status, EnvStatus.passed);
      expect(r.foundVersion, '17.0.9');
    });

    test('명령 이름에 셸이 해석할 글자가 있으면 실행하지 않고 점검 실패', () async {
      var ran = false;
      final checker = SystemEnvChecker(resolve: _direct, run: (_, _) async => (ran = true, _ok('1.0.0')).$2);
      final results = await checker.check(const [CliRequirement('node & calc'), CliRequirement('../node'), CliRequirement('')]);
      expect(ran, isFalse);
      expect(results.map((r) => r.status), everyElement(EnvStatus.checkFailed));
      expect(results.map((r) => r.message), everyElement(isNotNull));
    });

    test('정해진 시간 안에 답이 없으면 점검 실패', () async {
      final checker = SystemEnvChecker(
        resolve: _direct,
        timeout: const Duration(milliseconds: 50),
        run: (_, _) => Completer<ProcessResult>().future,
      );
      final [r] = await checker.check([const CliRequirement('node')]);
      expect(r.status, EnvStatus.checkFailed);
      expect(r.message, contains('답하지 않'));
    });

    test('버전을 읽지 못하면: 버전 조건이 있으면 점검 실패, 없으면 설치만 확인해 통과', () async {
      final checker = SystemEnvChecker(resolve: _direct, run: (_, _) async => _ok('뭔가 다른 출력'));
      final [withRange, withoutRange] = await checker.check(const [CliRequirement('tool', version: '>=1'), CliRequirement('tool')]);
      expect(withRange.status, EnvStatus.checkFailed);
      expect(withoutRange.status, EnvStatus.passed);
    });

    test('명령이 실패하고 버전도 못 읽으면 버전 조건이 없어도 점검 실패', () async {
      // macOS 의 /usr/bin/java 는 Java 가 없으면 이렇게 답하고 1 로 끝난다.
      final checker = SystemEnvChecker(
        resolve: _direct,
        run: (_, _) async => ProcessResult(0, 1, '', 'The operation couldn’t be completed. Unable to locate a Java Runtime.\n'),
      );
      final [r] = await checker.check([const CliRequirement('java')]);
      expect(r.status, EnvStatus.checkFailed);
      expect(r.message, contains('Unable to locate a Java Runtime'));
    });

    test('명령이 실패해도 버전을 읽었으면 그 버전으로 판단한다', () async {
      final checker = SystemEnvChecker(resolve: _direct, run: (_, _) async => ProcessResult(0, 2, 'tool 1.4.0\n', ''));
      final [r] = await checker.check([const CliRequirement('tool', version: '>=1')]);
      expect(r.status, EnvStatus.passed);
      expect(r.foundVersion, '1.4.0');
    });

    test('Windows 에서 PATH 에 없으면 실행하지 않고 미설치', () async {
      var ran = false;
      final checker = SystemEnvChecker(resolve: (_, _) => null, run: (_, _) async => (ran = true, _ok('1.0.0')).$2);
      final [r] = await checker.check([const CliRequirement('node')]);
      expect(ran, isFalse);
      expect(r.status, EnvStatus.notInstalled);
    });

    test('Docker: CLI 가 없으면 미설치, 데몬에 못 붙으면 데몬 미실행, 붙으면 서버 버전', () async {
      Future<ProcessResult> missing(String _, List<String> _) => throw const ProcessException('docker', [], '없음', 2);
      Future<ProcessResult> off(String _, List<String> _) async => ProcessResult(0, 1, '', 'Cannot connect to the Docker daemon');
      Future<ProcessResult> on(String _, List<String> _) async => _ok('27.1.1\n');

      Future<EnvCheckResult> docker(RunProcess run) async =>
          (await SystemEnvChecker(resolve: _direct, run: run).check([const DockerRequirement()])).single;
      expect((await docker(missing)).status, EnvStatus.notInstalled);
      expect((await docker(off)).status, EnvStatus.daemonNotRunning);
      expect((await docker(off)).message, isNotNull);
      final up = await docker(on);
      expect(up.status, EnvStatus.passed);
      expect(up.foundVersion, '27.1.1');
    });
  });

  group('resolveWindowsCli', () {
    const path = r'C:\Program Files\nodejs;C:\Windows\System32';
    const pathExt = '.COM;.EXE;.BAT;.CMD;.VBS;.JS';
    const comSpec = r'C:\Windows\System32\cmd.exe';
    List<String>? resolve(String cli, Set<String> files) =>
        resolveWindowsCli(cli, const ['--version'], path: path, pathExt: pathExt, comSpec: comSpec, exists: files.contains);

    test('.exe 는 찾은 경로로 바로 실행한다', () {
      expect(resolve('node', {r'C:\Program Files\nodejs\node.exe'}), [r'C:\Program Files\nodejs\node.exe', '--version']);
    });

    test('.cmd 는 cmd 를 거쳐 실행하고 AutoRun 을 끈다', () {
      expect(resolve('npm', {r'C:\Program Files\nodejs\npm.cmd'}),
          [comSpec, '/d', '/c', r'C:\Program Files\nodejs\npm.cmd', '--version']);
    });

    test('PATHEXT 순서대로 찾고, .vbs·.js 처럼 실행 대상이 아닌 건 건너뛴다', () {
      expect(resolve('tool', {r'C:\Windows\System32\tool.js', r'C:\Windows\System32\tool.cmd'})?[3], r'C:\Windows\System32\tool.cmd');
      expect(resolve('tool', {r'C:\Windows\System32\tool.js'}), isNull);
    });

    test('cmd 가 해석할 글자가 든 경로의 .cmd 는 실행하지 않고 이유를 알린다', () {
      expect(
          () => resolveWindowsCli('npm', const ['--version'],
              path: r'C:\Program Files (x86)\nodejs', pathExt: pathExt, comSpec: comSpec, exists: (f) => f.endsWith('.cmd')),
          throwsA(isA<FormatException>()));
    });

    test('경로 속 .cmd 를 거절하면 점검 실패로 알린다', () async {
      final checker = SystemEnvChecker(resolve: (_, _) => throw const FormatException('특수문자'), run: (_, _) async => _ok('1.0'));
      final [r] = await checker.check([const CliRequirement('npm')]);
      expect(r.status, EnvStatus.checkFailed);
      expect(r.message, isNotNull);
    });
  });
}

List<String> _direct(String cli, List<String> args) => [cli, ...args];

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');

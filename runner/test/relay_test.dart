import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_runner_relay/log_file.dart';
import 'package:popoling_runner_relay/relay_request.dart';

import 'support/relay_binary.dart';

void main() {
  late String relay;
  late Directory tmp;
  setUpAll(() async => relay = await relayBinary());
  setUp(() => tmp = Directory.systemTemp.createTempSync('relay_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File logFile() => File('${tmp.path}/p/s.log');

  /// 중계를 띄우고 요청을 넘긴다. 끝나면 (stdout 줄, stderr 줄, 종료 코드).
  Future<(List<String>, List<String>, int)> runRelay(List<String> command, {List<String> secrets = const []}) async {
    final p = await Process.start(relay, [], workingDirectory: tmp.path);
    p.stdin.writeln(RelayRequest(command: command, logFile: logFile().path, secrets: secrets).encode());
    await p.stdin.close();
    final out = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
    final err = p.stderr.transform(utf8.decoder).transform(const LineSplitter()).toList();
    return (await out, await err, await p.exitCode);
  }

  test('요청은 JSON 한 줄로 오가고, 비밀값은 인자가 아니라 요청에 담긴다', () {
    final r = RelayRequest(command: ['a', 'b c'], logFile: '/x.log', secrets: ['pw'], jobName: 'job-1', maxBytes: 10, keep: 2);
    final line = r.encode();
    expect(line, isNot(contains('\n')));
    final back = RelayRequest.decode(line);
    expect([back.command, back.logFile, back.secrets, back.jobName, back.maxBytes, back.keep],
        [['a', 'b c'], '/x.log', ['pw'], 'job-1', 10, 2]);
    expect(RelayRequest.decode(RelayRequest(command: ['a'], logFile: 'l', secrets: []).encode()).jobName, isNull);
  });

  group('POSIX', () {
    test('비밀값을 가려 파일에 쓰고 앱에도 가린 줄을 넘긴다', () async {
      final (out, err, code) =
          await runRelay(['sh', '-c', 'echo pw=hunter2; echo oops >&2; exit 3'], secrets: ['hunter2']);
      expect(code, 3);
      expect(out, ['pw=****']);
      expect(err, ['oops']);
      final lines = logFile().readAsLinesSync();
      expect(lines.first, startsWith('--- 시작 '));
      expect(lines.any((l) => l.endsWith(' out | pw=****')), isTrue);
      expect(lines.any((l) => l.endsWith(' err | oops')), isTrue);
      expect(exitCodeOf(lines.last), 3);
      expect(logFile().readAsStringSync(), isNot(contains('hunter2')));
    });

    test('없는 명령은 127 과 이유를 남긴다', () async {
      final (_, err, code) = await runRelay(['no-such-command-xyz']);
      expect(code, 127);
      expect(err, ['명령을 찾을 수 없어요: no-such-command-xyz']);
      expect(exitCodeOf(logFile().readAsLinesSync().last), 127);
    });

    test('신호로 끝난 서비스는 128+신호 번호로 끝난다', () async {
      final (_, _, code) = await runRelay(['sh', '-c', r'kill -TERM $$']);
      expect(code, 128 + 15);
    });

    Future<Process> startRelay(List<String> command, {String? pipeTo}) async {
      final req = File('${tmp.path}/req.json')
        ..writeAsStringSync(RelayRequest(command: command, logFile: logFile().path, secrets: []).encode());
      // pipeTo 가 있으면 중계 stdout 을 그 명령으로 넘긴다(앱 쪽 파이프 흉내).
      // 끝의 '; true' 는 Linux 의 sh(dash)가 중계로 자신을 바꿔치기하지 않고 자식으로 띄우게 한다(relayPid 가 부모로 찾는다).
      final p = await Process.start('sh', ['-c', '"$relay" < "${req.path}"${pipeTo == null ? '' : ' | $pipeTo'}; true']);
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      return p;
    }

    /// [shell] 이 띄운 중계의 PID. 다른 테스트 파일이 띄운 중계와 섞이지 않게 부모로 찾는다.
    Future<int?> relayPid(Process shell) async {
      for (var i = 0; i < 50; i++) {
        // 이름(comm)이 아니라 명령줄로 찾는다. Linux 에서 Dart 실행 파일은 comm 을 'dart:popoling-re' 로 바꾼다.
        final r = await Process.run('pgrep', ['-P', '${shell.pid}', '-f', 'popoling-relay']);
        final pids = (r.stdout as String).trim().split('\n').where((l) => l.isNotEmpty).map(int.parse).toList();
        if (pids.isNotEmpty) return pids.last;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    }

    Future<int?> pgidOf(int pid) async =>
        int.tryParse(((await Process.run('ps', ['-o', 'pgid=', '-p', '$pid'])).stdout as String).trim());

    test('새 프로세스 그룹의 리더가 되고 서비스도 그 그룹에 든다', () async {
      final p = await startRelay(['sh', '-c', 'sleep 5']);
      final pid = (await relayPid(p))!;
      addTearDown(() => Process.run('kill', ['-KILL', '--', '-$pid']));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await pgidOf(pid), pid);
      final children = ((await Process.run('pgrep', ['-g', '$pid'])).stdout as String).trim().split('\n');
      expect(children.length, greaterThanOrEqualTo(2), reason: '중계 + 서비스');
    });

    test('앱 쪽 파이프가 끊겨도 중계와 서비스는 계속 돈다', () async {
      final p = await startRelay(['sh', '-c', 'while true; do echo tick; sleep 0.1; done'], pipeTo: 'head -c 1 > /dev/null');
      final pid = (await relayPid(p))!;
      addTearDown(() => Process.run('kill', ['-KILL', '--', '-$pid']));
      await Future<void>.delayed(const Duration(seconds: 1)); // head 가 1바이트 읽고 끝나 파이프가 끊긴다
      final before = logFile().readAsLinesSync().length;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect((await Process.run('kill', ['-0', '$pid'])).exitCode, 0, reason: '중계가 살아 있다');
      expect(logFile().readAsLinesSync().length, greaterThan(before), reason: '로그가 계속 쌓인다');
    });

    test('TERM 을 받아도 서비스의 마지막 출력까지 적고 끝난다', () async {
      final p = await startRelay(['sh', '-c', 'trap "echo bye; exit 0" TERM; while true; do sleep 0.1; done']);
      final pid = (await relayPid(p))!;
      addTearDown(() => Process.run('kill', ['-KILL', '--', '-$pid']));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await Process.run('kill', ['-TERM', '--', '-$pid']);
      await p.exitCode.timeout(const Duration(seconds: 5));
      final lines = logFile().readAsLinesSync();
      expect(lines.any((l) => l.endsWith(' out | bye')), isTrue);
      expect(exitCodeOf(lines.last), 0);
    });
  }, skip: Platform.isWindows ? 'POSIX 전용' : false);
}

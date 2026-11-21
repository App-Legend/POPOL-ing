@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_runner/src/process/posix_process_launcher.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';

import 'support/relay_binary.dart';

/// [pgid] 그룹에 남은 프로세스 수.
Future<int> groupSize(int pgid) async {
  final r = await Process.run('ps', ['-A', '-o', 'pgid=']);
  return (r.stdout as String).split('\n').where((l) => l.trim() == '$pgid').length;
}

void main() {
  late PosixProcessLauncher launcher;
  late Directory tmp;
  final cwd = Directory.systemTemp.path;
  setUpAll(() async => launcher = PosixProcessLauncher(relay: await relayBinary()));
  setUp(() => tmp = Directory.systemTemp.createTempSync('posix_launcher_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LogTarget log() => LogTarget(File('${tmp.path}/s.log'));

  Future<RunningProcess> launch(List<String> command, {Map<String, String> env = const {}}) async {
    final p = await launcher.start(command, workingDirectory: cwd, environment: env, log: log());
    addTearDown(() => p.stop(Duration.zero));
    return p;
  }

  Future<RunningProcess> start(String script, {Map<String, String> env = const {}}) =>
      launch(['sh', '-c', script], env: env);

  test('stdout·stderr 를 줄 단위로 나눠 보내고 종료 코드를 알려준다', () async {
    final p = await start('echo hello; echo oops >&2; exit 3');
    final lines = await p.output.toList();
    expect(await p.exitCode, 3);
    expect(lines.where((l) => !l.isError).map((l) => l.text), ['hello']);
    expect(lines.where((l) => l.isError).map((l) => l.text), ['oops']);
    expect(log().file.readAsStringSync(), contains(' out | hello'), reason: '중계가 로그 파일에도 쓴다');
  });

  test('새 프로세스 그룹의 리더로 시작한다 (pgid == pid)', () async {
    final p = await start('sleep 30');
    await Future<void>.delayed(const Duration(milliseconds: 300)); // 중계가 그룹을 만들 때까지
    final r = await Process.run('ps', ['-o', 'pgid=', '-p', '${p.pid}']);
    expect(int.parse((r.stdout as String).trim()), p.pid);
    expect(p.pgid, p.pid);
  });

  test('작업 폴더와 환경변수를 넘긴다', () async {
    final p = await start(r'echo "$PPOLING_TEST"; pwd -P', env: {'PPOLING_TEST': 'ok'});
    final lines = (await p.output.toList()).map((l) => l.text).toList();
    expect(lines.first, 'ok');
    expect(lines.last, Directory(cwd).resolveSymbolicLinksSync());
  });

  test('멈추면 자식·손자까지 그룹 전체가 사라진다', () async {
    final p = await start('sleep 30 & sh -c "sleep 30" & wait');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await groupSize(p.pgid), greaterThanOrEqualTo(3));

    final result = await p.stop(const Duration(seconds: 5));
    expect(result.forced, isFalse);
    expect(await groupSize(p.pgid), 0);
  });

  test('종료 신호를 무시하면 제한 시간 뒤 강제 종료하고 알려준다', () async {
    final p = await start('trap "" TERM; sleep 30 & wait');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final result = await p.stop(const Duration(milliseconds: 500));
    expect(result.forced, isTrue);
    expect(await groupSize(p.pgid), 0);
  });

  test('없는 명령은 예외 없이 종료 코드 127 과 이유를 남긴다', () async {
    final p = await launch(['no-such-command-ppoling']);
    final lines = await p.output.toList();
    expect(await p.exitCode, 127);
    expect(lines.where((l) => l.isError), isNotEmpty);
  });

  test('이미 끝난 프로세스를 멈춰도 오류 없이 강제 종료가 아니다', () async {
    final p = await start('exit 0');
    await p.exitCode;
    expect((await p.stop(const Duration(seconds: 1))).forced, isFalse);
  });

  test('띄우자마자 멈춰도 명령이 남지 않는다', () async {
    final p = await launch(['sleep', '36']);
    await p.stop(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final r = await Process.run('ps', ['-A', '-o', 'command=']);
    expect((r.stdout as String).split('\n').where((l) => l.trim() == 'sleep 36'), isEmpty);
  });

  test("'-' 로 시작하는 명령도 옵션이 아니라 명령으로 넘긴다", () async {
    final p = await launch(['-x-ppoling']);
    final lines = await p.output.toList();
    expect(await p.exitCode, 127);
    expect(lines.where((l) => l.isError).map((l) => l.text), contains(contains('-x-ppoling')));
  });

  test('입력을 기다리는 명령은 기다리지 않고 빈 입력을 받는다', () async {
    final p = await start(r'read x; echo "got:$x"');
    final lines = await p.output.toList().timeout(const Duration(seconds: 5));
    expect(lines.map((l) => l.text), ['got:']);
  });

  test('명령이 비어 있으면 ArgumentError', () {
    expect(() => launcher.start([], workingDirectory: cwd, log: log()), throwsArgumentError);
  });

  test('중계가 없으면 시작이 실패로 끝나고 이유를 알린다', () async {
    final p = await PosixProcessLauncher(relay: '/nonexistent/ppoling-relay')
        .start(['sleep', '1'], workingDirectory: cwd, log: log());
    final lines = await p.output.toList();
    expect(await p.exitCode, 127);
    expect(lines.map((l) => l.text), ['중계 프로그램을 찾을 수 없어요.']);
  });

  group('다시 붙기', () {
    test('띄운 기록으로 다시 붙으면 멈출 수 있다', () async {
      final p = await start('sleep 30 & wait');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final r = await launcher.attach(pid: p.pid, startedAt: p.startedAt);
      final again = (r as Attached).process;
      expect(again.pid, p.pid);
      expect(await again.output.toList(), isEmpty, reason: '앱을 다시 켜기 전 출력은 로그 파일에만 있다');
      expect(await again.contains(p.pid), isTrue);
      expect((await again.stop(const Duration(seconds: 5))).forced, isFalse);
      expect(await groupSize(p.pid), 0);
      expect(await again.exitCode.timeout(const Duration(seconds: 3)), -1, reason: '종료 코드는 로그에서 읽는다');
    });

    test('PID 가 다른 프로그램에 재사용됐으면 Unverified', () async {
      final other = await Process.start('sleep', ['30']);
      addTearDown(other.kill);
      expect(await launcher.attach(pid: other.pid, startedAt: DateTime.now()), isA<Unverified>());
      expect((await Process.run('kill', ['-0', '${other.pid}'])).exitCode, 0, reason: '건드리지 않는다');
    });

    test('시작 시각이 다르면 Unverified', () async {
      final p = await start('sleep 30');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final r = await launcher.attach(pid: p.pid, startedAt: p.startedAt.subtract(const Duration(minutes: 1)));
      expect(r, isA<Unverified>());
    });

    test('끝난 기록은 Gone', () async {
      final p = await start('exit 0');
      await p.exitCode;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await launcher.attach(pid: p.pid, startedAt: p.startedAt), isA<Gone>());
    });
  });
}

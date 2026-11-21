@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_relay/relay_request.dart';
import 'package:ppoling_runner/src/process/process_launcher.dart';
import 'package:ppoling_runner/src/process/windows_job.dart';
import 'package:ppoling_runner/src/process/windows_process_launcher.dart';

import 'support/relay_binary.dart';

void main() {
  late WindowsProcessLauncher launcher;
  late Directory dir;

  setUpAll(() async => launcher = WindowsProcessLauncher(relay: await relayBinary()));
  setUp(() => dir = Directory.systemTemp.createTempSync('ppoling_win_'));
  tearDown(() => dir.deleteSync(recursive: true));

  LogTarget log() => LogTarget(File('${dir.path}\\s.log'));

  Future<RunningProcess> start(List<String> command, {Map<String, String> env = const {}}) async {
    final p = await launcher.start(command, workingDirectory: dir.path, environment: env, log: log());
    addTearDown(() => p.stop(Duration.zero));
    return p;
  }

  test('ProcessLauncher.forPlatform 은 Windows 실행기를 고른다', () {
    expect(ProcessLauncher.forPlatform(relay: 'ppoling-relay.exe'), isA<WindowsProcessLauncher>());
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
    // cmd 가 (Job 에 들어갈 때까지 1초쯤 기다린 뒤) ping 을 따로 띄우고 바로 끝난다.
    // 손자 ping 은 1초마다 ping.txt 에 한 줄씩 쓰니, 파일이 자라는지로 살아 있는지 Job 과 따로 확인한다.
    final out = File('${dir.path}\\ping.txt');
    final p = await start(['cmd', '/d', '/c', 'ping -n 2 127.0.0.1 > nul & start /b ping -n 60 127.0.0.1 > ping.txt']);
    // 손자가 stderr 를 물려받아 중계는 손자가 끝날 때까지 남는다. cmd 가 끝날 시간만 기다린다.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(await p.groupAlive, isTrue);
    final before = out.lengthSync();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(out.lengthSync(), greaterThan(before), reason: '손자 ping 이 아직 돌고 있어야 한다');

    final r = await p.stop(const Duration(seconds: 1));
    expect(r.forced, isTrue);
    expect(await p.groupAlive, isFalse);
    final after = out.lengthSync();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(out.lengthSync(), after, reason: '멈춘 뒤에는 손자 ping 도 더 쓰지 않아야 한다');
  });

  test('Job 에 든 프로세스만 내 것이다', () async {
    final p = await start(['ping', '-n', '30', '127.0.0.1']);
    final foreign = await Process.start('ping', ['-n', '30', '127.0.0.1']);
    addTearDown(foreign.kill);
    expect(await p.contains(p.pid), isTrue);
    expect(await p.contains(foreign.pid), isFalse);
    await p.stop(Duration.zero);
    expect(await p.contains(p.pid), isFalse);
  });

  test('이미 끝난 프로세스를 멈추면 아무것도 하지 않는다', () async {
    final p = await start(['cmd', '/d', '/c', 'exit /b 0']);
    await p.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect((await p.stop(Duration.zero)).forced, isFalse);
  });

  test('중계가 로그 파일에도 쓴다', () async {
    final p = await start(['cmd', '/d', '/c', 'echo hello']);
    await p.exitCode;
    expect(log().file.readAsStringSync(), contains(' out | hello'));
  });

  group('다시 붙기', () {
    test('앱이 꺼져 Job 핸들이 닫혀도 중계가 쥐고 있으면 Job 이름이 남는다', () async {
      // 앱이 꺼진 상황: Job 을 만든 쪽 핸들을 닫는다. 중계가 같은 이름으로 연 핸들만 남는다.
      final name = 'ppoling-test-${DateTime.now().microsecondsSinceEpoch}';
      final job = WindowsJob(name: name);
      final relay = await Process.start(await relayBinary(), const [], workingDirectory: dir.path);
      expect(job.assign(relay.pid), isTrue);
      relay.stdin.writeln(RelayRequest(
              command: ['ping', '-n', '60', '127.0.0.1'], logFile: log().file.path, secrets: const [], jobName: name)
          .encode());
      await relay.stdin.close();
      relay.stdout.drain<void>();
      relay.stderr.drain<void>();
      await Future<void>.delayed(const Duration(seconds: 1));
      job.close();

      final reopened = WindowsJob.open(name);
      expect(reopened, isNotNull, reason: '이게 실패하면 설계의 대안(중계 PID + 생성 시각)으로 가야 한다');
      expect(reopened!.contains(relay.pid), isTrue);
      expect(reopened.terminate(), isTrue);
      reopened.close();
      await relay.exitCode.timeout(const Duration(seconds: 5));
    });

    test('앱이 Job 핸들을 닫아도 중계가 살아 있으면 이름으로 다시 열린다', () async {
      final p = await start(['ping', '-n', '60', '127.0.0.1']);
      final name = p.jobName!;
      await Future<void>.delayed(const Duration(seconds: 1)); // 중계가 Job 핸들을 열 때까지
      expect(WindowsJob.open(name), isNotNull);
      final r = await launcher.attach(pid: p.pid, startedAt: p.startedAt, jobName: name);
      final again = (r as Attached).process;
      expect(await again.contains(p.pid), isTrue);
      expect(await again.output.toList(), isEmpty);
      await again.stop(Duration.zero);
      expect(await again.groupAlive, isFalse);
      expect(await again.exitCode.timeout(const Duration(seconds: 5)), -1);
    });

    test('Job 이름이 없거나 다른 프로세스면 Unverified', () async {
      final foreign = await Process.start('ping', ['-n', '30', '127.0.0.1']);
      addTearDown(foreign.kill);
      expect(await launcher.attach(pid: foreign.pid, startedAt: DateTime.now()), isA<Unverified>());
      final p = await start(['ping', '-n', '30', '127.0.0.1']);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await launcher.attach(pid: foreign.pid, startedAt: DateTime.now(), jobName: p.jobName), isA<Unverified>());
      expect(foreign.kill(ProcessSignal.sigterm), isTrue, reason: '건드리지 않았으니 아직 살아 있다');
    });

    test('끝난 기록은 Gone', () async {
      final p = await start(['cmd', '/d', '/c', 'exit /b 0']);
      await p.exitCode;
      await p.stop(Duration.zero);
      expect(await launcher.attach(pid: p.pid, startedAt: p.startedAt, jobName: p.jobName), isA<Gone>());
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/port_owner/macos_port_owner.dart';
import 'package:popoling_checks/src/port_owner/port_owner_lookup.dart';
import 'package:popoling_checks/src/port_owner/windows_port_owner.dart';
import 'package:popoling_checks/src/system_port_probe.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/testing.dart';

void main() {
  late ServerSocket server;
  late int freePort;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) => client.destroy());
    freePort = await _freePort();
  });
  tearDown(() => server.close());

  group('SystemPortProbe (이 컴퓨터)', () {
    portProbeContract(() async => PortProbeFixture(probe: SystemPortProbe(), freePort: freePort, busyPort: server.port));

    test('내가 연 포트의 주인은 이 테스트 프로세스다', () async {
      final usage = await SystemPortProbe().whoUses(server.port) as PortInUse;
      if (!Platform.isWindows && !Platform.isMacOS) return markTestSkipped('PID 찾기는 macOS·Windows 만');
      expect(usage.pid, pid);
      expect(usage.processName, isNotNull);
    });

    test('OS 명령으로 모르면 직접 열어 보고, PID 없이 사용 중이라고 답한다', () async {
      final probe = SystemPortProbe(owners: _Unknown());
      final busy = await probe.whoUses(server.port);
      expect(busy, isA<PortInUse>());
      expect((busy as PortInUse).pid, isNull);
      expect(await probe.whoUses(freePort), isA<PortFree>());
    });
  });

  group('connect', () {
    final probe = SystemPortProbe();

    test('host 를 주면 그 주소로 연결하고 대상에 적는다', () async {
      final result = await probe.connect(server.port, host: '127.0.0.1');
      expect((result.ok, result.target), (true, '127.0.0.1:${server.port}'));
    });

    test('충분히 기다리면 비어 있는 포트는 연결 거부다', () async {
      // Windows 는 거부를 약 2초 뒤에 알려서 기본 대기 시간으로는 응답 없음이 될 수 있다.
      final result = await probe.connect(freePort, timeout: const Duration(seconds: 5));
      expect(result.failureReason, '연결 거부');
    });

    test('없는 주소는 주소를 찾을 수 없음', () async {
      final result = await probe.connect(80, host: 'no-such-host.invalid');
      expect((result.ok, result.failureReason), (false, '주소를 찾을 수 없음'));
    });
  });

  group('Windows 출력 읽기', () {
    const netstat = '''
활성 연결

  프로토콜  로컬 주소              외부 주소              상태            PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1180
  TCP    127.0.0.1:3306         127.0.0.1:52000        ESTABLISHED     9999
  TCP    127.0.0.1:52000        127.0.0.1:3306         ESTABLISHED     8888
  TCP    0.0.0.0:3306           0.0.0.0:0              LISTENING       4321
  TCP    [::]:5173              [::]:0                 LISTENING       777
''';

    test('netstat 에서 LISTEN 줄의 PID 만 찾는다 (상태 이름이 한국어여도)', () {
      expect(listeningPid(netstat, 3306), 4321);
      expect(listeningPid(netstat, 5173), 777);
      expect(listeningPid(netstat, 52000), isNull, reason: '연결된 쪽 포트는 LISTEN 이 아니다');
      expect(listeningPid(netstat.replaceAll('LISTENING', '수신 대기'), 135), 1180);
    });

    test('tasklist 의 첫 칸이 프로그램 이름, 못 찾으면 null', () {
      expect(tasklistName('"node.exe","4321","Console","1","45,000 K"\r\n'), 'node.exe');
      expect(tasklistName('정보: 지정된 조건에 맞는 작업이 없습니다.\r\n'), isNull);
    });

    test('netstat·tasklist 결과로 PortInUse, 없으면 PortFree, 명령이 실패하면 모름', () async {
      final owner = WindowsPortOwner(run: (exe, args) async => switch (exe) {
            'netstat' => ProcessResult(0, 0, args.last == 'TCP' ? netstat : '', ''),
            _ => ProcessResult(0, 0, '"mysqld.exe","4321","Services","0","1 K"', ''),
          });
      final usage = await owner.find(3306) as PortInUse;
      expect((usage.pid, usage.processName), (4321, 'mysqld.exe'));
      expect(await owner.find(8080), isA<PortFree>());

      final broken = WindowsPortOwner(run: (exe, args) async => throw const ProcessException('netstat', []));
      expect(await broken.find(3306), isNull);
    });
  });

  group('macOS 출력 읽기', () {
    test('lsof -F pc 에서 첫 프로세스의 PID·이름', () {
      final usage = lsofOwner('p4321\ncnode\np5555\ncother\n', 5173)!;
      expect((usage.port, usage.pid, usage.processName), (5173, 4321, 'node'));
      expect(lsofOwner('', 5173), isNull);
    });

    test('lsof 가 못 찾으면 PortFree 가 아니라 모름(남의 계정 프로세스는 안 보여서)', () async {
      final owner = MacosPortOwner(run: (exe, args) async => ProcessResult(0, 1, '', ''));
      expect(await owner.find(5173), isNull);
    });
  });
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _Unknown implements PortOwnerLookup {
  @override
  Future<PortUsage?> find(int port) async => null;
}

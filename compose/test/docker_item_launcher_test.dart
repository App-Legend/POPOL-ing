@Timeout(Duration(minutes: 5)) // 실제 Docker 테스트는 처음에 이미지를 받는다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_compose/src/docker_cli.dart';
import 'package:popoling_compose/src/docker_item_launcher.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/testing.dart';

void main() {
  group('DockerItemLauncher (실제 Docker)', () {
    late bool dockerRunning;
    setUpAll(() async => dockerRunning = await DockerCli().daemonRunning());

    itemLauncherContract(() async {
      final folder = await Directory.systemTemp.createTemp('popoling-compose-test');
      addTearDown(() => folder.delete(recursive: true));
      final port = await _freePort();
      File('${folder.path}/docker-compose.yml').writeAsStringSync('''
services:
  web:
    image: nginx:alpine
    ports: ["$port:80"]
''');
      const compose = ComposeService(id: 'web', file: './docker-compose.yml', services: ['web']);
      const process = ProcessService(id: 'api', command: ['echo', 'hi']);
      const remoteUp = RemoteService(id: 'storage', ready: HttpReady(url: 'https://storage.example.com/health'));
      const remoteDown = RemoteService(id: 'old-api', ready: PortReady(port: 3306, host: 'db.example.com'));

      final repo = FakeProjectRepository(existingFolders: [folder.path])
        ..addFolder(folder.path,
            config: const ProjectConfig(services: [compose, process, remoteUp, remoteDown]));
      final project = await repo.addProject(folder.path);

      return ItemLauncherFixture(
        launcher: DockerItemLauncher(
          projects: () => repo,
          http: () => FakeHttpProbe(responses: {'https://storage.example.com/health': 200}),
          ports: () => FakePortProbe(),
        ),
        projectId: project.id,
        compose: compose,
        composePort: port,
        process: process,
        remoteUp: remoteUp,
        remoteDown: remoteDown,
        dockerRunning: dockerRunning,
      );
    });
  });

  group('DockerItemLauncher 가 넘기는 명령', () {
    late _RecordingDocker docker;
    late DockerItemLauncher launcher;
    late FakeProjectRepository repo;
    const db = ComposeService(id: 'db', file: './docker-compose.yml', services: ['mysql']);
    const whole = ComposeService(id: 'all', file: './docker-compose.yml');

    setUp(() async {
      docker = _RecordingDocker();
      repo = FakeProjectRepository(existingFolders: ['/projects/shop'])
        ..addFolder('/projects/shop', config: const ProjectConfig(services: [db, whole]));
      await repo.addProject('/projects/shop');
      launcher = DockerItemLauncher(
        projects: () => repo,
        http: () => FakeHttpProbe(),
        ports: () => FakePortProbe(),
        docker: docker.cli,
      );
    });

    test('Compose 는 항상 -p popoling-<프로젝트ID> 와 프로젝트 폴더 안의 compose 파일로 부른다', () async {
      await launcher.start('shop', db);
      final up = docker.calls.firstWhere((c) => c.contains('up'));
      expect(up.sublist(0, 3), ['compose', '-p', 'popoling-shop']);
      expect(up[4], endsWith('docker-compose.yml'));
      expect(up.sublist(5), ['up', '-d', 'mysql']);
    });

    List<String> composeCall(String sub) => docker.calls.firstWhere((c) => c.first == 'compose' && c[5] == sub);

    test('멈출 때는 이 항목의 서비스만 지우고, 볼륨은 지우지 않는다', () async {
      docker.stdout['ps'] = 'abc123\n'; // 다른 항목의 컨테이너가 아직 남아 있다
      await launcher.stop('shop', db);
      expect(composeCall('rm').sublist(5), ['rm', '--stop', '--force', 'mysql']);
      expect(docker.calls.where((c) => c.contains('down')), isEmpty, reason: '남은 컨테이너가 있으면 down 하지 않는다');
      for (final call in docker.calls) {
        expect(call, isNot(anyOf(contains('-v'), contains('--volumes'))));
      }
    });

    test('프로젝트에 컨테이너가 안 남으면 볼륨 없이 down 해서 네트워크를 정리한다', () async {
      await launcher.stop('shop', db);
      final down = docker.calls.last;
      expect(down.sublist(0, 3), ['compose', '-p', 'popoling-shop']);
      expect(down.sublist(5), ['down']);
    });

    test('services 를 비운 항목은 compose 파일의 서비스 목록을 읽어 그것만 지운다', () async {
      docker.stdout['config'] = 'mysql\nredis\n';
      await launcher.stop('shop', whole);
      expect(composeCall('rm').sublist(5), ['rm', '--stop', '--force', 'mysql', 'redis']);
    });

    test('compose 파일이 프로젝트 폴더 밖이면 거절하고 docker 를 부르지 않는다', () async {
      const escape = ComposeService(id: 'x', file: '../other/docker-compose.yml');
      await expectLater(launcher.start('shop', escape), throwsA(isA<PopolingException>()));
      expect(docker.calls.where((c) => c.contains('up')), isEmpty);
    });

    test('compose 명령이 실패하면 ComposeCommandException, 출력은 남긴다', () async {
      docker.failOn['up'] = 'no such image: mysql:99';
      await expectLater(
        launcher.start('shop', db),
        throwsA(isA<ComposeCommandException>()
            .having((e) => e.exitCode, 'exitCode', 1)
            .having((e) => e.output, 'output', contains('no such image'))),
      );
    });

    test('Docker 가 꺼져 있으면 compose 명령 전에 DockerNotRunningException', () async {
      docker.daemon = false;
      await expectLater(launcher.start('shop', db), throwsA(isA<DockerNotRunningException>()));
      expect(docker.calls.where((c) => c.first == 'compose'), isEmpty);
    });

    test('포트 주인은 popoling- 프로젝트의 컨테이너만 보고, 서비스 이름으로 항목을 찾는다', () async {
      docker.stdout['ps'] = 'shop\tmysql\t0.0.0.0:3306->3306/tcp\n'
          'popoling-shop\tmysql\t0.0.0.0:3306->3306/tcp, [::]:3306->3306/tcp\n'
          'popoling-shop\tredis\t0.0.0.0:6379->6379/tcp\n';
      expect(await launcher.composeOwnerOf(3306), const ItemRef(projectId: 'shop', serviceId: 'db'));
      expect(await launcher.composeOwnerOf(6379), const ItemRef(projectId: 'shop', serviceId: 'all'));
      expect(await launcher.composeOwnerOf(8080), isNull);
    });
  });

  group('출력 읽기', () {
    const row = '{"Service":"mysql","Name":"popoling-shop-mysql-1","State":"running","Health":"healthy",'
        '"ExitCode":0,"Publishers":[{"PublishedPort":3306},{"PublishedPort":3306},{"PublishedPort":0}]}';

    test('ps json 은 한 줄에 하나 형식과 배열 형식을 모두 읽는다', () {
      for (final out in ['$row\n$row\n', '[$row]']) {
        final c = parseComposePs(out).first;
        expect((c.service, c.state, c.health, c.exitCode), ('mysql', ContainerState.running, ContainerHealth.healthy, null));
        expect(c.ports, [3306]);
      }
      expect(parseComposePs(''), isEmpty);
    });

    test('.env 값은 4글자 이상만 가린다', () {
      expect(maskSecrets('pw=hunter2 user=ab', ['hunter2', 'ab']), 'pw=**** user=ab');
    });
  });
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// 실제로 실행하지 않고 docker 인자를 기록한다. [stdout]·[failOn] 은 첫 compose 하위 명령(또는 `ps`)으로 찾는다.
class _RecordingDocker {
  final calls = <List<String>>[];
  final stdout = <String, String>{};
  final failOn = <String, String>{};
  var daemon = true;

  late final cli = DockerCli(run: (exe, args, {workingDirectory}) async {
    if (args.first == 'version') return ProcessResult(0, daemon ? 0 : 1, '', '');
    calls.add(args);
    final sub = args.first == 'compose' ? args[5] : args.first;
    final fail = failOn[sub];
    return ProcessResult(0, fail == null ? 0 : 1, stdout[sub] ?? '', fail ?? '');
  });
}

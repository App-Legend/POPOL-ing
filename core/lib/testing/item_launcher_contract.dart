import 'package:flutter_test/flutter_test.dart';

import '../contracts/item_launcher.dart';
import '../models/errors.dart';
import '../models/item_ref.dart';
import '../models/launch.dart';
import '../models/service_config.dart';

/// [itemLauncherContract] 가 테스트마다 받는 준비물.
class ItemLauncherFixture {
  ItemLauncherFixture({
    required this.launcher,
    required this.projectId,
    required this.compose,
    required this.composePort,
    required this.process,
    required this.remoteUp,
    required this.remoteDown,
    required this.dockerRunning,
    this.unknownProjectId = 'no-such-project',
  });

  /// 아무 항목도 띄우지 않은 ItemLauncher.
  final ItemLauncher launcher;

  /// 등록된 프로젝트. 아래 항목들이 이 프로젝트의 popoling.yaml 에 있어야 한다.
  final String projectId;

  /// Compose 항목. 띄우면 [composePort] 를 열고, 시작할 때 로그를 한 줄 이상 남겨야 한다.
  /// 진짜 구현 테스트에서는 작은 이미지(예: `nginx:alpine`)를 쓰는 샘플 compose 파일을 둔다.
  final ComposeService compose;
  final int composePort;

  /// 프로세스 항목. ItemLauncher 가 받지 않아야 한다.
  final ProcessService process;

  /// 연결되는 원격 항목과 연결되지 않는 원격 항목.
  final RemoteService remoteUp;
  final RemoteService remoteDown;

  /// 이 환경에서 Docker 데몬이 켜져 있는가. 꺼져 있으면 Compose 는 '꺼짐' 약속만 확인한다.
  final bool dockerRunning;

  /// 등록되지 않은 프로젝트 ID.
  final String unknownProjectId;
}

/// [ItemLauncher] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
/// Compose 를 띄운 테스트는 끝날 때 스스로 멈춘다.
void itemLauncherContract(Future<ItemLauncherFixture> Function() setUp) {
  test('프로세스 항목은 받지 않는다 (ArgumentError)', () async {
    final f = await setUp();
    await expectLater(f.launcher.start(f.projectId, f.process), throwsArgumentError);
    await expectLater(f.launcher.stop(f.projectId, f.process), throwsArgumentError);
    await expectLater(f.launcher.status(f.projectId, f.process), throwsArgumentError);
  });

  test('없는 프로젝트면 ProjectNotFoundException', () async {
    final f = await setUp();
    await expectLater(f.launcher.start(f.unknownProjectId, f.remoteUp), throwsA(isA<ProjectNotFoundException>()));
    await expectLater(f.launcher.status(f.unknownProjectId, f.compose), throwsA(isA<ProjectNotFoundException>()));
  });

  group('원격 항목', () {
    test('연결되면 연결됨, 안 되면 예외 없이 연결 안 됨과 이유', () async {
      final f = await setUp();
      final up = await f.launcher.start(f.projectId, f.remoteUp);
      final down = await f.launcher.start(f.projectId, f.remoteDown);

      expect(up, isA<RemoteStatus>());
      expect((up as RemoteStatus).connected, isTrue);
      expect((down as RemoteStatus).connected, isFalse);
      expect(down.probe.failureReason, isNotNull);
    });

    test('status 도 같은 확인을 하고, stop 은 아무것도 하지 않는다', () async {
      final f = await setUp();
      await f.launcher.stop(f.projectId, f.remoteUp);
      final status = await f.launcher.status(f.projectId, f.remoteUp);
      expect((status as RemoteStatus).connected, isTrue);
    });
  });

  group('Compose 항목', () {
    test('Docker 가 꺼져 있으면 DockerNotRunningException, 포트 주인은 null', () async {
      final f = await setUp();
      if (f.dockerRunning) return markTestSkipped('Docker 가 켜져 있는 환경');

      await expectLater(f.launcher.start(f.projectId, f.compose), throwsA(isA<DockerNotRunningException>()));
      await expectLater(f.launcher.status(f.projectId, f.compose), throwsA(isA<DockerNotRunningException>()));
      expect(await f.launcher.composeOwnerOf(f.composePort), isNull);
    });

    test('띄우기 전에는 컨테이너가 없고, 포트 주인도 없다', () async {
      final f = await setUp();
      if (!f.dockerRunning) return markTestSkipped('Docker 가 꺼져 있는 환경');

      final status = await f.launcher.status(f.projectId, f.compose);
      expect((status as ComposeStatus).containers, isEmpty);
      expect(status.running, isFalse);
      expect(await f.launcher.composeOwnerOf(f.composePort), isNull);
    });

    test('시작하면 실행 중이고, 연 포트의 주인은 이 항목이다. 멈추면 둘 다 사라진다', () async {
      final f = await setUp();
      if (!f.dockerRunning) return markTestSkipped('Docker 가 꺼져 있는 환경');
      addTearDown(() => f.launcher.stop(f.projectId, f.compose));

      final started = await f.launcher.start(f.projectId, f.compose) as ComposeStatus;
      expect(started.running, isTrue);
      if (f.compose.services.isNotEmpty) {
        expect(started.containers.map((c) => c.service).toSet(), f.compose.services.toSet());
      }
      expect(await f.launcher.composeOwnerOf(f.composePort), ItemRef(projectId: f.projectId, serviceId: f.compose.id));

      await f.launcher.stop(f.projectId, f.compose);
      expect(((await f.launcher.status(f.projectId, f.compose)) as ComposeStatus).containers, isEmpty);
      expect(await f.launcher.composeOwnerOf(f.composePort), isNull);
    });

    test('이미 멈춘 항목을 다시 멈춰도 괜찮다', () async {
      final f = await setUp();
      if (!f.dockerRunning) return markTestSkipped('Docker 가 꺼져 있는 환경');

      await f.launcher.stop(f.projectId, f.compose);
      await f.launcher.stop(f.projectId, f.compose);
    });

    test('로그는 띄운 컨테이너의 줄을 보낸다', () async {
      final f = await setUp();
      if (!f.dockerRunning) return markTestSkipped('Docker 가 꺼져 있는 환경');
      addTearDown(() => f.launcher.stop(f.projectId, f.compose));

      await f.launcher.start(f.projectId, f.compose);
      final first = await f.launcher.logs(f.projectId, f.compose, tail: 10).first.timeout(const Duration(seconds: 30));
      expect(first, isNotEmpty);
    });
  });
}

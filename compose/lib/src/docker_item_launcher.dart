import 'dart:io';

import 'package:popoling_core/contracts.dart';

import 'docker_cli.dart';

/// [ItemLauncher] 의 진짜 구현. Compose 는 `docker compose` CLI 로, 원격은 [HttpProbe]·[PortProbe] 로 다룬다.
///
/// 다른 계약은 함수로 받는다. 앱에서는 `register()` 가 끝난 뒤에 꺼내야 가짜가 진짜로 바뀌어 있기 때문이다.
class DockerItemLauncher implements ItemLauncher {
  DockerItemLauncher({
    required ProjectRepository Function() projects,
    required HttpProbe Function() http,
    required PortProbe Function() ports,
    DockerCli? docker,
  })  : _projects = projects, // ignore: prefer_initializing_formals
        _http = http, // ignore: prefer_initializing_formals
        _ports = ports, // ignore: prefer_initializing_formals
        _docker = docker ?? DockerCli();

  // 이름 붙은 인자는 `_` 로 시작할 수 없어 위에서 옮겨 담는다.
  final ProjectRepository Function() _projects;
  final HttpProbe Function() _http;
  final PortProbe Function() _ports;
  final DockerCli _docker;

  /// Compose 프로젝트 이름의 앞부분. 사용자가 직접 띄운 compose 와 섞이지 않게 한다(CLAUDE.md).
  static const projectPrefix = 'popoling-';

  /// 오류 안내에 붙일 명령 출력 줄 수.
  static const _outputLines = 20;

  @override
  Future<LaunchStatus> start(String projectId, ServiceConfig service) async {
    _rejectProcess(service);
    final project = await _projects().getProject(projectId);
    switch (service) {
      case ProcessService():
        throw StateError('unreachable');
      case RemoteService():
        return _checkRemote(service);
      case ComposeService():
        final c = await _compose(project, service);
        await c.run(['up', '-d', ...service.services], action: '시작하지');
        return _status(c);
    }
  }

  @override
  Future<void> stop(String projectId, ServiceConfig service) async {
    _rejectProcess(service);
    final project = await _projects().getProject(projectId);
    switch (service) {
      case ProcessService():
        throw StateError('unreachable');
      case RemoteService():
        return; // 원격은 켜고 끄지 않는다(FR-18).
      case ComposeService():
        final c = await _compose(project, service);
        // 이 항목의 서비스만 멈추고 지운다. 볼륨은 지우지 않는다(`-v` 를 쓰지 않음).
        final names = service.services.isNotEmpty ? service.services : await c.fileServices();
        if (names.isEmpty) return;
        await c.run(['rm', '--stop', '--force', ...names], action: '멈추지');
        // 이 프로젝트에 컨테이너가 하나도 안 남았으면 compose 가 만든 네트워크를 정리한다. 볼륨은 남긴다(`-v` 없음).
        if (await c.projectEmpty()) await c.run(['down'], action: '정리하지');
    }
  }

  @override
  Future<LaunchStatus> status(String projectId, ServiceConfig service) async {
    _rejectProcess(service);
    final project = await _projects().getProject(projectId);
    switch (service) {
      case ProcessService():
        throw StateError('unreachable');
      case RemoteService():
        return _checkRemote(service);
      case ComposeService():
        return _status(await _compose(project, service));
    }
  }

  @override
  Stream<String> logs(String projectId, ComposeService service, {int tail = 200}) async* {
    final project = await _projects().getProject(projectId);
    final c = await _compose(project, service);
    final process = await _docker.start(
      [...c.base, 'logs', '--follow', '--no-color', '--tail', '$tail', ...service.services],
      workingDirectory: project.folderPath,
    );
    final secrets = c.secrets;
    try {
      await for (final line in processLines(process)) {
        yield maskSecrets(line, secrets);
      }
    } finally {
      process.kill(); // 이 함수가 띄운 `docker compose logs` 프로세스만 끝낸다.
    }
  }

  @override
  Future<ItemRef?> composeOwnerOf(int port) async {
    try {
      final r = await _docker.run([
        'ps',
        '--filter', 'label=com.docker.compose.project',
        '--format', '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}\t{{.Ports}}',
      ]);
      if (r.exitCode != 0) return null;
      for (final line in (r.stdout as String).split('\n')) {
        final cols = line.trim().split('\t');
        if (cols.length < 3 || !cols[0].startsWith(projectPrefix)) continue;
        if (!parsePublishedPorts(cols[2]).contains(port)) continue;
        return await _itemFor(cols[0].substring(projectPrefix.length), cols[1]);
      }
      return null;
    } on Exception {
      return null; // RuntimeQuery 처럼 모르면 null(약속).
    }
  }

  /// 컨테이너의 compose 서비스 이름으로 popoling.yaml 의 Compose 항목을 찾는다.
  Future<ItemRef?> _itemFor(String projectId, String composeService) async {
    final config = (await _projects().getProject(projectId)).config;
    final items = config?.services.whereType<ComposeService>() ?? const <ComposeService>[];
    final item = items.where((s) => s.services.contains(composeService)).firstOrNull ??
        items.where((s) => s.services.isEmpty).firstOrNull;
    return item == null ? null : ItemRef(projectId: projectId, serviceId: item.id);
  }

  Future<RemoteStatus> _checkRemote(RemoteService service) async => RemoteStatus(switch (service.ready) {
        HttpReady(:final url, :final expectStatus) => await _http().get(url, expectStatus: expectStatus),
        PortReady(:final port, :final host) => await _ports().connect(port, host: host),
        _ => ProbeResult(target: service.id, ok: false, failureReason: '원격 항목은 http 또는 port 준비 조건이 필요해요'),
      });

  Future<ComposeStatus> _status(_Compose c) async {
    final r = await c.run(['ps', '--all', '--format', 'json', ...c.service.services], action: '확인하지');
    return ComposeStatus(parseComposePs(r.stdout as String));
  }

  /// Docker 가 켜져 있는지 확인하고, 이 항목의 compose 명령 앞부분을 만든다.
  Future<_Compose> _compose(Project project, ComposeService service) async {
    if (!await _docker.daemonRunning()) throw DockerNotRunningException();
    return _Compose(_docker, project, service, _composeFile(project, service));
  }

  /// compose 파일의 절대 경로. 프로젝트 폴더 밖을 가리키면 거절한다(CLAUDE.md "작업 폴더는 프로젝트 하위").
  static String _composeFile(Project project, ComposeService service) {
    final folder = Directory(project.folderPath).absolute.uri;
    final file = folder.resolve(service.file.replaceAll(r'\', '/'));
    if (!file.path.startsWith(folder.path)) {
      throw PopolingException('compose 파일이 프로젝트 폴더 밖에 있어요: ${service.file}');
    }
    return file.toFilePath();
  }

  static void _rejectProcess(ServiceConfig service) {
    if (service is ProcessService) {
      throw ArgumentError.value(service.id, 'service', 'process 항목은 ItemLauncher 가 아니라 runner 가 다뤄요');
    }
  }
}

/// 항목 하나에 대한 `docker compose -p popoling-<id> -f <file>` 명령.
class _Compose {
  _Compose(this._docker, this.project, this.service, String file)
      : base = ['compose', '-p', '${DockerItemLauncher.projectPrefix}${project.id}', '-f', file];

  final DockerCli _docker;
  final Project project;
  final ComposeService service;
  final List<String> base;

  /// 출력에서 가릴 `.env` 값. compose 는 프로젝트 폴더의 `.env` 를 읽는다.
  late final List<String> secrets = readEnvValues('${project.folderPath}${Platform.pathSeparator}.env');

  Future<ProcessResult> run(List<String> args, {required String action}) async {
    final r = await _docker.run([...base, ...args], workingDirectory: project.folderPath);
    if (r.exitCode != 0) {
      final lines = '${r.stderr}'.trim().split('\n');
      final tail = lines.length > DockerItemLauncher._outputLines ? lines.length - DockerItemLauncher._outputLines : 0;
      throw ComposeCommandException(
        action: action,
        exitCode: r.exitCode,
        output: maskSecrets(lines.skip(tail).join('\n'), secrets),
      );
    }
    return r;
  }

  /// `popoling-<id>` 프로젝트에 남은 컨테이너가 없는지. 다른 compose 파일로 띄운 항목까지 본다.
  Future<bool> projectEmpty() async {
    final r = await _docker.run(['ps', '--all', '--quiet', '--filter', 'label=com.docker.compose.project=${base[2]}']);
    return r.exitCode == 0 && '${r.stdout}'.trim().isEmpty;
  }

  /// compose 파일에 정의된 서비스 이름. 항목이 `services` 를 비워 파일 전체를 쓸 때 멈출 대상을 알아낸다.
  Future<List<String>> fileServices() async {
    final r = await run(['config', '--services'], action: '읽지');
    return [for (final s in '${r.stdout}'.split('\n')) if (s.trim().isNotEmpty) s.trim()];
  }
}

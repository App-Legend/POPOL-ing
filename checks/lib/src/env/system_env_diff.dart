// 이름 있는 매개변수는 _ 로 시작할 수 없어서 생성자에서 옮겨 담는다.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:popoling_core/contracts.dart';

import '../port_owner/port_owner_lookup.dart';
import 'env_snapshot.dart';
import 'system_env_checker.dart';

/// 실행 환경 기록·비교(FR-16)의 진짜 구현.
///
/// - 전체 실행이 성공하면([RunSucceeded]) 그때 환경을 [EnvSnapshotStore] 에 남긴다([listenTo]).
/// - [sinceLastSuccess] 는 지금 환경을 다시 읽어 남긴 것과 비교한다.
///
/// 읽는 것: `requires` 의 버전(환경 점검과 같은 방법), compose 이미지 태그, 프로젝트 폴더의 Git 커밋.
/// 한계: 이미지는 태그만 본다(`latest` 처럼 태그가 같고 내용만 바뀐 것은 모른다).
class SystemEnvDiff implements EnvDiff {
  SystemEnvDiff({
    required ProjectRepository Function() projects,
    required EnvSnapshotStore store,
    RunProcess run = runProcess,
    ResolveCli resolve = resolveCliForPlatform,
    this.timeout = const Duration(seconds: 10),
    DateTime Function() now = DateTime.now,
  })  : _projects = projects,
        _store = store,
        _run = run,
        _resolve = resolve,
        _now = now,
        _checker = SystemEnvChecker(run: run, resolve: resolve, timeout: timeout);

  /// [AppRegistry.read] 처럼 쓸 때 꺼낸다. 등록 중에는 아직 가짜일 수 있어서.
  final ProjectRepository Function() _projects;
  final EnvSnapshotStore _store;
  final RunProcess _run;
  final ResolveCli _resolve;
  final DateTime Function() _now;
  final EnvChecker _checker;

  /// 명령 하나를 기다리는 시간.
  final Duration timeout;

  static const _composePrefix = 'popoling-';

  @override
  Future<List<EnvChange>?> sinceLastSuccess(String projectId) async {
    final project = await _projects().getProject(projectId);
    final last = await _store.read(projectId);
    if (last == null) return null;
    return compare(last, await snapshot(project));
  }

  /// [projectId] 의 지금 환경을 "마지막 성공 환경"으로 남긴다.
  Future<void> recordSuccess(String projectId) async {
    final project = await _projects().getProject(projectId);
    await _store.write(projectId, await snapshot(project));
  }

  /// [events] 에서 [RunSucceeded] 를 받을 때마다 [recordSuccess] 한다.
  StreamSubscription<RunEvent> listenTo(Stream<RunEvent> events) => events.listen((event) {
        if (event is! RunSucceeded) return;
        final id = event.summary.projectId;
        // 기록 실패가 실행 결과를 바꾸지는 않는다. 다음 성공 때 다시 남긴다.
        recordSuccess(id).catchError((Object e) => debugPrint('성공 환경을 남기지 못했어요($id): $e'));
      });

  /// [project] 의 지금 환경.
  Future<EnvSnapshot> snapshot(Project project) async {
    final config = project.config;
    final composeFiles = {
      for (final s in config?.services ?? const <ServiceConfig>[])
        if (s is ComposeService) s.file,
    };
    final [tools, images, commit] = await Future.wait([
      _tools(config?.requires ?? const []),
      _images(project, composeFiles),
      _commit(project.folderPath),
    ]);
    return EnvSnapshot(takenAt: _now(), values: {...tools, ...images, ...commit});
  }

  /// 마지막 성공([before])과 지금([after]) 둘 다 확인한 이름 중 값이 다른 것. [before] 의 순서대로.
  static List<EnvChange> compare(EnvSnapshot before, EnvSnapshot after) => [
        for (final MapEntry(:key, :value) in before.values.entries)
          if (after.values.containsKey(key) && after.values[key] != value)
            EnvChange(name: key, before: value, after: after.values[key]),
      ];

  Future<Map<String, String?>> _tools(List<Requirement> requires) async => {
        for (final r in await _checker.check(requires))
          if (_toolValue(r) case (final String? value,)) _toolName(r.requirement): value,
      };

  static String _toolName(Requirement r) => switch (r) {
        CliRequirement(:final cli) => cli,
        DockerRequirement() => 'docker',
      };

  /// 비교할 값. 확인하지 못했으면 null(이름째 뺀다), 미설치면 `(null,)`.
  static (String?,)? _toolValue(EnvCheckResult r) => switch (r.status) {
        EnvStatus.notInstalled => (null,),
        EnvStatus.passed || EnvStatus.versionMismatch when r.foundVersion != null => (r.foundVersion,),
        _ => null,
      };

  /// compose 파일마다 `docker compose config --images` 로 이미지를 읽는다. Docker 가 꺼져 있어도 된다.
  Future<Map<String, String?>> _images(Project project, Set<String> files) async {
    final values = <String, String?>{};
    for (final file in files) {
      final path = _insideFolder(project.folderPath, file);
      if (path == null) continue; // 프로젝트 폴더 밖의 파일은 읽지 않는다
      final out = await _output('docker', ['compose', '-p', '$_composePrefix${project.id}', '-f', path, 'config', '--images']);
      for (final line in out?.split('\n') ?? const <String>[]) {
        if (_splitImage(line.trim()) case (final name, final tag)) values['image:$name'] = tag;
      }
    }
    return values;
  }

  Future<Map<String, String?>> _commit(String folder) async {
    final out = await _output('git', ['-C', folder, 'rev-parse', '--short=12', 'HEAD']);
    final commit = out?.trim();
    return commit == null || commit.isEmpty ? const {} : {'commit': commit};
  }

  /// [cli] 를 실행해 성공하면 stdout, 아니면 null.
  Future<String?> _output(String cli, List<String> args) async {
    try {
      final command = _resolve(cli, args);
      // cmd.exe 를 거치는 경로(.cmd·.bat)면 폴더 경로가 셸에 해석될 수 있어 실행하지 않는다.
      if (command == null || command.length != args.length + 1) return null;
      final r = await _run(command.first, command.sublist(1)).timeout(timeout);
      return r.exitCode == 0 ? '${r.stdout}' : null;
    } on Object {
      return null; // 미설치·시간 초과·Git 저장소 아님: 확인 못 한 것으로 친다
    }
  }

  /// [file] 이 [folder] 안에 있으면 그 절대 경로, 밖이면 null.
  static String? _insideFolder(String folder, String file) {
    final base = Uri.directory(folder, windows: _windows);
    final target = base.resolveUri(Uri.file(file, windows: _windows));
    if (!target.path.startsWith(base.path)) return null;
    return target.toFilePath(windows: _windows);
  }

  static bool get _windows => Platform.isWindows;

  /// `postgres:16` → (postgres, 16). 태그가 없으면 `latest`. `@sha256:…` 는 뺀다.
  static (String, String)? _splitImage(String image) {
    if (image.isEmpty) return null;
    final ref = image.split('@').first;
    final colon = ref.lastIndexOf(':');
    if (colon > ref.lastIndexOf('/')) return (ref.substring(0, colon), ref.substring(colon + 1));
    return (ref, 'latest');
  }
}

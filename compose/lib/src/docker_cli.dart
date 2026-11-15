import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/models.dart';

/// `docker` 명령을 셸 없이 인자 배열로 실행한다. 테스트에서는 [run]·[start] 를 바꿔 끼운다.
class DockerCli {
  DockerCli({this.executable = 'docker', RunProcess? run, StartProcess? start})
      : _run = run ?? _defaultRun,
        _start = start ?? _defaultStart;

  /// docker 실행 파일. macOS GUI 앱은 PATH 에 `/usr/local/bin` 이 없을 수 있어 절대 경로를 넘길 수 있다.
  final String executable;
  final RunProcess _run;
  final StartProcess _start;

  /// 명령을 끝까지 실행하고 결과를 돌려준다. docker 가 없으면 [DockerNotRunningException].
  Future<ProcessResult> run(List<String> args, {String? workingDirectory}) async {
    try {
      return await _run(executable, args, workingDirectory: workingDirectory);
    } on ProcessException {
      throw DockerNotRunningException();
    }
  }

  /// 오래 도는 명령(로그 따라가기)을 시작한다. docker 가 없으면 [DockerNotRunningException].
  Future<Process> start(List<String> args, {String? workingDirectory}) async {
    try {
      return await _start(executable, args, workingDirectory: workingDirectory);
    } on ProcessException {
      throw DockerNotRunningException();
    }
  }

  /// Docker 데몬에 연결되는지. CLI 가 없어도 false.
  Future<bool> daemonRunning() async {
    try {
      final r = await _run(executable, ['version', '--format', '{{.Server.Version}}']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<ProcessResult> _defaultRun(String exe, List<String> args, {String? workingDirectory}) =>
      Process.run(exe, args,
          workingDirectory: workingDirectory, runInShell: false, stdoutEncoding: utf8, stderrEncoding: utf8);

  static Future<Process> _defaultStart(String exe, List<String> args, {String? workingDirectory}) =>
      Process.start(exe, args, workingDirectory: workingDirectory, runInShell: false);
}

typedef RunProcess = Future<ProcessResult> Function(String executable, List<String> arguments,
    {String? workingDirectory});
typedef StartProcess = Future<Process> Function(String executable, List<String> arguments,
    {String? workingDirectory});

/// `docker compose ps --format json` 출력을 읽는다. 한 줄에 하나(새 버전)와 배열(옛 버전)을 모두 받는다.
List<ContainerStatus> parseComposePs(String output) {
  final text = output.trim();
  if (text.isEmpty) return const [];
  final List<Object?> rows = text.startsWith('[')
      ? jsonDecode(text) as List<Object?>
      : [for (final line in const LineSplitter().convert(text)) if (line.trim().isNotEmpty) jsonDecode(line)];
  return List.unmodifiable([
    for (final row in rows.whereType<Map<String, Object?>>()) _container(row),
  ]);
}

ContainerStatus _container(Map<String, Object?> row) {
  final state = _state(row['State'] as String? ?? '');
  final publishers = (row['Publishers'] as List<Object?>? ?? const []).whereType<Map<String, Object?>>();
  return ContainerStatus(
    service: row['Service'] as String? ?? '',
    name: row['Name'] as String? ?? '',
    state: state,
    health: _health(row['Health'] as String? ?? ''),
    ports: List.unmodifiable({
      for (final p in publishers)
        if ((p['PublishedPort'] as num? ?? 0) > 0) (p['PublishedPort'] as num).toInt(),
    }.toList()),
    exitCode: state == ContainerState.running ? null : (row['ExitCode'] as num?)?.toInt(),
  );
}

ContainerState _state(String s) => switch (s) {
      'created' => ContainerState.created,
      'running' => ContainerState.running,
      'restarting' => ContainerState.restarting,
      'paused' => ContainerState.paused,
      'dead' => ContainerState.dead,
      _ => ContainerState.exited, // exited, removing
    };

ContainerHealth _health(String s) => switch (s) {
      'starting' => ContainerHealth.starting,
      'healthy' => ContainerHealth.healthy,
      'unhealthy' => ContainerHealth.unhealthy,
      _ => ContainerHealth.none,
    };

/// `docker ps --format` 의 `{{.Ports}}` 에서 이 컴퓨터에 연 포트를 꺼낸다.
/// 예: `0.0.0.0:8080->80/tcp, [::]:8080->80/tcp` → {8080}
Set<int> parsePublishedPorts(String ports) =>
    {for (final m in RegExp(r':(\d+)->').allMatches(ports)) int.parse(m[1]!)};

/// [text] 에서 `.env` 값을 `****` 로 가린다. 4글자보다 짧은 값은 흔한 단어와 겹쳐 가리지 않는다.
String maskSecrets(String text, Iterable<String> secrets) {
  var out = text;
  for (final s in secrets.where((s) => s.length >= 4).toList()..sort((a, b) => b.length - a.length)) {
    out = out.replaceAll(s, '****');
  }
  return out;
}

/// `.env` 파일의 값들. 파일이 없거나 읽을 수 없으면 빈 목록.
List<String> readEnvValues(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (!line.trimLeft().startsWith('#') && line.contains('='))
          line.substring(line.indexOf('=') + 1).trim().replaceAll(RegExp(r'''^["']|["']$'''), ''),
    ].where((v) => v.isNotEmpty).toList();
  } on FileSystemException {
    return const [];
  }
}

/// 프로세스의 stdout·stderr 를 줄 단위로 합쳐 흘려보낸다. 둘 다 끝나면 닫힌다.
Stream<String> processLines(Process process) {
  final controller = StreamController<String>();
  var open = 2;
  void done() {
    if (--open == 0) controller.close();
  }

  for (final stream in [process.stdout, process.stderr]) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(controller.add, onError: controller.addError, onDone: done);
  }
  return controller.stream;
}

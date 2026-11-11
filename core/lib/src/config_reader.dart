import '../models/check_config.dart';
import '../models/errors.dart';
import '../models/project_config.dart';
import '../models/ready_condition.dart';
import '../models/requirement.dart';
import '../models/service_config.dart';
import 'map_reader.dart';

/// [ProjectConfig.fromMap] 의 실제 읽기. 문제가 하나라도 있으면 모두 모아 던진다.
ProjectConfig readProjectConfig(Map<Object?, Object?> raw) {
  final r = MapReader();
  final map = r.asMap(raw, '')!;
  final config = _config(r, map);
  if (r.issues.isNotEmpty) {
    throw ConfigFormatException(r.issues);
  }
  return config;
}

ProjectConfig _config(MapReader r, Map<String, Object?> map) {
  r.onlyKeys(map, '', const {'version', 'name', 'about', 'requires', 'services', 'checks'});
  final version = r.integer(map, 'version', '', required: true);
  if (version != null && version != ProjectConfig.supportedVersion) {
    r.report('version', '이 앱은 version: ${ProjectConfig.supportedVersion} 설정만 읽을 수 있어요.');
  }
  return ProjectConfig(
    version: version ?? ProjectConfig.supportedVersion,
    name: r.string(map, 'name', ''),
    about: _about(r, map['about'], 'about'),
    requires: _items(r, map, 'requires', _requirement),
    services: _items(r, map, 'services', _service),
    checks: _items(r, map, 'checks', _check),
  );
}

/// 맨 위 목록의 항목을 하나씩 읽는다. 읽지 못한 항목은 빼고 문제만 남긴다.
List<T> _items<T>(
  MapReader r,
  Map<String, Object?> map,
  String key,
  T? Function(MapReader r, Map<String, Object?> item, String path) read,
) {
  final result = <T>[];
  for (final (i, value) in (r.list(map, key, '') ?? const []).indexed) {
    final path = MapReader.item(key, i);
    final item = r.asMap(value, path);
    if (item == null) {
      continue;
    }
    final parsed = read(r, item, path);
    if (parsed != null) {
      result.add(parsed);
    }
  }
  return result;
}

About _about(MapReader r, Object? value, String path) {
  if (value == null) {
    return const About();
  }
  final map = r.asMap(value, path);
  if (map == null) {
    return const About();
  }
  r.onlyKeys(map, path, const {'summary', 'stack', 'links', 'memo'});
  return About(
    summary: r.string(map, 'summary', path),
    stack: r.strings(map, 'stack', path),
    links: r.stringMap(map, 'links', path),
    memo: r.string(map, 'memo', path),
  );
}

Requirement? _requirement(MapReader r, Map<String, Object?> map, String path) {
  r.onlyKeys(map, path, const {'cli', 'version', 'docker'});
  if (map.containsKey('docker')) {
    if (map.containsKey('cli') || map.containsKey('version')) {
      r.report(path, 'docker 와 cli 는 한 칸에 같이 쓸 수 없어요. 칸을 나눠 주세요.');
      return null;
    }
    if (map['docker'] != true) {
      r.report(MapReader.child(path, 'docker'), 'docker: true 로만 적을 수 있어요.');
      return null;
    }
    return const DockerRequirement();
  }
  final cli = r.string(map, 'cli', path, required: true);
  final version = r.string(map, 'version', path);
  return cli == null ? null : CliRequirement(cli, version: version);
}

final _serviceIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');
const _commonServiceKeys = {'id', 'type', 'dependsOn', 'ready'};

ServiceConfig? _service(MapReader r, Map<String, Object?> map, String path) {
  final id = r.string(map, 'id', path, required: true);
  if (id != null && !_serviceIdPattern.hasMatch(id)) {
    r.report(MapReader.child(path, 'id'), '영문, 숫자, -, _ 만 쓸 수 있어요.');
  }
  final type = r.string(map, 'type', path, required: true);
  final dependsOn = r.strings(map, 'dependsOn', path);
  final readyPath = MapReader.child(path, 'ready');

  switch (type) {
    case 'process':
      r.onlyKeys(map, path, {..._commonServiceKeys, 'cwd', 'command', 'env', 'envFile', 'ports', 'stopTimeout'});
      final command = _command(r, map, path);
      final ready = _ready(r, map['ready'], readyPath, allowed: const ['port', 'http', 'log', 'none']);
      final cwd = _insidePath(r, map, 'cwd', path);
      final env = r.stringMap(map, 'env', path);
      final envFile = _insidePath(r, map, 'envFile', path);
      final ports = r.ints(map, 'ports', path, min: 1, max: 65535);
      final stopTimeout = r.seconds(map, 'stopTimeout', path);
      if (id == null || command == null) {
        return null;
      }
      return ProcessService(
        id: id,
        command: command,
        dependsOn: dependsOn,
        ready: ready ?? const NoneReady(),
        cwd: cwd ?? '.',
        env: env,
        envFile: envFile,
        ports: ports,
        stopTimeout: stopTimeout ?? ProcessService.defaultStopTimeout,
      );

    case 'compose':
      r.onlyKeys(map, path, {..._commonServiceKeys, 'file', 'services'});
      final file = _insidePath(r, map, 'file', path, required: true);
      final services = r.strings(map, 'services', path);
      final ready = _ready(r, map['ready'], readyPath, allowed: const ['port', 'http', 'log', 'compose-healthy', 'none']);
      if (id == null || file == null) {
        return null;
      }
      return ComposeService(id: id, file: file, services: services, dependsOn: dependsOn, ready: ready ?? const NoneReady());

    case 'remote':
      r.onlyKeys(map, path, _commonServiceKeys);
      if (map['ready'] == null) {
        r.report(readyPath, '원격 항목은 연결을 확인할 방법(http 또는 host 가 있는 port)을 꼭 적어야 해요.');
      }
      final ready = _ready(r, map['ready'], readyPath, allowed: const ['http', 'port'], hostRequired: true);
      if (id == null || ready == null) {
        return null;
      }
      return RemoteService(id: id, ready: ready, dependsOn: dependsOn);

    case null:
      return null; // type 이 없다는 문제는 이미 남겼다.

    default:
      r.report(MapReader.child(path, 'type'), 'process, compose, remote 중 하나로 적어 주세요.');
      return null;
  }
}

/// 실행 명령은 셸 문자열이 아니라 [실행 파일, 인자...] 목록이어야 한다.
List<String>? _command(MapReader r, Map<String, Object?> map, String parent) {
  final path = MapReader.child(parent, 'command');
  final value = map['command'];
  if (value is String) {
    r.report(path, '명령은 한 줄 글자가 아니라 목록으로 적어 주세요. 예: ["npm", "run", "dev"]');
    return null;
  }
  if (value is List && value.isEmpty) {
    r.report(path, '실행할 명령을 적어 주세요. 예: ["npm", "run", "dev"]');
    return null;
  }
  final issuesBefore = r.issues.length;
  final command = r.strings(map, 'command', parent, required: true);
  return r.issues.length == issuesBefore ? command : null;
}

/// 프로젝트 폴더 안을 가리키는 상대 경로만 받는다. 실행 위치가 프로젝트 밖으로 나가지 않게 하려고.
String? _insidePath(MapReader r, Map<String, Object?> map, String key, String parent, {bool required = false}) {
  final value = r.string(map, key, parent, required: required);
  if (value == null) {
    return null;
  }
  final normalized = value.replaceAll(r'\', '/');
  final isAbsolute = normalized.startsWith('/') || normalized.startsWith('~') || RegExp(r'^[A-Za-z]:').hasMatch(normalized);
  final goesUp = normalized.split('/').contains('..');
  if (isAbsolute || goesUp) {
    r.report(MapReader.child(parent, key), '프로젝트 폴더 안의 상대 경로로 적어 주세요. 예: ./backend');
    return null;
  }
  return value;
}

String? _url(MapReader r, Map<String, Object?> map, String key, String parent, {bool required = false}) {
  final value = r.string(map, key, parent, required: required);
  if (value == null) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
    r.report(MapReader.child(parent, key), 'http:// 또는 https:// 로 시작하는 주소로 적어 주세요.');
    return null;
  }
  return value;
}

ReadyCondition? _ready(
  MapReader r,
  Object? value,
  String path, {
  required List<String> allowed,
  bool hostRequired = false,
}) {
  if (value == null) {
    return null;
  }
  final map = r.asMap(value, path);
  if (map == null) {
    return null;
  }
  const common = {'type', 'timeout', 'interval'};
  final type = r.string(map, 'type', path, required: true);
  final timeout = r.seconds(map, 'timeout', path) ?? ReadyCondition.defaultTimeout;
  final interval = r.seconds(map, 'interval', path) ?? ReadyCondition.defaultInterval;
  if (type == null) {
    return null;
  }
  if (!allowed.contains(type)) {
    r.report(MapReader.child(path, 'type'), '이 항목에는 ${allowed.join(', ')} 중 하나만 쓸 수 있어요.');
    return null;
  }

  switch (type) {
    case 'port':
      r.onlyKeys(map, path, {...common, 'port', 'host'});
      final port = r.integer(map, 'port', path, required: true, min: 1, max: 65535);
      final host = r.string(map, 'host', path, required: hostRequired);
      return port == null ? null : PortReady(port: port, host: host, timeout: timeout, interval: interval);

    case 'http':
      r.onlyKeys(map, path, {...common, 'url', 'expectStatus'});
      final url = _url(r, map, 'url', path, required: true);
      final expectStatus = r.integer(map, 'expectStatus', path, min: 100, max: 599);
      return url == null ? null : HttpReady(url: url, expectStatus: expectStatus, timeout: timeout, interval: interval);

    case 'log':
      r.onlyKeys(map, path, {...common, 'pattern'});
      final pattern = r.string(map, 'pattern', path, required: true);
      if (pattern == null) {
        return null;
      }
      try {
        RegExp(pattern);
      } on FormatException {
        r.report(MapReader.child(path, 'pattern'), '정규식 형식이 올바르지 않아요.');
        return null;
      }
      return LogReady(pattern: pattern, timeout: timeout, interval: interval);

    case 'compose-healthy':
      r.onlyKeys(map, path, common);
      return ComposeHealthyReady(timeout: timeout, interval: interval);

    default: // 'none'
      r.onlyKeys(map, path, common);
      return NoneReady(timeout: timeout, interval: interval);
  }
}

CheckConfig? _check(MapReader r, Map<String, Object?> map, String path) {
  r.onlyKeys(map, path, const {'name', 'url', 'port', 'host', 'expectStatus'});
  final name = r.string(map, 'name', path, required: true);
  final url = _url(r, map, 'url', path);
  final port = r.integer(map, 'port', path, min: 1, max: 65535);
  final host = r.string(map, 'host', path);
  final expectStatus = r.integer(map, 'expectStatus', path, min: 100, max: 599);
  var ok = true;
  if (map['url'] != null && map['port'] != null) {
    r.report(path, 'url 과 port 중 하나만 적어 주세요.');
    ok = false;
  }
  if (map['host'] != null && map['port'] == null) {
    r.report(MapReader.child(path, 'host'), 'host 는 port 와 함께 써요.');
    ok = false;
  }
  if (map['expectStatus'] != null && map['url'] == null) {
    r.report(MapReader.child(path, 'expectStatus'), 'expectStatus 는 url 과 함께 써요.');
    ok = false;
  }
  if (name == null || !ok) {
    return null;
  }
  return CheckConfig(name: name, url: url, port: port, host: host, expectStatus: expectStatus);
}

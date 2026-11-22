import 'dart:io';

/// 테스트용 중계(`ppoling-relay`) 실행 파일. 소스가 바뀌었을 때만 `build/test-relay/` 에 다시 컴파일한다.
Future<String> relayBinary() async {
  final out = File('build/test-relay/ppoling-relay${Platform.isWindows ? '.exe' : ''}');
  final sources = Directory('relay').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  final newest = sources.map((f) => f.lastModifiedSync()).reduce((a, b) => a.isAfter(b) ? a : b);
  if (out.existsSync() && out.lastModifiedSync().isAfter(newest)) return out.absolute.path;

  final root = Platform.environment['FLUTTER_ROOT'];
  final dart = root == null ? 'dart' : [root, 'bin', Platform.isWindows ? 'dart.bat' : 'dart'].join(Platform.pathSeparator);
  Future<void> run(List<String> args) async {
    final r = await Process.run(dart, args, runInShell: Platform.isWindows);
    if (r.exitCode != 0) throw StateError('dart ${args.join(' ')} 실패:\n${r.stdout}\n${r.stderr}');
  }

  await run(['pub', 'get', '--directory', 'relay']);
  out.parent.createSync(recursive: true);
  // 테스트 파일 여러 개가 동시에 컴파일해도 반쯤 쓴 파일을 쓰지 않게 다른 이름으로 만든 뒤 바꿔 끼운다.
  final tmp = '${out.path}.$pid';
  await run(['compile', 'exe', 'relay/bin/ppoling_relay.dart', '-o', tmp]);
  try {
    File(tmp).renameSync(out.path);
  } on FileSystemException {
    // Windows 는 다른 테스트 파일이 실행 중인 중계를 덮어쓸 수 없다. 그쪽이 먼저 만든 것을 쓴다.
    if (!out.existsSync()) rethrow;
    File(tmp).deleteSync();
  }
  return out.absolute.path;
}

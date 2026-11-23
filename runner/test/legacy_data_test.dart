import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_runner/src/runtime/legacy_data.dart';

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('popoling_home_')); // 위쪽 경로의 popoling 은 바꾸지 않는다
  tearDown(() => home.deleteSync(recursive: true));

  String p(List<String> parts) => [home.path, ...parts].join(Platform.pathSeparator);

  test('옛 이름은 마지막 두 칸에서만 바꾼다 (macOS 번들 ID, Windows 회사·제품)', () {
    expect(legacyDataDir(Directory(p(['Application Support', 'dev.popoling.popoling']))).path,
        p(['Application Support', 'dev.ppoling.ppoling']));
    expect(legacyDataDir(Directory(p(['Roaming', 'dev.popoling', 'popoling']))).path, p(['Roaming', 'dev.ppoling', 'ppoling']));
  });

  test('새 폴더가 없고 옛 폴더가 있으면 옮긴다', () async {
    File(p(['Roaming', 'dev.ppoling', 'ppoling', 'runtime.json']))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    final now = Directory(p(['Roaming', 'dev.popoling', 'popoling']));
    await moveLegacyDataDir(now);
    expect(File('${now.path}${Platform.pathSeparator}runtime.json').readAsStringSync(), '{}');
    expect(Directory(p(['Roaming', 'dev.ppoling', 'ppoling'])).existsSync(), isFalse);
  });

  test('새 폴더가 이미 있으면 아무것도 하지 않는다', () async {
    final legacy = Directory(p(['dev.ppoling.ppoling']))..createSync(recursive: true);
    final now = Directory(p(['dev.popoling.popoling']))..createSync(recursive: true);
    await moveLegacyDataDir(now);
    expect(legacy.existsSync(), isTrue);
    expect(now.listSync(), isEmpty);
  });

  test('옛 폴더가 없으면 아무것도 하지 않는다', () async {
    final now = Directory(p(['dev.popoling.popoling']));
    await moveLegacyDataDir(now);
    expect(now.existsSync(), isFalse);
  });
}

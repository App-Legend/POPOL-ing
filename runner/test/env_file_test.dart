import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_runner/src/orchestrator/env_file.dart';

void main() {
  test('따옴표·export·주석을 다루고, 값 뒤 주석은 뗀다', () {
    final dir = Directory.systemTemp.createTempSync('popoling_env_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/.env')
      ..writeAsStringSync('# 주석\n'
          'PORT=3000 # dev\n'
          'export NAME="a # b" # 이름\n'
          "SINGLE='x'\n"
          'HASH=abc#def\n'
          'EMPTY= # 비어 있음\n');
    expect(readEnvFile(file.path), {
      'PORT': '3000',
      'NAME': 'a # b',
      'SINGLE': 'x',
      'HASH': 'abc#def',
      'EMPTY': '',
    });
  });
}

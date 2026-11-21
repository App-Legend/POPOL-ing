import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_relay/log_file.dart';

/// 실행 항목 로그 `<root>/<projectId>/<serviceId>.log` 의 위치와 읽기. 쓰기는 중계(`ppoling-relay`)가 한다.
class LogStore {
  LogStore(this._root, {this.maxBytes = 10 * 1024 * 1024, this.keep = 3});

  final Future<Directory> Function() _root;

  /// 파일 하나의 최대 크기(바이트). 중계에 넘긴다.
  final int maxBytes;

  /// `.log` 를 포함해 남기는 파일 수.
  final int keep;

  /// [item] 의 지금 로그 파일(없을 수도 있다).
  Future<File> fileOf(ItemRef item) async {
    final root = await _root();
    return File([root.path, item.projectId, '${item.serviceId}.log'].join(Platform.pathSeparator));
  }

  /// [item] 의 로그 마지막 [lines] 줄. 지금 파일 줄이 모자라면 막 밀려난 `.log.1` 끝에서 채운다.
  /// 파일이 없으면 빈 목록. 파일마다 끝 [maxRead] 바이트만 읽는다.
  Future<List<String>> tail(ItemRef item, {int lines = 5000, int maxRead = 1024 * 1024}) async {
    final file = await fileOf(item);
    final (now, whole) = await _tailOf(file, lines, maxRead);
    if (now.length >= lines || !whole) return now; // 중간부터 읽었으면 .log.1 과 이어지지 않는다
    final (older, _) = await _tailOf(File('${file.path}.1'), lines - now.length, maxRead);
    return [...older, ...now];
  }

  /// [item] 의 마지막 실행이 끝났으면 그 종료 코드(로그 끝 줄). 아직 안 끝났거나 모르면 null.
  Future<int?> lastExitCode(ItemRef item) async => switch (await tail(item, lines: 1)) {
        [final last] => exitCodeOf(last),
        _ => null,
      };

  /// [file] 마지막 [lines] 줄과, 파일을 처음부터 다 읽었는지.
  Future<(List<String>, bool)> _tailOf(File file, int lines, int maxRead) async {
    try {
      final raf = await file.open();
      try {
        final length = await raf.length();
        final start = length > maxRead ? length - maxRead : 0;
        await raf.setPosition(start);
        final all = const LineSplitter().convert(utf8.decode(await raf.read(length - start), allowMalformed: true));
        final whole = start == 0 ? all : all.skip(1).toList(); // 중간부터 읽었으면 첫 줄은 잘린 줄이다
        return (whole.length > lines ? whole.sublist(whole.length - lines) : whole, start == 0);
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return (const <String>[], true);
    }
  }
}

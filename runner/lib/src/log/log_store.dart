import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

import '../process/process_launcher.dart';

/// 실행 항목의 출력을 `<root>/<projectId>/<serviceId>.log` 에 쌓는 부품. 크기가 넘으면 `.log.1`, `.log.2` 로 밀어낸다.
///
/// 로그를 못 써도 실행은 멈추지 않는다. 쓰기 실패는 삼킨다.
class LogStore {
  LogStore(this._root, {this.maxBytes = 10 * 1024 * 1024, this.keep = 3});

  final Future<Directory> Function() _root;

  /// 파일 하나의 최대 크기(바이트).
  final int maxBytes;

  /// `.log` 를 포함해 남기는 파일 수.
  final int keep;

  // 같은 항목의 기록이 섞이지 않게 항목마다 이전 기록 뒤에 잇는다.
  final _tails = <ItemRef, Future<void>>{};

  /// [lines] 를 끝날 때까지 [item] 의 로그 파일에 쓴다. [secrets] 는 쓰기 전에 `****` 로 가린다.
  /// 같은 항목의 이전 기록이 남아 있으면 그게 끝난 뒤 쓴다. 쓰기에 실패해도 예외를 내지 않는다.
  Future<void> record(ItemRef item, Stream<OutputLine> lines, {Iterable<String> secrets = const []}) {
    final next = (_tails[item] ?? Future.value()).then((_) => _write(item, lines, secrets));
    return _tails[item] = next;
  }

  /// [item] 의 지금 로그 파일(없을 수도 있다).
  Future<File> fileOf(ItemRef item) async {
    final root = await _root();
    return File('${root.path}/${item.projectId}/${item.serviceId}.log');
  }

  Future<void> _write(ItemRef item, Stream<OutputLine> lines, Iterable<String> secrets) async {
    // 긴 값부터 가려야 짧은 값이 긴 값의 일부를 먼저 갉아먹지 않는다.
    final masks = secrets.where((s) => s.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
    String mask(String t) => masks.fold(t, (acc, s) => acc.replaceAll(s, '****'));

    File? file;
    IOSink? sink;
    var size = 0;

    Future<void> put(String line) async {
      final bytes = utf8.encode('$line\n');
      if (size > 0 && size + bytes.length > maxBytes) {
        await sink!.close();
        sink = null;
        await _rotate(file!);
        size = 0;
        sink = file!.openWrite(mode: FileMode.append);
      }
      sink!.add(bytes);
      size += bytes.length;
      await sink!.flush();
    }

    try {
      file = await fileOf(item);
      await file.parent.create(recursive: true);
      size = file.existsSync() ? await file.length() : 0;
      sink = file.openWrite(mode: FileMode.append);
      await put('--- 시작 ${DateTime.now().toIso8601String()} ---');
    } catch (_) {
      sink = null;
    }
    // 쓰기가 실패해도 끝까지 읽는다. 안 그러면 보내는 쪽이 막힌다.
    await for (final l in lines) {
      if (sink == null) continue;
      try {
        await put('${l.at.toIso8601String()} ${l.isError ? 'err' : 'out'} | ${mask(l.text)}');
      } catch (_) {
        sink = null;
      }
    }
    try {
      await sink?.close();
    } catch (_) {}
  }

  /// `.log.(keep-2)` … `.log.1` 을 한 칸씩 뒤로 밀고 `.log` 를 `.log.1` 로 옮긴다. 가장 오래된 것은 덮어쓴다.
  Future<void> _rotate(File file) async {
    for (var i = keep - 2; i >= 1; i--) {
      final older = File('${file.path}.$i');
      if (older.existsSync()) await older.rename('${file.path}.${i + 1}');
    }
    await file.rename('${file.path}.1');
  }
}

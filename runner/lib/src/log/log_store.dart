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
    Future<void> run(Object? _) => _write(item, lines, secrets);
    final next = (_tails[item] ?? Future.value()).then(run, onError: run);
    return _tails[item] = next;
  }

  /// [item] 의 지금 로그 파일(없을 수도 있다).
  Future<File> fileOf(ItemRef item) async {
    final root = await _root();
    return File([root.path, item.projectId, '${item.serviceId}.log'].join(Platform.pathSeparator));
  }

  /// [item] 의 지금 기록이 다 써지면 끝난다. 기록 중인 게 없으면 바로 끝난다.
  Future<void> idle(ItemRef item) => _tails[item] ?? Future.value();

  /// [item] 의 로그 마지막 [lines] 줄. 지금 파일 줄이 모자라면 막 밀려난 `.log.1` 끝에서 채운다.
  /// 파일이 없으면 빈 목록. 파일마다 끝 [maxRead] 바이트만 읽는다.
  Future<List<String>> tail(ItemRef item, {int lines = 5000, int maxRead = 1024 * 1024}) async {
    final file = await fileOf(item);
    final (now, whole) = await _tailOf(file, lines, maxRead);
    if (now.length >= lines || !whole) return now; // 중간부터 읽었으면 .log.1 과 이어지지 않는다
    final (older, _) = await _tailOf(File('${file.path}.1'), lines - now.length, maxRead);
    return [...older, ...now];
  }

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
        try {
          await _rotate(file!);
        } catch (_) {} // 다른 프로그램이 파일을 잡고 있으면 밀지 못한다. 그대로 이어 쓰고 maxBytes 뒤에 다시 시도한다.
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
    try {
      await for (final l in lines) {
        if (sink == null) continue;
        try {
          await put('${l.at.toIso8601String()} ${l.isError ? 'err' : 'out'} | ${mask(l.text)}');
        } catch (_) {
          sink = null;
        }
      }
    } catch (_) {} // 입력 스트림 오류: 거기까지 쓰고 끝낸다
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:popoling_runner_relay/log_file.dart';
import 'package:popoling_runner_relay/relay_request.dart';
import 'package:popoling_runner_relay/src/os.dart';

/// 서비스 하나를 띄워 출력을 받아 적는 중계. 앱이 꺼져도 서비스가 출력할 곳을 잃고 죽지 않게 한다.
///
/// stdin 첫 줄로 [RelayRequest] 를 받는다. 서비스 출력은 줄마다 `.env` 값을 가려 로그 파일에 쓰고,
/// 같은 줄을 자기 stdout·stderr 로 앱에 넘긴다. 앱이 꺼져 넘기기가 실패하면 넘기기만 그만둔다.
/// 서비스가 끝나면 끝 줄을 남기고 같은 종료 코드로 끝난다(신호로 끝났으면 128+신호 번호).
Future<void> main() async {
  final line = await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  final request = RelayRequest.decode(line);
  if (Platform.isWindows) {
    if (request.jobName case final name?) holdJob(name);
  } else {
    becomeGroupLeader();
    // 앱이 그룹째 TERM 을 보내면 서비스가 남기는 마지막 출력까지 받아 적고 끝난다. KILL 은 막을 수 없다.
    ProcessSignal.sigterm.watch().listen((_) {});
  }

  final log = RotatingLogFile(File(request.logFile), maxBytes: request.maxBytes, keep: request.keep);
  await log.open();
  await log.write(startLine(DateTime.now()));

  var forward = true;
  unawaited(stdout.done.catchError((_) => forward = false));
  unawaited(stderr.done.catchError((_) => forward = false));
  Future<void> emit(String text, {required bool isError}) async {
    final masked = maskSecrets(text, request.secrets);
    await log.write(outputLine(DateTime.now(), masked, isError: isError));
    if (!forward) return;
    try {
      (isError ? stderr : stdout).writeln(masked);
    } catch (_) {
      forward = false; // 앱이 꺼졌다. 파일에는 계속 쓴다
    }
  }

  Future<void> finish(int code) async {
    await log.write(endLine(code));
    await log.close();
    try {
      await Future.wait([stdout.flush(), stderr.flush()]).timeout(const Duration(seconds: 1));
    } catch (_) {}
    exit(code < 0 ? 128 - code : code);
  }

  final Process service;
  try {
    service = await Process.start(request.command.first, request.command.sublist(1));
  } on ProcessException {
    await emit('명령을 찾을 수 없어요: ${request.command.first}', isError: true);
    await finish(127);
    return;
  }
  service.stdin.close().ignore(); // 입력을 기다리는 명령이 영영 멈춰 있지 않게 바로 EOF 를 준다

  // stdout·stderr 를 나온 순서대로 한 줄씩 적는다. 둘 다 닫히면(자식·손자까지 출력을 닫으면) 끝난다.
  final lines = StreamController<(String, bool)>();
  var open = 2;
  void pipe(Stream<List<int>> bytes, {required bool isError}) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .listen((l) => lines.add((l, isError)), onDone: () {
        if (--open == 0) lines.close();
      });
  pipe(service.stdout, isError: false);
  pipe(service.stderr, isError: true);
  await for (final (text, isError) in lines.stream) {
    await emit(text, isError: isError);
  }
  await finish(await service.exitCode);
}

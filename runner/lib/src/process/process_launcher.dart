import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'posix_process_launcher.dart';
import 'windows_process_launcher.dart';

/// 실행 항목 프로세스를 띄우는 부품. OS별 구현이 프로세스 트리를 통째로 멈출 수 있게 띄운다.
///
/// `runner/` 안에서만 쓴다. 다른 기능은 `Orchestrator` 계약으로 실행을 맡긴다.
abstract interface class ProcessLauncher {
  /// 이 OS 의 구현. OS 를 고르는 곳은 여기 한 곳이다.
  static ProcessLauncher forPlatform() => Platform.isWindows ? WindowsProcessLauncher() : PosixProcessLauncher();

  /// [command] 를 셸 해석 없이 실행한다. [command] 의 첫 칸은 PATH 에서 찾는다.
  ///
  /// 명령이 없거나 바로 실패해도 예외가 아니라, 종료 코드와 stderr 로 알린다(없는 명령은 127).
  /// [command] 가 비어 있으면 [ArgumentError], [workingDirectory] 가 없으면 [ProcessException].
  Future<RunningProcess> start(
    List<String> command, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  });
}

/// 띄운 프로세스 하나(와 그 자식들).
abstract interface class RunningProcess {
  /// 띄운 프로세스의 PID.
  int get pid;

  /// 멈출 때 신호를 보낼 프로세스 그룹. 자식·손자도 이 그룹에 든다.
  int get pgid;

  DateTime get startedAt;

  /// stdout·stderr 를 줄 단위로, 나온 순서대로. 프로세스가 출력을 닫으면 끝난다. 한 번만 구독할 수 있다.
  Stream<OutputLine> get output;

  /// 띄운 프로세스의 종료 코드. 자식·손자는 그 뒤에도 남아 있을 수 있다([groupAlive]).
  Future<int> get exitCode;

  /// 그룹에 프로세스가 하나라도 남아 있다.
  Future<bool> get groupAlive;

  /// [pid] 가 지금 이 그룹(Windows 는 Job)에 든 프로세스다. 포트 주인이 내 항목인지 판단할 때 쓴다.
  /// 확인할 수 없으면 false 다(내 것이라고 하지 않는다).
  Future<bool> contains(int pid);

  /// 그룹 전체에 종료 신호를 보내고 [timeout] 동안 기다린다. 그래도 남아 있으면 강제 종료한다.
  /// 이미 끝났으면 아무것도 하지 않는다.
  Future<StopResult> stop(Duration timeout);
}

/// 출력 한 줄.
class OutputLine {
  const OutputLine(this.text, {required this.isError, required this.at});

  final String text;

  /// stderr 에서 나온 줄.
  final bool isError;

  final DateTime at;
}

/// 멈춘 결과.
class StopResult {
  const StopResult({required this.forced});

  /// 종료 신호로 멈추지 않아 강제 종료했다(전체 종료 결과에 표시).
  final bool forced;
}

/// [process] 의 stdout·stderr 를 줄 단위로, 나온 순서대로. 둘 다 닫히면 끝난다.
/// 바로 읽기 시작해 둔다. 안 읽으면 출력 버퍼가 차서 프로세스가 멈춘다.
Stream<OutputLine> outputLines(Process process) {
  final out = StreamController<OutputLine>();
  var open = 2;
  void pipe(Stream<List<int>> bytes, {required bool isError}) {
    bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) => out.add(OutputLine(line, isError: isError, at: DateTime.now())), onDone: () {
      if (--open == 0) out.close();
    });
  }

  pipe(process.stdout, isError: false);
  pipe(process.stderr, isError: true);
  return out.stream;
}

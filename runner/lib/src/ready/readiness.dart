import 'dart:async';

import 'package:popoling_core/contracts.dart';

/// 준비 확인 결과.
class ReadyResult {
  const ReadyResult.ready()
      : ok = true,
        reason = null,
        timedOut = false;

  const ReadyResult.failed(String this.reason, {this.timedOut = false}) : ok = false;

  final bool ok;

  /// 제한 시간이 지나 실패했다(준비 시간 초과). 프로세스가 먼저 끝났거나 멈췄으면 false.
  final bool timedOut;

  /// 실패 이유. 화면에 그대로 보여줄 수 있는 문장.
  final String? reason;
}

/// 실행 항목이 준비 완료가 될 때까지 기다린다(기획서 §6 준비 조건 유형).
///
/// 포트·HTTP 확인은 C 의 [PortProbe]·[HttpProbe] 에 맡기고, 여기서는 되풀이·제한 시간·조기 종료만 다룬다.
class Readiness {
  Readiness({required this.ports, required this.http});

  final PortProbe ports;
  final HttpProbe http;

  /// [condition] 이 채워지거나 제한 시간이 지날 때까지 기다린다.
  ///
  /// - [lines]: 항목 출력. `log` 조건에 꼭 넘긴다.
  /// - [composeHealthy]: Compose 항목이 healthy 인지 묻는 함수. `compose-healthy` 조건에 꼭 넘긴다.
  /// - [exited]: 프로세스 종료. 기다리는 중에 끝나면 바로 실패한다.
  /// - [cancelled]: 사용자가 멈췄다. 끝나면 더 기다리지 않고 바로 실패한다.
  ///
  /// 확인 중에 예외가 나도 멈추지 않는다. 아직 준비 안 됨으로 보고 제한 시간까지 다시 확인한다.
  Future<ReadyResult> wait(
    ReadyCondition condition, {
    Stream<String>? lines,
    Future<bool> Function()? composeHealthy,
    Future<int>? exited,
    Future<void>? cancelled,
  }) {
    if (condition is LogReady && lines == null) throw ArgumentError.notNull('lines');
    if (condition is ComposeHealthyReady && composeHealthy == null) throw ArgumentError.notNull('composeHealthy');
    if (condition is NoneReady) return Future.value(const ReadyResult.ready());

    final result = Completer<ReadyResult>();
    void finish(ReadyResult r) {
      if (!result.isCompleted) result.complete(r);
    }

    exited?.then((code) => finish(ReadyResult.failed('준비되기 전에 종료됐어요 (종료 코드 $code).')));
    cancelled?.then((_) => finish(const ReadyResult.failed('준비를 기다리는 중에 멈췄어요.')));

    if (condition case LogReady(:final pattern)) {
      final regex = RegExp(pattern);
      final sub = lines!.listen((line) {
        if (regex.hasMatch(line)) finish(const ReadyResult.ready());
      }, onError: (Object e) {
        // 로그를 못 읽으면 제한 시간까지 기다려도 소용없으니 진짜 원인으로 바로 실패한다
        finish(ReadyResult.failed('출력을 읽지 못했어요: ${e is PopolingException ? e.message : e}'));
      });
      final timer = Timer(condition.timeout, () => finish(_timedOut(condition, '"$pattern" 이 출력에 나오지 않았어요')));
      result.future.whenComplete(() {
        timer.cancel();
        sub.cancel();
      });
    } else {
      _poll(condition, composeHealthy, result, finish);
    }
    return result.future;
  }

  Future<void> _poll(ReadyCondition condition, Future<bool> Function()? composeHealthy, Completer<ReadyResult> result,
      void Function(ReadyResult) finish) async {
    final deadline = DateTime.now().add(condition.timeout);
    while (!result.isCompleted) {
      String? last;
      try {
        last = await _check(condition, composeHealthy);
      } catch (e) {
        last = '확인하지 못했어요 ($e)';
      }
      if (last == null) return finish(const ReadyResult.ready());
      if (!DateTime.now().isBefore(deadline)) return finish(_timedOut(condition, last));
      await Future<void>.delayed(condition.interval);
    }
  }

  /// 준비됐으면 null, 아니면 마지막 확인 결과 한 줄.
  Future<String?> _check(ReadyCondition condition, Future<bool> Function()? composeHealthy) async {
    final probe = switch (condition) {
      PortReady(:final port, :final host) => await ports.connect(port, host: host),
      HttpReady(:final url, :final expectStatus) => await http.get(url, expectStatus: expectStatus),
      ComposeHealthyReady() => null,
      LogReady() || NoneReady() => throw StateError('되풀이 확인 대상이 아니에요: $condition'),
    };
    if (probe == null) return await composeHealthy!() ? null : '컨테이너가 아직 healthy 가 아니에요';
    return probe.ok ? null : '${probe.target} ${probe.failureReason ?? ''}'.trim();
  }

  static ReadyResult _timedOut(ReadyCondition condition, String last) {
    final t = condition.timeout;
    final limit = t.inSeconds >= 1 ? '${t.inSeconds}초' : '${t.inMilliseconds}ms';
    return ReadyResult.failed('준비 시간($limit)을 넘겼어요. 마지막 확인: $last', timedOut: true);
  }
}

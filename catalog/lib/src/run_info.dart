import 'dart:async';

/// 카드에 보일 프로젝트 하나의 실행 정보(FR-14).
///
/// A 의 실행 기록 계약이 core 에 생기면 그걸 읽어 이 모양으로 바꿔 준다. 그때까지는 [FakeRunInfoSource].
class RunInfo {
  const RunInfo({this.lastRunAt, this.lastSucceeded, this.running = 0});

  /// 실행 기록이 없는 상태.
  static const none = RunInfo();

  /// 마지막으로 실행한 때. 실행 기록이 없으면 null.
  final DateTime? lastRunAt;

  /// 마지막 실행이 성공했는지. 실행 기록이 없으면 null.
  final bool? lastSucceeded;

  /// 지금 떠 있는 항목 수(원격 항목은 세지 않는다).
  final int running;
}

/// 프로젝트별 실행 정보를 주는 곳. 카탈로그 안에서만 쓴다.
abstract interface class RunInfoSource {
  /// 프로젝트 ID → 실행 정보. 기록이 없는 프로젝트는 빠진다.
  /// 구독하면 지금 것부터 한 번 보내고, 바뀔 때마다 전체를 다시 보낸다.
  Stream<Map<String, RunInfo>> watchRunInfo();
}

/// [RunInfoSource] 의 가짜 구현. A 의 실행 기록이 붙기 전까지 화면에 쓴다.
class FakeRunInfoSource implements RunInfoSource {
  FakeRunInfoSource([Map<String, RunInfo> info = const {}]) : _info = Map.unmodifiable(info);

  /// 목업과 같은 샘플 프로젝트 5개(`SampleProjects`)의 실행 정보. 날짜는 [clock] 의 지금을 기준으로 한다.
  factory FakeRunInfoSource.samples({DateTime Function()? clock}) {
    final now = (clock ?? DateTime.now)();
    DateTime ago(Duration d) => now.subtract(d);
    return FakeRunInfoSource({
      'my-team-project': RunInfo(lastRunAt: ago(const Duration(hours: 1)), lastSucceeded: true, running: 3),
      'ppoling': RunInfo(lastRunAt: ago(const Duration(days: 1)), lastSucceeded: true),
      'weather-bot': RunInfo(lastRunAt: ago(const Duration(days: 249)), lastSucceeded: false),
      'shop-clone': RunInfo(lastRunAt: ago(const Duration(days: 349)), lastSucceeded: true),
    });
  }

  Map<String, RunInfo> _info;
  final List<StreamController<Map<String, RunInfo>>> _watchers = [];

  /// 실행 정보를 바꾸고 구독자에게 다시 보낸다.
  void update(Map<String, RunInfo> info) {
    _info = Map.unmodifiable(info);
    for (final w in [..._watchers]) {
      w.add(_info);
    }
  }

  @override
  Stream<Map<String, RunInfo>> watchRunInfo() {
    late final StreamController<Map<String, RunInfo>> controller;
    controller = StreamController(
      onListen: () {
        controller.add(_info);
        _watchers.add(controller);
      },
      onCancel: () => _watchers.remove(controller),
    );
    return controller.stream;
  }
}

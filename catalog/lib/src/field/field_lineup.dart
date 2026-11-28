import '../catalog_view.dart';
import 'field_panel.dart';

/// 운동장에 누구를 어디에 세울지. 화면과 떼어 두어 따로 시험한다.
class FieldLineup {
  const FieldLineup({required this.lanes, required this.running, required this.fallen, this.bench});

  /// 실행 중·넘어짐·출발선 대기·실행 방법 없음 순. 레인은 앞의 4개만 그린다.
  final List<FieldRunner> lanes;

  /// 벤치에서 조는 프로젝트(오래됨): 이름과 상태 글자.
  final (String, String)? bench;

  /// 전광판 숫자. 레인 4개에 다 못 서도 모든 프로젝트를 센다.
  final int running;
  final int fallen;

  String get score => '달리는 중 $running · 넘어짐 $fallen';
}

/// 프로젝트 목록으로 운동장 배치를 만든다.
///
/// - 실패한 프로젝트는 오래됐어도 레인에 넘어진 채로 둔다(왼쪽 "지금 상태"가 실패를 먼저 보여 주는 것과 같게).
/// - 벤치에는 가장 오래 쉰 프로젝트 하나를 앉히고, 나머지 오래된 프로젝트는 "외 n개"로 알린다.
FieldLineup fieldLineup(List<CatalogEntry> entries, DateTime now) {
  bool failed(CatalogEntry e) => !e.isRunning && e.run.lastSucceeded == false;

  final stale = [for (final e in entries) if (e.isStale(now) && !failed(e)) e]
    ..sort((a, b) => a.run.lastRunAt!.compareTo(b.run.lastRunAt!));
  final lanes = [for (final e in entries) if (!stale.contains(e)) _runner(e)]
    ..sort((a, b) => a.pose.index.compareTo(b.pose.index));

  (String, String)? bench;
  if (stale.isNotEmpty) {
    final rest = stale.length - 1;
    bench = (stale.first.project.name, [cardStateLabel(stale.first, now), if (rest > 0) '외 $rest개'].join(' '));
  }
  return FieldLineup(
    lanes: lanes,
    bench: bench,
    running: lanes.where((l) => l.pose == FieldPose.run).length,
    fallen: lanes.where((l) => l.pose == FieldPose.fallen).length,
  );
}

FieldRunner _runner(CatalogEntry e) {
  final p = e.project;
  if (e.serviceCount == 0 && (p.config?.services.isEmpty ?? true)) {
    return FieldRunner(name: p.name, status: '실행 방법 없음', pose: FieldPose.empty);
  }
  // 시작 중·종료 중인 항목도 세므로 "준비 완료"라고 하지 않는다.
  if (e.isRunning) return FieldRunner(name: p.name, status: '실행 중 · ${e.run.running}/${e.serviceCount}', pose: FieldPose.run);
  if (e.run.lastSucceeded == false) return FieldRunner(name: p.name, status: '실패 · 원인 보기', pose: FieldPose.fallen);
  return FieldRunner(name: p.name, status: '중지 · 출발선 대기', pose: FieldPose.wait);
}

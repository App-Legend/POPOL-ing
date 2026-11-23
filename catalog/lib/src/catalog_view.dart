import 'package:popoling_core/models.dart';

import 'run_info.dart';

/// 이만큼 넘게 실행하지 않으면 "오래됨"(FR-17 기본 90일). 결과(성공·실패)와 상관없이 마지막 실행일로 본다.
const staleAfter = Duration(days: 90);

/// 카탈로그 카드 하나: 프로젝트와 그 실행 정보.
class CatalogEntry {
  CatalogEntry(this.project, this.run);

  final Project project;
  final RunInfo run;

  /// 띄우는 실행 항목 수. 원격 항목은 연결만 확인하고 전체 종료에서도 그대로라 세지 않는다. 설정이 없으면 0.
  int get serviceCount => project.config?.services.where((s) => s is! RemoteService).length ?? 0;

  bool get isRunning => run.running > 0;

  /// 실행 중이 아니고, 마지막 실행이 [staleAfter] 보다 오래됐는지. 실행 기록이 없으면 오래됨이 아니다.
  bool isStale(DateTime now) {
    final at = run.lastRunAt;
    return !isRunning && at != null && now.difference(at) > staleAfter;
  }
}

/// 카드 상태 칩의 종류.
enum CardState { running, stale, stopped, never }

/// 위에서부터 먼저 맞는 것: 실행 중 → 오래됨 → 중지(기록 있음) → 실행 기록 없음.
CardState cardStateOf(CatalogEntry e, DateTime now) {
  if (e.isRunning) return CardState.running;
  if (e.isStale(now)) return CardState.stale;
  if (e.run.lastRunAt != null) return CardState.stopped;
  return CardState.never;
}

/// 카드 상태 칩 문구. 색만으로 구분하지 않게 늘 글로 쓴다.
String cardStateLabel(CatalogEntry e, DateTime now) => switch (cardStateOf(e, now)) {
      CardState.running => '실행 중 ${e.run.running}/${e.serviceCount}',
      CardState.stale => '오래됨 · ${_period(now.difference(e.run.lastRunAt!))}',
      CardState.stopped => '중지',
      CardState.never => '실행 기록 없음',
    };

String _period(Duration d) => d.inDays < 365 ? '${d.inDays ~/ 30}개월' : '${d.inDays ~/ 365}년';

/// `마지막 실행 오늘 14:02` · `마지막 실행 어제` · `마지막 실행 2026-03-12`. 기록이 없으면 null.
String? lastRunText(RunInfo run, DateTime now) {
  final at = run.lastRunAt?.toLocal();
  if (at == null) return null;
  final local = now.toLocal();
  // 달력 날짜끼리 비교한다. UTC 로 만들어 서머타임에 하루 길이가 흔들리지 않게.
  final days = DateTime.utc(local.year, local.month, local.day).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  return switch (days) {
    0 => '마지막 실행 오늘 ${two(at.hour)}:${two(at.minute)}',
    1 => '마지막 실행 어제',
    _ => '마지막 실행 ${at.year}-${two(at.month)}-${two(at.day)}',
  };
}

/// 전체 실행·종료 결과를 카드에 남길 한 줄. 모두 성공했으면 null.
/// 예: `시작하지 못한 항목: api · 건너뜀: web`. 항목 이름은 popoling.yaml 의 id 그대로 쓴다.
String? runProblemText(RunSummary summary, {required bool stopping}) {
  List<String> idsOf(ItemOutcome outcome) => [
        for (final r in summary.items)
          if (r.outcome == outcome) r.item.serviceId,
      ];
  final failed = idsOf(ItemOutcome.failed);
  final skipped = idsOf(ItemOutcome.skipped);
  final parts = [
    if (failed.isNotEmpty) '${stopping ? '멈추지' : '시작하지'} 못한 항목: ${failed.join(', ')}',
    if (skipped.isNotEmpty) '건너뜀: ${skipped.join(', ')}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

enum _FilterKind { all, running, stale, tag }

/// 필터 칩 하나. 한 번에 하나만 고른다.
class CatalogFilter {
  const CatalogFilter._(this.label, this._kind);

  static const all = CatalogFilter._('전체', _FilterKind.all);
  static const running = CatalogFilter._('실행 중', _FilterKind.running);
  static const stale = CatalogFilter._('오래됨', _FilterKind.stale);

  /// 기술 스택 태그로 거르는 칩. 대소문자는 구분하지 않는다.
  factory CatalogFilter.tag(String tag) => CatalogFilter._(tag, _FilterKind.tag);

  /// 칩에 보이는 글자.
  final String label;
  final _FilterKind _kind;

  bool get isTag => _kind == _FilterKind.tag;

  bool matches(CatalogEntry e, DateTime now) => switch (_kind) {
        _FilterKind.all => true,
        _FilterKind.running => e.isRunning,
        _FilterKind.stale => e.isStale(now),
        _FilterKind.tag => e.project.about.stack.any((s) => s.toLowerCase() == label.toLowerCase()),
      };

  String get _key => isTag ? label.toLowerCase() : label;

  @override
  bool operator ==(Object other) => other is CatalogFilter && other._kind == _kind && other._key == _key;

  @override
  int get hashCode => Object.hash(_kind, _key);
}

enum CatalogSort {
  recent('최근 실행순'),
  neglected('오래 방치된 순'),
  name('이름순');

  const CatalogSort(this.label);

  final String label;
}

/// 모든 프로젝트의 기술 스택 태그. 대소문자만 다르면 하나로 치고 처음 나온 표기를 쓴다. 가나다(abc)순.
List<String> stackTags(Iterable<Project> projects) {
  final seen = <String, String>{};
  for (final p in projects) {
    for (final s in p.about.stack) {
      seen.putIfAbsent(s.toLowerCase(), () => s);
    }
  }
  return seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// 검색어·필터에 맞는 카드를 고른 정렬 순서로. 검색은 이름·설명·스택에서, 앞뒤 공백과 대소문자를 무시한다.
/// 실행 기록이 없는 카드는 실행일 정렬에서 늘 맨 뒤. 같으면 이름순.
List<CatalogEntry> visibleEntries(
  List<CatalogEntry> entries, {
  String query = '',
  CatalogFilter filter = CatalogFilter.all,
  CatalogSort sort = CatalogSort.recent,
  required DateTime now,
}) {
  final q = query.trim().toLowerCase();
  bool hit(CatalogEntry e) {
    final about = e.project.about;
    return q.isEmpty || [e.project.name, about.summary ?? '', ...about.stack].any((t) => t.toLowerCase().contains(q));
  }

  final shown = [
    for (final e in entries)
      if (filter.matches(e, now) && hit(e)) e,
  ];
  return shown..sort((a, b) => _compare(a, b, sort));
}

int _byName(CatalogEntry a, CatalogEntry b) => a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());

int _compare(CatalogEntry a, CatalogEntry b, CatalogSort sort) {
  if (sort == CatalogSort.name) return _byName(a, b);
  final (x, y) = (a.run.lastRunAt, b.run.lastRunAt);
  if (x == null || y == null) {
    if (x == y) return _byName(a, b);
    return x == null ? 1 : -1;
  }
  final byTime = sort == CatalogSort.recent ? y.compareTo(x) : x.compareTo(y);
  return byTime != 0 ? byTime : _byName(a, b);
}

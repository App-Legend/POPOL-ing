import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_catalog/src/catalog_view.dart';
import 'package:ppoling_catalog/src/run_info.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/models.dart';

final now = DateTime(2026, 11, 16, 15);

Future<List<CatalogEntry>> samples() async {
  final info = await FakeRunInfoSource.samples(clock: () => now).watchRunInfo().first;
  return [for (final p in SampleProjects.all) CatalogEntry(p, info[p.id] ?? RunInfo.none)];
}

Project project(String id, {List<String> stack = const [], String? summary}) => Project(
      id: id,
      name: id,
      folderPath: '/projects/$id',
      registeredAt: DateTime(2026, 11, 1),
      config: ProjectConfig(about: About(summary: summary, stack: stack)),
    );

CatalogEntry ran(DateTime at) => CatalogEntry(SampleProjects.ppoling, RunInfo(lastRunAt: at, lastSucceeded: true));

List<String> names(List<CatalogEntry> entries) => [for (final e in entries) e.project.name];

Future<CatalogEntry> sample(String id) async => (await samples()).firstWhere((e) => e.project.id == id);

void main() {
  test('실행 중이면 실행 중 n/m', () async {
    final e = await sample('my-team-project');
    expect(cardStateOf(e, now), CardState.running);
    expect(cardStateLabel(e, now), '실행 중 3/3'); // 원격 항목(storage)은 세지 않는다
  });

  test('90일 넘게 실행하지 않으면 오래됨', () async {
    expect(cardStateLabel(await sample('weather-bot'), now), '오래됨 · 8개월');
    expect(cardStateLabel(await sample('shop-clone'), now), '오래됨 · 11개월');
    expect(cardStateOf(ran(now.subtract(const Duration(days: 90))), now), CardState.stopped);
    expect(cardStateOf(ran(now.subtract(const Duration(days: 91))), now), CardState.stale);
    expect(cardStateLabel(ran(now.subtract(const Duration(days: 400))), now), '오래됨 · 1년');
  });

  test('기록이 있으면 중지, 없으면 실행 기록 없음', () async {
    expect(cardStateLabel(await sample('ppoling'), now), '중지');
    expect(cardStateOf(await sample('algo-study'), now), CardState.never);
    expect(cardStateLabel(await sample('algo-study'), now), '실행 기록 없음');
  });

  test('마지막 실행 문구', () {
    expect(lastRunText(RunInfo(lastRunAt: DateTime(2026, 11, 16, 14, 2)), now), '마지막 실행 오늘 14:02');
    expect(lastRunText(RunInfo(lastRunAt: DateTime(2026, 11, 15, 23, 59)), now), '마지막 실행 어제');
    expect(lastRunText(RunInfo(lastRunAt: DateTime(2026, 3, 12, 9)), now), '마지막 실행 2026-03-12');
    expect(lastRunText(RunInfo.none, now), isNull);
  });

  test('태그는 대소문자만 다르면 하나로 친다', () {
    final a = project('a', stack: ['React']);
    final b = project('b', stack: ['react', 'Vite']);
    expect(stackTags([a, b]), ['React', 'Vite']);
    final entries = [CatalogEntry(a, RunInfo.none), CatalogEntry(b, RunInfo.none)];
    expect(names(visibleEntries(entries, filter: CatalogFilter.tag('React'), now: now)), ['a', 'b']);
  });

  test('검색은 이름·설명·스택, 앞뒤 공백과 대소문자 무시', () async {
    final all = await samples();
    expect(names(visibleEntries(all, query: '  SPRING ', now: now)), ['my-team-project']);
    expect(names(visibleEntries(all, query: '디스코드', now: now)), ['weather-bot']);
    expect(names(visibleEntries(all, query: 'shop', now: now)), ['shop-clone']);
  });

  test('필터: 실행 중·오래됨', () async {
    final all = await samples();
    expect(names(visibleEntries(all, filter: CatalogFilter.running, now: now)), ['my-team-project']);
    expect(names(visibleEntries(all, filter: CatalogFilter.stale, now: now)), unorderedEquals(['weather-bot', 'shop-clone']));
  });

  test('필터 칩은 값으로 같은지 본다', () {
    expect(CatalogFilter.tag('react'), CatalogFilter.tag('React'));
    expect(CatalogFilter.tag('React'), isNot(CatalogFilter.all));
    expect(CatalogFilter.running.label, '실행 중');
  });

  test('최근 실행순: 기록 없는 것은 맨 뒤', () async {
    expect(names(visibleEntries(await samples(), sort: CatalogSort.recent, now: now)),
        ['my-team-project', 'ppoling', 'weather-bot', 'shop-clone', 'algo-study']);
  });

  test('오래 방치된 순: 오래된 것부터, 기록 없는 것은 맨 뒤', () async {
    expect(names(visibleEntries(await samples(), sort: CatalogSort.neglected, now: now)),
        ['shop-clone', 'weather-bot', 'ppoling', 'my-team-project', 'algo-study']);
  });

  test('이름순', () async {
    expect(names(visibleEntries(await samples(), sort: CatalogSort.name, now: now)),
        ['algo-study', 'my-team-project', 'ppoling', 'shop-clone', 'weather-bot']);
  });

  test('가짜 실행 정보는 구독하면 지금 것부터 보내고 update 로 다시 보낸다', () async {
    final source = FakeRunInfoSource({'a': const RunInfo(running: 1)});
    final got = <Map<String, RunInfo>>[];
    final sub = source.watchRunInfo().listen(got.add);
    await pumpEventQueue();
    source.update({'b': const RunInfo(running: 2)});
    await pumpEventQueue();
    await sub.cancel();
    expect([for (final m in got) m.keys.toList()], [
      ['a'],
      ['b'],
    ]);
  });
}

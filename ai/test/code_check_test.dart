import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/src/code_check.dart';

const reply = '{"criteria":['
    '{"id":"config","level":"danger","reason":".env 가 .gitignore 에 없어요.","fix":".gitignore 에 .env 를 넣어 주세요.","evidence":[".gitignore:1"]},'
    '{"id":"quality","level":"caution","reason":"한 파일이 900줄이에요.","fix":"기능별로 나눠 주세요."},'
    '{"id":"performance","level":"good","reason":"큰 문제는 안 보여요."},'
    '{"id":"release","level":"caution","reason":"README 에 실행 방법이 없어요.","fix":"실행 방법을 적어 주세요."}'
    ']}';

PreparedCheck sent() => prepareCodeCheck(const [CodeCheckFile('README.md', '# 앱')], const {});

void main() {
  test('비밀값처럼 보이는 줄은 ●●● 로 바꾸고 경로:줄을 남긴다', () {
    final p = prepareCodeCheck(const [CodeCheckFile('src/config.js', 'const a = 1;\nconst API_KEY = "sk-live-abcdefghijklmnop";')], const {});
    expect(p.prompt, isNot(contains('sk-live-abcdefghijklmnop')));
    expect(p.prompt, contains('2: ●●●'));
    expect(p.hiddenAt, ['src/config.js:2']);
  });

  test('보낼 파일은 5개까지', () {
    final p = prepareCodeCheck([for (var i = 0; i < 7; i++) CodeCheckFile('f$i.dart', 'x')], const {});
    expect(p.files, hasLength(5));
  });

  test('앱이 확인 줄도 함께 보낸다', () {
    final p = prepareCodeCheck(const [], const {CheckCriterion.config: ['.gitignore 에 .env 없음']});
    expect(p.prompt, contains('[앱이 확인 · config] .gitignore 에 .env 없음'));
  });

  test('답을 기준 4개로 읽고, 가장 급한 줄과 개수를 낸다(점수 없음)', () {
    final r = parseCodeCheck(reply, projectId: 'p', at: DateTime(2026, 11, 28), model: 'm', sent: sent())!;
    expect([for (final c in r.results) c.criterion], CheckCriterion.values);
    expect(r.mostUrgent, '.env 가 .gitignore 에 없어요.');
    expect(r.countsLabel, '위험 1 · 주의 2 · 좋음 1');
    expect(r.results.first.evidence, ['.gitignore:1']);
    expect(r.toJson().toString(), isNot(contains('score')));
  });

  test('기준이 빠졌거나 JSON 이 아니면 null', () {
    expect(parseCodeCheck('좋아요!', projectId: 'p', at: DateTime(2026), model: 'm', sent: sent()), isNull);
    expect(parseCodeCheck('{"criteria":[{"id":"config","level":"good","reason":"ok"}]}', projectId: 'p', at: DateTime(2026), model: 'm', sent: sent()), isNull);
  });

  test('ai-checks.json 에 프로젝트마다 마지막 하나만 남는다', () async {
    final tmp = Directory.systemTemp.createTempSync('popoling_ai_checks_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/ai-checks.json');
    final store = CodeCheckStore(() async => file);
    final first = parseCodeCheck(reply, projectId: 'p', at: DateTime(2026, 11, 27), model: 'm', sent: sent())!;
    final second = parseCodeCheck(reply, projectId: 'p', at: DateTime(2026, 11, 28), model: 'm', sent: sent())!;
    await store.save(first);
    await store.save(second);
    final again = await CodeCheckStore(() async => file).load();
    expect(again.keys, ['p']);
    expect(again['p']!.at, DateTime(2026, 11, 28));
    expect(again['p']!.countsLabel, '위험 1 · 주의 2 · 좋음 1');
  });
}

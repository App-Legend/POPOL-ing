import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_ai/src/qa_summary.dart';
import 'package:ppoling_core/models.dart';

final nowAt = DateTime(2026, 11, 22, 14, 5, 2);
final prev1At = DateTime(2026, 11, 21, 18, 41);
final prev2At = DateTime(2026, 11, 20, 21, 10);

QaResult r(String name, QaStatus status, DateTime at, {String? target, int? code, int? ms, String? reason}) => QaResult(
      name: name,
      status: status,
      checkedAt: at,
      target: target,
      statusCode: code,
      elapsed: ms == null ? null : Duration(milliseconds: ms),
      failureReason: reason,
    );

QaRun run(DateTime at, List<QaResult> results) => QaRun(projectId: 'p', startedAt: at, trigger: QaTrigger.manual, results: results);

const apiUrl = 'GET http://localhost:8080/actuator/health';
const webUrl = 'GET http://localhost:5173';

QaRun nowRun() => run(nowAt, [
      r('API 헬스', QaStatus.failed, nowAt, target: apiUrl, code: 503, ms: 120),
      r('프론트 메인', QaStatus.passed, nowAt, target: webUrl, code: 200, ms: 84),
      r('관리자 페이지', QaStatus.needsSetup, nowAt),
    ]);

QaRun prev1() => run(prev1At, [
      r('API 헬스', QaStatus.passed, prev1At, target: apiUrl, code: 200, ms: 84),
      r('프론트 메인', QaStatus.passed, prev1At, target: webUrl, code: 200, ms: 80),
    ]);

QaRun prev2() => run(prev2At, [r('API 헬스', QaStatus.passed, prev2At, target: apiUrl, code: 200, ms: 80)]);

QaRun allPassed(DateTime at, {int apiMs = 84}) => run(at, [
      r('API 헬스', QaStatus.passed, at, target: apiUrl, code: 200, ms: apiMs),
      r('프론트 메인', QaStatus.passed, at, target: webUrl, code: 200, ms: 80),
    ]);

RunSummary lastRun() => RunSummary(
      projectId: 'p',
      startedAt: DateTime(2026, 11, 22, 14, 0),
      finishedAt: DateTime(2026, 11, 22, 14, 1),
      items: [
        const ItemResult(item: ItemRef(projectId: 'p', serviceId: 'api'), outcome: ItemOutcome.ok),
        const ItemResult(item: ItemRef(projectId: 'p', serviceId: 'web'), outcome: ItemOutcome.failed, reason: '준비 시간(60초)을 넘겼어요.'),
        const ItemResult(item: ItemRef(projectId: 'p', serviceId: 'db'), outcome: ItemOutcome.skipped),
      ],
    );

void main() {
  group('stripHost', () {
    test('호스트·쿼리·조각을 빼고 경로만 남긴다', () {
      expect(stripHost('GET http://localhost:8080/actuator/health'), 'GET /actuator/health');
      expect(stripHost('GET http://localhost:8080/health?token=abc#x'), 'GET /health');
      expect(stripHost('GET https://api.example.com'), 'GET /');
    });

    test('포트 검사는 포트 번호만 남긴다', () {
      expect(stripHost('localhost:3306'), '포트 3306');
      expect(stripHost('db.internal:5432'), '포트 5432');
    });

    test('모르는 모양의 주소는 원문 대신 주소 생략으로 보낸다', () {
      expect(stripHost('GET localhost:8080/health?sig=abc'), 'GET (주소 생략)', reason: 'http:// 를 빠뜨린 주소');
      expect(stripHost('GET http:/host/x?sig=1'), 'GET (주소 생략)');
      expect(stripHost('GET http://host/a b?sig=1'), '(주소 생략)', reason: '공백이 든 주소');
      expect(stripHost('host/x?sig=1'), '(주소 생략)');
    });

    test('경로만 있는 주소는 쿼리를 빼고 그대로 쓴다', () {
      expect(stripHost('GET /health?sig=abc'), 'GET /health');
    });
  });

  group('prompt', () {
    test('이번 검사 머리와 검사마다 번호', () {
      final p = QaSummaryInput(run: nowRun(), history: [nowRun(), prev1(), prev2()], lastRun: lastRun()).prompt;
      expect(p, contains('[이번 검사] 2026-11-22 14:05 · 통과 1 · 실패 1 · 설정 필요 1'));
      expect(p, contains('#1 API 헬스 · 실패 · GET /actuator/health · 503 · 120ms · 14:05:02'));
      expect(p, contains('#2 프론트 메인 · 통과 · GET / · 200 · 84ms · 14:05:02'));
      expect(p, contains('#3 관리자 페이지 · 설정 필요(검사할 주소 없음)'));
    });

    test('같은 항목의 최근 이력을 붙인다', () {
      final p = QaSummaryInput(run: nowRun(), history: [nowRun(), prev1(), prev2()]).prompt;
      expect(p, contains('#1 API 헬스 · 실패 · GET /actuator/health · 503 · 120ms · 14:05:02\n   최근: 통과 200 84ms (11/21 18:41), 통과 200 80ms (11/20 21:10)'));
    });

    test('실패 이유를 넣는다', () {
      final refused = run(nowAt, [r('프론트 메인', QaStatus.failed, nowAt, target: webUrl, reason: '연결 거부')]);
      expect(QaSummaryInput(run: refused).prompt, contains('#1 프론트 메인 · 실패 · GET / · 연결 거부 · 14:05:02'));
    });

    test('마지막 전체 실행 줄', () {
      final p = QaSummaryInput(run: nowRun(), lastRun: lastRun()).prompt;
      expect(p, contains('[마지막 전체 실행] 11/22 14:00 · api 성공 · web 실패(준비 시간(60초)을 넘겼어요.) · db 건너뜀'));
    });

    test('lastRun 이 없으면 실행 줄을 뺀다', () {
      expect(QaSummaryInput(run: nowRun()).prompt, isNot(contains('[마지막 전체 실행]')));
    });

    test('보낼 글에 호스트·주소·쿼리가 없다', () {
      final withQuery = run(nowAt, [r('API 헬스', QaStatus.failed, nowAt, target: 'GET http://10.0.0.5:8080/health?token=abc', code: 500)]);
      for (final p in [QaSummaryInput(run: nowRun(), history: [prev1()], lastRun: lastRun()).prompt, QaSummaryInput(run: withQuery).prompt]) {
        expect(p, isNot(contains('localhost')));
        expect(p, isNot(contains('http')));
        expect(p, isNot(contains('10.0.0.5')));
        expect(p, isNot(contains('token')));
      }
    });

    test('최근 이력은 같은 이름으로 최대 5회', () {
      final history = [for (var d = 1; d <= 7; d++) allPassed(nowAt.subtract(Duration(days: d)))];
      final p = QaSummaryInput(run: nowRun(), history: history).prompt;
      final recent = p.split('\n').firstWhere((l) => l.startsWith('   최근:'));
      expect(RegExp(r'\(\d+/\d+ \d\d:\d\d\)').allMatches(recent).length, 5);
    });

    test('이번 검사보다 뒤의 이력은 쓰지 않는다', () {
      final later = allPassed(nowAt.add(const Duration(minutes: 1)));
      expect(QaSummaryInput(run: nowRun(), history: [later]).previous, isEmpty);
    });
  });

  group('isSlow', () {
    QaResult at(int ms) => r('API 헬스', QaStatus.passed, nowAt, code: 200, ms: ms);
    QaResult noTime() => r('API 헬스', QaStatus.failed, nowAt, reason: '연결 거부');

    test('이전 평균의 2배 이상이고 200ms 이상 늦으면 느려짐', () {
      expect(isSlow(at(300), [at(100), at(100)]), isTrue);
      expect(isSlow(at(200), [at(100)]), isFalse, reason: '차이가 100ms 뿐');
    });

    test('2배가 안 되면 느려짐이 아니다', () {
      expect(isSlow(at(399), [at(200)]), isFalse);
    });

    test('평균이 작아 차이가 200ms 안 되면 느려짐이 아니다', () {
      expect(isSlow(at(60), [at(20)]), isFalse);
    });

    test('이전 응답 시간이 없으면 판단하지 않는다', () {
      expect(isSlow(at(5000), []), isFalse);
      expect(isSlow(at(5000), [noTime()]), isFalse);
      expect(isSlow(noTime(), [at(100)]), isFalse);
    });
  });

  group('needsAi', () {
    test('모두 통과하고 직전도 통과면 부르지 않는다', () {
      expect(QaSummaryInput(run: allPassed(nowAt), history: [prev1()]).needsAi, isFalse);
    });

    test('직전 검사가 없고 모두 통과면 부르지 않는다', () {
      expect(QaSummaryInput(run: allPassed(nowAt)).needsAi, isFalse);
    });

    test('직전에 같은 항목이 실패였으면 부른다', () {
      final failedBefore = run(prev1At, [r('API 헬스', QaStatus.failed, prev1At, target: apiUrl, code: 503)]);
      expect(QaSummaryInput(run: allPassed(nowAt), history: [failedBefore]).needsAi, isTrue);
    });

    test('실패가 있으면 부른다', () {
      expect(QaSummaryInput(run: nowRun()).needsAi, isTrue);
    });

    test('설정 필요가 있으면 부른다', () {
      final withSetup = run(nowAt, [r('API 헬스', QaStatus.passed, nowAt, code: 200, ms: 84), r('관리자 페이지', QaStatus.needsSetup, nowAt)]);
      expect(QaSummaryInput(run: withSetup).needsAi, isTrue);
    });

    test('느려진 항목이 있으면 부른다', () {
      expect(QaSummaryInput(run: allPassed(nowAt, apiMs: 900), history: [prev1()]).needsAi, isTrue);
    });
  });

  group('parseQaSummary', () {
    test('울타리를 벗기고 번호로 실제 검사 결과를 붙인다', () {
      final s = parseQaSummary('```json\n{"sentences":[{"text":"API 헬스가 실패했어요.","checks":[1]}]}\n```', nowRun())!;
      expect(s.single.text, 'API 헬스가 실패했어요.');
      expect(s.single.evidence.single.name, 'API 헬스');
    });

    test('근거가 여러 개면 모두 붙인다', () {
      final s = parseQaSummary('{"sentences":[{"text":"둘 다 봤어요.","checks":[1,2]}]}', nowRun())!;
      expect([for (final e in s.single.evidence) e.name], ['API 헬스', '프론트 메인']);
    });

    test('범위 밖 번호·문자열 번호·빈 checks 문장은 뺀다', () {
      final s = parseQaSummary(
        '{"sentences":[{"text":"a","checks":[0]},{"text":"b","checks":[9]},{"text":"c","checks":["1"]},{"text":"d","checks":[]},{"text":"e","checks":[2]}]}',
        nowRun(),
      )!;
      expect([for (final x in s) x.text], ['e']);
    });

    test('남는 문장이 없거나 JSON 이 아니면 null', () {
      expect(parseQaSummary('요약할게요: 다 괜찮아요', nowRun()), isNull);
      expect(parseQaSummary('{"sentences":[{"text":"a","checks":[7]}]}', nowRun()), isNull);
      expect(parseQaSummary('{"sentences":"x"}', nowRun()), isNull);
      expect(parseQaSummary('{"sentences":[{"text":"","checks":[1]}]}', nowRun()), isNull, reason: '빈 문장');
    });
  });

  group('evidenceLabel', () {
    final at1402 = DateTime(2026, 11, 22, 14, 2);

    test('판정 다음에 응답 코드', () {
      expect(evidenceLabel(r('API 헬스', QaStatus.failed, at1402, target: apiUrl, code: 503, ms: 120)), 'API 헬스 · 실패 · 503 · 14:02');
    });

    test('코드가 없으면 실패 이유', () {
      expect(evidenceLabel(r('프론트 메인', QaStatus.failed, nowAt, target: webUrl, reason: '연결 거부')), '프론트 메인 · 실패 · 연결 거부 · 14:05');
    });

    test('코드·이유가 없으면 응답 시간', () {
      expect(evidenceLabel(r('DB 포트', QaStatus.passed, nowAt, target: 'localhost:3306', ms: 84)), 'DB 포트 · 통과 · 84ms · 14:05');
    });

    test('값이 없으면 판정과 시각만', () {
      expect(evidenceLabel(r('관리자 페이지', QaStatus.needsSetup, nowAt)), '관리자 페이지 · 설정 필요 · 14:05');
    });
  });

  group('flags', () {
    test('실패·설정 필요를 검사 순서대로', () {
      final flags = QaSummaryInput(run: nowRun()).flags;
      expect([for (final f in flags) '${f.label} · ${f.result.name}'], ['실패 · API 헬스', '설정 필요 · 관리자 페이지']);
    });

    test('통과했지만 느려진 항목은 느려짐', () {
      final flags = QaSummaryInput(run: allPassed(nowAt, apiMs: 900), history: [prev1()]).flags;
      expect([for (final f in flags) '${f.label} · ${f.result.name}'], ['느려짐 · API 헬스']);
      expect(flags.single.kind, QaFlagKind.slow);
    });
  });
}

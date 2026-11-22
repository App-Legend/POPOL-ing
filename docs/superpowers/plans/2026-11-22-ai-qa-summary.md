# AI-03 QA 결과 요약 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** QA 검사 결과를 Gemini로 2~3문장 요약하고 문장마다 실제 검사 값으로 근거를 붙이는 패널을 `ai/`에 만들고, 화면 8(`/ai`)에 카드로 붙인다.

**Architecture:** 화면 없는 로직(`qa_summary.dart`: 보낼 글·안 부르는 조건·느려짐·답 읽기·근거 라벨)과 위젯(`qa_summary_panel.dart`)을 나눈다. 보내기는 기존 `AiSender` 한 길로만 한다. 화면 8은 `/ai` 인자로 받은 프로젝트 ID의 최근 검사로 패널을 그린다.

**Tech Stack:** Flutter/Dart, `ppoling_core`(contracts·fakes·ui), `flutter_test`. 새 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-11-22-ai-qa-summary-design.md`

## Global Constraints

- `ai/` 안에서만 고친다. `core/`·다른 기능 폴더·`app/`은 고치지 않는다. 다른 기능 패키지를 import하지 않는다(`core/`만).
- 새 패키지 추가 금지(날짜 포맷은 손으로: `padLeft(2, '0')`).
- Gemini 호출은 `AiSender.send(...)` → `LlmClient.complete` 한 길로만. [보내기] 전 요청 0건.
- 보낼 글에 호스트·쿼리 문자열·API 키가 없다. 주소는 `GET /path` 꼴, 포트 검사는 `포트 3306`.
- 상태는 색만으로 나누지 않고 글 라벨을 함께(`StatusChip(label, tone)`).
- 화면 문구(그대로 쓴다):
  - 설명: `검사 결과를 AI가 두세 문장으로 정리해요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.`
  - 버튼: `AI 요약` · `다시 요약` · `취소` · `헬스체크`
  - 고정 문구: `모든 검사를 통과했어요.`
  - 분석 중: `분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.`
  - 취소함: `분석을 멈췄어요.`
  - 완료 라벨: `요약 완료 · {modelName}`
  - 완료 뒤 안내: `요약은 판정을 바꾸지 않아요. 통과·실패는 헬스체크 규칙 그대로예요. AI 결과는 틀릴 수 있으니 근거를 확인해 주세요.`
  - 근거: `근거  {이름} · {값} · {HH:mm}` (근거 뒤 공백 두 칸)
  - 못 읽음: `AI 답을 읽지 못했어요.`
  - 검사 없음: `검사할 항목이 없어요.`
  - 화면 8 카드 제목 `헬스체크 결과 요약`, 머리 `{오늘 HH:mm | M/d HH:mm} 검사 기준`, 빈 상태 `아직 헬스체크 결과가 없어요.`
  - 확인 창 notes: `주소는 호스트를 빼고 경로만 보내요. 응답 본문은 보내지 않아요.`, requestName `헬스체크 결과 요약`
- 커밋에 Co-Authored-By 같은 공동작성 문구를 넣지 않는다.

## Review Focus

1. 주소에 쿼리 문자열(`?token=abc`)이 붙은 check → 보낼 글에서 쿼리까지 빠진다. (Task 1 테스트)
2. AI 답이 범위 밖 번호(`0`, `9`)·문자열 번호·빈 `checks`를 섞어 보냄 → 그 문장만 빠지고, 모두 빠지면 "못 읽음". (Task 2 테스트)
3. checks가 하나도 없는 프로젝트의 검사 → "검사할 항목이 없어요.", 요청 0건, [AI 요약] 없음. (Task 3 테스트)
4. 프로젝트가 목록에서 지워져 `lastRun`이 `ProjectNotFoundException` → 실행 요약 줄만 빠지고 패널은 그대로. (Task 3 테스트)
5. 답을 기다리는 중에 화면을 떠남(위젯 dispose) → 늦게 온 답에 setState 오류 없음. (Task 3 테스트)

---

### Task 1: 보낼 글과 안 부르는 조건 (`qa_summary.dart`)

**Files:**
- Create: `ai/lib/src/qa_summary.dart`
- Test: `ai/test/qa_summary_test.dart`

**Interfaces:**
- Produces:
  - `String stripHost(String target)` — `GET http://h:8080/a/b?x=1#f` → `GET /a/b`; `GET https://h` → `GET /`; `localhost:3306` → `포트 3306`.
  - `String qaStatusLabel(QaStatus s)` — `통과` / `실패` / `설정 필요`.
  - `enum QaFlagKind { failed, slow, needsSetup }`, `class QaFlag { final QaFlagKind kind; final QaResult result; String get label; }` — label `실패` / `느려짐` / `설정 필요`.
  - `class QaSummaryInput { QaSummaryInput({required QaRun run, List<QaRun> history = const [], RunSummary? lastRun}); final QaRun run; final List<QaRun> previous; final RunSummary? lastRun; List<QaFlag> get flags; bool get needsAi; String get prompt; }`
    - `previous` = `history` 중 `startedAt`이 `run.startedAt`보다 앞선 것(최근 것이 앞).
    - 항목별 최근 이력 = `previous`에서 같은 `name`의 결과를 앞에서 최대 5개.
  - `bool isSlow(QaResult now, List<QaResult> recent)` — `now.elapsed`와 `recent` 중 elapsed 있는 것의 평균 avg: `now >= 2*avg && now - avg >= 200ms`. elapsed 있는 이전 기록이 없으면 false.
  - `const String qaSummarySystem` — 한국어·쉬운 말·2~3문장·판정을 바꾸거나 값을 지어내지 말 것·JSON 하나만 `{"sentences":[{"text":"...","checks":[1]}]}`(checks는 근거가 된 검사 번호).

- [ ] **Step 1: 실패하는 테스트 작성** (`clock` 고정 `DateTime(2026, 11, 22, 14, 5, 2)`, 이전 검사는 11/21 18:41, 11/20 21:10)

```dart
test('stripHost: 호스트·쿼리·조각을 빼고 경로만 남긴다', () {
  expect(stripHost('GET http://localhost:8080/actuator/health'), 'GET /actuator/health');
  expect(stripHost('GET http://localhost:8080/health?token=abc#x'), 'GET /health');
  expect(stripHost('GET https://api.example.com'), 'GET /');
  expect(stripHost('localhost:3306'), '포트 3306');
  expect(stripHost('db.internal:5432'), '포트 5432');
});
test('prompt: 검사마다 번호, 최근 이력, 마지막 전체 실행 줄', () {
  final p = QaSummaryInput(run: now /*API 헬스 실패 503 120ms, 프론트 메인 통과 200 84ms, 관리자 페이지 설정 필요*/, history: [now, prev1, prev2], lastRun: summary /*api ok, web failed '준비 시간(60초)을 넘겼어요.', db skipped*/).prompt;
  expect(p, contains('[이번 검사] 2026-11-22 14:05 · 통과 1 · 실패 1 · 설정 필요 1'));
  expect(p, contains('#1 API 헬스 · 실패 · GET /actuator/health · 503 · 120ms · 14:05:02'));
  expect(p, contains('   최근: 통과 200 84ms (11/21 18:41), 통과 200 80ms (11/20 21:10)'));
  expect(p, contains('#3 관리자 페이지 · 설정 필요(검사할 주소 없음)'));
  expect(p, contains('[마지막 전체 실행] '));
  expect(p, contains('web 실패(준비 시간(60초)을 넘겼어요.)'));
  expect(p, contains('db 건너뜀'));
  expect(p, isNot(contains('localhost')));
  expect(p, isNot(contains('http')));
});
test('prompt: lastRun 이 없으면 실행 줄을 뺀다', ...);           // expect(p, isNot(contains('[마지막 전체 실행]')))
test('최근 이력은 같은 이름으로 최대 5회', ...);                    // 이전 7회 → '최근:' 줄에 항목 5개
test('isSlow: 2배이면서 200ms 이상일 때만', () {
  // avg 100ms: 300ms → true, 199ms → false(2배 아님), avg 20ms: 60ms → false(차이 40ms), 이전 elapsed 없음 → false
});
test('needsAi: 모두 통과 + 직전도 통과 + 느려짐 없음이면 false', ...);
test('needsAi: 직전 검사가 없고 모두 통과면 false', ...);
test('needsAi: 직전에 같은 항목이 실패였으면 true', ...);
test('needsAi: 설정 필요가 있으면 true', ...);
test('needsAi: 느려진 항목이 있으면 true', ...);
test('flags: 실패·느려짐·설정 필요를 검사 순서대로', () {
  expect(input.flags.map((f) => '${f.label} · ${f.result.name}'), ['실패 · API 헬스', '설정 필요 · 관리자 페이지']);
});
```

- [ ] **Step 2: 실패 확인** — Run: `cd ai && flutter test test/qa_summary_test.dart` → Expected: FAIL (`qa_summary.dart` 없음)
- [ ] **Step 3: `ai/lib/src/qa_summary.dart`에 위 Interfaces 구현** — 주소 파싱은 `Uri.tryParse`; 시각은 `padLeft(2, '0')`로 손 포맷. 실행 줄 결과 라벨: `ok`→`성공`, `failed`→`실패`, `skipped`→`건너뜀`, reason 있으면 `(reason)`.
- [ ] **Step 4: 통과 확인** — Run: `cd ai && flutter test test/qa_summary_test.dart` → Expected: All tests passed

### Task 2: 답 읽기와 근거 라벨 (`qa_summary.dart`에 추가)

**Files:**
- Modify: `ai/lib/src/qa_summary.dart`
- Test: `ai/test/qa_summary_test.dart`

**Interfaces:**
- Consumes: Task 1의 `qaStatusLabel`.
- Produces:
  - `class QaSummarySentence { final String text; final List<QaResult> evidence; }`
  - `List<QaSummarySentence>? parseQaSummary(String reply, QaRun run)` — 못 읽으면 null.
  - `String evidenceLabel(QaResult r)` — `{name} · {값} · {HH:mm}`, 값 = statusCode → failureReason → `{ms}ms` → `qaStatusLabel`.

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
test('울타리를 벗기고 번호로 실제 검사 결과를 붙인다', () {
  final s = parseQaSummary('```json\n{"sentences":[{"text":"API 헬스가 실패했어요.","checks":[1]}]}\n```', now)!;
  expect(s.single.text, 'API 헬스가 실패했어요.');
  expect(s.single.evidence.single.name, 'API 헬스');
});
test('범위 밖 번호·문자열 번호·빈 checks 문장은 뺀다', () {
  final s = parseQaSummary('{"sentences":[{"text":"a","checks":[0]},{"text":"b","checks":[9]},{"text":"c","checks":["1"]},{"text":"d","checks":[]},{"text":"e","checks":[2]}]}', now)!;
  expect(s.map((x) => x.text), ['e']);
});
test('남는 문장이 없거나 JSON 이 아니면 null', () {
  expect(parseQaSummary('요약할게요: 다 괜찮아요', now), isNull);
  expect(parseQaSummary('{"sentences":[{"text":"a","checks":[7]}]}', now), isNull);
  expect(parseQaSummary('{"sentences":"x"}', now), isNull);
});
test('evidenceLabel: 응답 코드 → 실패 이유 → 시간 → 상태 순', () {
  expect(evidenceLabel(apiHealth503at1402), 'API 헬스 · 503 · 14:02');
  expect(evidenceLabel(refusedAt1405 /*statusCode null, failureReason 연결 거부*/), '프론트 메인 · 연결 거부 · 14:05');
  expect(evidenceLabel(portPassed /*84ms*/), 'DB 포트 · 84ms · 14:05');
  expect(evidenceLabel(needsSetup), '관리자 페이지 · 설정 필요 · 14:05');
});
```

- [ ] **Step 2: 실패 확인** — Run: `cd ai && flutter test test/qa_summary_test.dart` → Expected: FAIL (`parseQaSummary` 없음)
- [ ] **Step 3: 구현** — 첫 `{`~마지막 `}`를 `jsonDecode`, `FormatException`·타입 불일치면 null. 번호는 `int`만, 1부터 `run.results.length`까지.
- [ ] **Step 4: 통과 확인** — Run: `cd ai && flutter test test/qa_summary_test.dart` → Expected: All tests passed
- [ ] **Step 5: 커밋**

```bash
git add ai/lib/src/qa_summary.dart ai/test/qa_summary_test.dart
git commit -m "feat(ai): AI-03 QA 요약에 보낼 글·안 부르는 조건·답 읽기"
```

### Task 3: 요약 패널 위젯 (`qa_summary_panel.dart`)

**Files:**
- Create: `ai/lib/src/qa_summary_panel.dart`
- Modify: `ai/lib/src/ai_sender.dart` (`send`에 `VoidCallback? onConfirmed` 추가: [보내기]를 누른 직후·`complete` 전에 부른다)
- Test: `ai/test/qa_summary_panel_test.dart`, `ai/test/dialogs_test.dart`(onConfirmed 한 건)

**Interfaces:**
- Consumes: Task 1·2 전부, `AiSender`, `llmErrorText`, `showApiKeyDialog`, `ApiKeyCheck`.
- Produces: `class QaSummaryPanel extends StatefulWidget { const QaSummaryPanel({super.key, required QaRun run, required LlmClient client, required ApiKeyStore keys, required QaRunner qa, required Orchestrator orchestrator, ApiKeyCheck? checkKey}); }`

동작:
- 처음에 `qa.history(run.projectId)`와 `orchestrator.lastRun(run.projectId)`(예외면 null)를 읽어 `QaSummaryInput`을 만든다. 읽는 동안은 아무 버튼도 없다.
- 보이는 순서: 검사 없음 → `!needsAi`면 고정 문구 → `!client.isConfigured()`면 `llmErrorText(missingKey)` + [키 입력] → 처음 상태.
- [AI 요약]/[다시 요약]/[다시 시도] → `AiSender(client, keys: keys).send(context, requestName: '헬스체크 결과 요약', content: input.prompt, system: qaSummarySystem, notes: [...], onConfirmed: 분석 중으로)`. null(취소)이면 이전 상태로.
- [취소] → 시도 번호를 올리고 `분석을 멈췄어요.` + [AI 요약]. 늦게 온 답·오류는 버린다. 모든 setState 앞에 `mounted`.
- `LlmException` → `llmErrorText(failure)`의 제목·안내·버튼. 버튼 `키 입력`/`키 바꾸기`는 `showApiKeyDialog(context, keys, check: checkKey)` 뒤 다시 확인, `다시 시도`는 다시 보낸다.
- 완료 → 문장마다 `text` 아래 `근거  ` + `evidenceLabel` (evidence 여러 개면 ` / `로 잇는다), `flags`를 `StatusChip('${f.label} · ${f.result.name}', tone)`(failed `C.bad`, slow `C.warn`, needsSetup `C.idle`), `요약 완료 · ${client.modelName}`, 완료 뒤 안내, [다시 요약].

- [ ] **Step 1: 실패하는 테스트 작성** (가짜: `FakeQaRunner`(clock 주입, `failing: {'API 헬스'}`), `FakeLlmClient`, `FakeOrchestrator`, `MemoryApiKeyStore('AQ.test-key-abcdefghijklmnop')`, 기다림용 `_HeldLlmClient`(Completer로 답을 붙잡음))

```dart
testWidgets('AT-21: [보내기] 전·취소하면 요청 0건, 보낸 내용에 호스트·키 없음', ...);
  // [AI 요약] 탭 → 확인 창 → ai.sent 비어 있음 → [취소] → 여전히 0건
  // 다시 [AI 요약] → [보내기] → ai.sent.single 에 'localhost'·'http'·키 없음
testWidgets('AT-20: 모두 통과·직전도 통과면 확인 창 없이 고정 문구, 요청 0건', ...);
  // find.text('모든 검사를 통과했어요.') findsOneWidget, btn('AI 요약') findsNothing
testWidgets('AT-20: 실패 판정은 요약 뒤에도 실패 라벨 그대로, 근거는 실제 값', ...);
  // reply {"sentences":[{"text":"API 헬스가 괜찮아요.","checks":[1]}]} → '근거  API 헬스 · 연결 거부 · 14:05', StatusChip '실패 · API 헬스' 그대로, '요약 완료 · fake-model'
testWidgets('AT-19: 키가 없으면 API 키 필요와 [키 입력]', ...);
testWidgets('오류 4종은 llmErrorText 제목과 버튼', ...);   // invalidKey→'키 바꾸기', quotaExceeded·network→'다시 시도'
testWidgets('답을 못 읽으면 AI 답을 읽지 못했어요와 [다시 요약]', ...);
testWidgets('분석 중 [취소] → 분석을 멈췄어요, 늦은 답은 무시', ...);  // _HeldLlmClient 로 붙잡고 취소 후 complete → 요약 문장 안 나옴
testWidgets('검사할 항목이 없으면 안내만, 요청 0건', ...);                  // Review Focus 3
testWidgets('lastRun 이 ProjectNotFoundException 이어도 패널은 그대로', ...); // Review Focus 4
testWidgets('답을 기다리다 화면을 떠나도 오류 없음', ...);                    // Review Focus 5: pumpWidget(SizedBox()) 후 complete → tester.takeException() isNull
```

- [ ] **Step 2: 실패 확인** — Run: `cd ai && flutter test test/qa_summary_panel_test.dart` → Expected: FAIL (`QaSummaryPanel` 없음)
- [ ] **Step 3: `AiSender.send`에 `onConfirmed` 추가, `QaSummaryPanel` 구현**
- [ ] **Step 4: 통과 확인** — Run: `cd ai && flutter test` → Expected: All tests passed (기존 dialogs_test 포함)

### Task 4: 화면 8 카드와 등록 (`ai_screen.dart`, `ai.dart`)

**Files:**
- Modify: `ai/lib/src/ai_screen.dart`, `ai/lib/ai.dart`
- Test: `ai/test/ai_screen_test.dart`, `ai/test/ai_register_test.dart`

**Interfaces:**
- Consumes: Task 3의 `QaSummaryPanel`.
- Produces: `AiScreen({..., String? projectId, QaRunner? qa, Orchestrator? orchestrator})`. `ai.dart`는 `QaSummaryPanel`을 export하고, `/ai` 빌더에서 `ModalRoute.of(ctx)?.settings.arguments`가 `String`이면 projectId로, `qa: app.read<QaRunner>()`, `orchestrator: app.read<Orchestrator>()`를 넘긴다.

동작:
- projectId·qa·orchestrator가 모두 있으면 `Panel(title: '헬스체크 결과 요약', titleAction: Text('{기준} 검사 기준'))` 안에 `qa.history(projectId)`의 첫 검사로 `QaSummaryPanel`. 기준: 오늘이면 `오늘 HH:mm`, 아니면 `M/d HH:mm`.
- 이력이 비면 `아직 헬스체크 결과가 없어요.` + [헬스체크] → `qa.runChecks(projectId)` 뒤 다시 읽는다. 실패하면 SnackBar `헬스체크를 하지 못했어요.`
- 아래 준비 중 문구: projectId가 있으면 `실행 실패 원인 분석은 준비 중이에요.`, 없으면 지금 문구 그대로(카드 없음).

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
testWidgets('프로젝트 ID 없이 열면 카드 없이 지금 안내 그대로', ...);  // find.text('헬스체크 결과 요약') findsNothing
testWidgets('검사 이력이 없으면 빈 안내와 [헬스체크], 누르면 카드에 요약 패널', ...);
testWidgets('최근 검사가 있으면 오늘 HH:mm 검사 기준과 패널', ...);
// ai_register_test: '/ai' 경로에 arguments 'my-team-project' 로 열면 '헬스체크 결과 요약' 카드가 보인다(등록에 FakeQaRunner·FakeOrchestrator 를 먼저 provide)
```

- [ ] **Step 2: 실패 확인** — Run: `cd ai && flutter test test/ai_screen_test.dart test/ai_register_test.dart` → Expected: FAIL
- [ ] **Step 3: 구현**
- [ ] **Step 4: 전체 확인** — Run: `cd ai && flutter analyze && flutter test` → Expected: No issues found / All tests passed. 이어서 `cd ../app && flutter analyze && flutter test` → Expected: 통과(앱 조립이 깨지지 않음)
- [ ] **Step 5: 커밋**

```bash
git add ai/ docs/superpowers/specs/2026-11-22-ai-qa-summary-design.md timeline/수연.md
git commit -m "feat(ai): AI-03 QA 결과 요약 패널과 화면 8 카드 (AT-20·21)"
```

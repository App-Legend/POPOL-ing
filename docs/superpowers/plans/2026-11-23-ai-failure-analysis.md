# AI-02 실행 실패 원인 분석 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 마지막 전체 실행에서 실패한 항목마다 [원인 분석]을 두고, 실패 이유·실행 설정·로그 끝부분·환경 차이를 Gemini에 보내 원인 후보와 해결 방법을 실제 근거와 함께 보여준다. 화면 8(`/ai`)에 카드로 붙인다.

**Architecture:** 화면 없는 로직(`failure_analysis.dart`: 보낼 글 모으기·만들기, AI 지시, 답 읽기)과 패널(`failure_analysis_panel.dart`)을 나눈다. AI-03 패널에 있던 보내기 과정(키 확인·확인 창·분석 중/취소·오류)을 `ai_request.dart`의 `AiRequestView<T>`로 옮겨 두 패널이 같이 쓴다. `EnvDiff`·`LogExcerpt`·`ProjectRepository`는 없을 수 있는 것으로 받는다.

**Tech Stack:** Flutter/Dart, `popoling_core`(contracts·fakes·ui), `flutter_test`. 새 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-11-23-ai-failure-analysis-design.md`

## Global Constraints

- `ai/` 안에서만 코드를 고친다. `core/`·`app/`·다른 기능 폴더는 고치지 않고 import도 `core/`만. 문서는 이 계획·설계와 기획서 §2 AI-02 줄만 고친다.
- 새 패키지 추가 금지.
- Gemini 호출은 `AiSender.send(...)` 한 길로만. [보내기] 전 요청 0건.
- 보낼 글에 환경변수(`env`)의 이름·값, `.env` 내용, API 키, 호스트(`localhost`, `storage.my-team.dev` 등)가 없다.
- 상태·후보는 색만으로 나누지 않고 글 라벨을 함께(`StatusChip(label, tone)`).
- AI-03 동작은 바뀌지 않는다. `ai/test/qa_summary_panel_test.dart`·`ai/test/qa_summary_test.dart`는 고치지 않는다.
- 화면 문구(그대로 쓴다):
  - 카드 제목 `실행 실패 원인 분석`, 머리 `{오늘 HH:mm | M/d HH:mm} 전체 실행 기준`
  - 카드 설명 `실패한 항목의 로그와 마지막 성공 때와 달라진 환경을 AI가 읽고 원인 후보와 해결 방법을 찾아 줘요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.`
  - 빈 상태 `실패한 실행이 없어요. 실행이 실패하면 여기서 원인을 찾아 드려요.`
  - 행 `{id} · 실패 · {실패 이유}` / `{id} · 건너뜀 · {이유}`(이유 없으면 `{id} · 건너뜀`)
  - 버튼 `원인 분석` · `다시 분석`
  - 후보 라벨 `원인 후보 · 가능성 높음` / `원인 후보 · 가능성 있음`
  - 근거 `근거 로그 · {id} 마지막 실행`, `환경 차이 · {이름} {전} → {후}`, `실패 이유 · {실패 이유}`, `해결 방법` + `1. …`
  - 완료 라벨 `분석 완료 · {modelName}`
  - 주의 `AI 결과는 틀릴 수 있어요. 근거(로그 줄, 검사 항목)를 확인한 뒤 판단해 주세요.`
  - 확인 창 requestName `실행 실패 원인 분석`, notes `실행 설정은 명령·폴더·포트·준비 조건만 보내요. 환경변수와 .env 파일 내용은 보내지 않아요.`
  - 프로젝트 없이 연 화면 8 `프로젝트 대시보드에서 [AI 검사]를 누르면 그 프로젝트의 실행 실패 원인 분석과 헬스체크 결과 요약을 볼 수 있어요.`
- 커밋에 Co-Authored-By 같은 공동작성 문구를 넣지 않는다. 커밋할 때 타임라인 훅이 묻는다.

## Review Focus

1. A가 못 가린 비밀값이 로그에 남음(`DB_PASSWORD=hunter2`) → 보낸 글에 `hunter2`가 없고 확인 창에 "비밀값으로 보이는 1곳을 가렸어요". (Task 4 테스트)
2. 실행 뒤 설정에서 그 항목이 지워짐 → `설정에서 이 항목을 찾지 못했어요.`로 보내고 패널은 그대로. (Task 1 테스트)
3. 프로젝트가 목록에서 지워져 `getProject`·`tail`·`sinceLastSuccess`가 `ProjectNotFoundException` → `collect`가 던지지 않고 각 칸을 "못 읽음"으로 채운다. (Task 1 테스트)
4. 공백이 든 명령 인자(`C:\Program Files\nodejs\node.exe`) → 따옴표로 묶여 한 인자로 읽힌다. (Task 1 테스트)
5. 로그가 바뀐 뒤 [다시 분석] → 새 로그로 다시 보낸다(처음 모은 글을 재사용하지 않는다). (Task 4 테스트)

---

### Task 1: 보낼 글 모으기·만들기 (`failure_analysis.dart`)

**Files:**
- Create: `ai/lib/src/failure_analysis.dart`
- Test: `ai/test/failure_analysis_test.dart`

**Interfaces:**
- Consumes: `stripHost(String)` (`qa_summary.dart`). `core` 모델 `ItemResult`, `RunSummary`, `ServiceConfig`(`ProcessService`·`ComposeService`·`RemoteService`), `ReadyCondition`(`HttpReady`·`PortReady`·`LogReady`·`ComposeHealthyReady`·`NoneReady`), `EnvChange`.
- Produces:
  - `const failureLogLines = 50;` `const logLineMax = 300;`
  - `String failureReasonText(ItemResult r)` — `reason`에 `exitCode`가 있고 reason에 "종료 코드"가 없으면 `'{reason} · 종료 코드 {n}'`. reason만 있으면 reason. exitCode만 있으면 `'종료 코드 {n}'`. 둘 다 없으면 `'이유를 알 수 없어요.'`
  - `String envChangeLabel(EnvChange c)` — `'{name} {before ?? '없음'} → {after ?? '없음'}'`
  - `class FailureAnalysisInput { FailureAnalysisInput({required ItemResult item, required RunSummary run, ServiceConfig? service, bool envAvailable = true, List<EnvChange>? envChanges, List<String>? logs}); final ItemResult item; final RunSummary run; final ServiceConfig? service; final bool envAvailable; final List<EnvChange>? envChanges; final List<String>? logs; String get prompt; static Future<FailureAnalysisInput> collect({required ItemResult item, required RunSummary run, required ProjectRepository projects, LogExcerpt? logs, EnvDiff? envDiff}); }`
    - `logs` 필드는 생성자에서 줄마다 `logLineMax`자를 넘으면 앞 300자 + `…`로 자른 목록. 근거 칸도 이 줄을 쓴다.
    - `collect`는 절대 던지지 않는다. `getProject` 실패 → `service: null`. `logs`가 null이거나 `tail(..., lines: failureLogLines)`가 던지면 `logs: null`. `envDiff`가 null이거나 던지면 `envAvailable: false`.

- [ ] **Step 1: Write the failing tests** (`failure_analysis_test.dart`)

공통 데이터: `ref(id) => ItemRef(projectId: 'my-team-project', serviceId: id)`, 샘플 서비스는 `(await FakeProjectRepository.withSamples().getProject('my-team-project')).config!.services`에서 id로.

```dart
final api = ItemResult(item: ref('api'), outcome: ItemOutcome.failed, reason: '시작하자마자 종료됐어요 (종료 코드 1).', exitCode: 1);
final run = RunSummary(projectId: 'my-team-project', startedAt: DateTime(2026, 11, 22, 14), finishedAt: DateTime(2026, 11, 22, 14, 0, 30), items: [
  ItemResult(item: ref('db'), outcome: ItemOutcome.ok),
  ItemResult(item: ref('storage'), outcome: ItemOutcome.ok),
  api,
  ItemResult(item: ref('web'), outcome: ItemOutcome.skipped, reason: 'api 가 실패해서 시작하지 않았어요.'),
]);
```

- `'보낼 글: 실패 이유·실행 설정·다른 항목·환경 차이·로그에 번호'` — `FailureAnalysisInput(item: api, run: run, service: apiService, envChanges: [EnvChange(name: 'node', before: '20.11.0', after: '22.3.0')], logs: ['Starting backend', 'Error: The module was compiled against a different Node.js version']).prompt` 이 정확히:
  ```
  [실패한 항목] api · 내 컴퓨터에서 실행 · 11/22 14:00 전체 실행
  #R 시작하자마자 종료됐어요 (종료 코드 1).
  [실행 설정] 명령 ./gradlew bootRun · 폴더 ./backend · 포트 8080 · .env 파일 씀(내용은 보내지 않음)
    준비 조건 HTTP /actuator/health 응답(120초 안) · 먼저 떠야 하는 항목 db
  [같은 실행의 다른 항목] db 성공 · storage 성공 · web 건너뜀(api 가 실패해서 시작하지 않았어요.)
  [환경 차이] 마지막 성공 실행과 비교
  #E1 node 20.11.0 → 22.3.0
  [로그] api 마지막 2줄
  #L1 Starting backend
  #L2 Error: The module was compiled against a different Node.js version
  ```
  그리고 `SPRING_PROFILES_ACTIVE`·`localhost`가 들어 있지 않다.
- `'compose 항목'` — db 서비스: 설정 줄이 `[실행 설정] compose 파일 ./docker-compose.yml · 서비스 mysql` 과 `  준비 조건 compose healthy(90초 안)`.
- `'원격 항목은 호스트를 빼고 준비 조건만'` — storage: `[실행 설정] 원격 항목(켜고 끄지 않고 연결만 확인)`, `  준비 조건 HTTP /health 응답(10초 안)`, `storage.my-team.dev` 없음.
- `'공백이 든 인자는 따옴표, 포트 준비 조건은 호스트를 빼고, 준비 조건 없음'` — `ProcessService(id: 'bot', command: [r'C:\Program Files\nodejs\node.exe', 'index.js'], ready: PortReady(port: 5432, host: 'db.internal'))` → `명령 "C:\Program Files\nodejs\node.exe" index.js`, `준비 조건 포트 5432 연결(60초 안)`, `db.internal` 없음. `ProcessService(id: 'x', command: ['a'])`(NoneReady) → `  준비 조건 없음`. `LogReady(pattern: 'Started .* in')` → `준비 조건 로그에 "Started .* in" 출력(60초 안)`.
- `'설정에서 못 찾은 항목'` — `service: null` → 첫 줄 `[실패한 항목] api · 11/22 14:00 전체 실행`, 설정 줄 `[실행 설정] 설정에서 이 항목을 찾지 못했어요.`
- `'환경 차이 네 경우'` — `envAvailable: false` → `[환경 차이] 환경 비교를 아직 쓸 수 없어요.`; `envChanges: null` → `[환경 차이] 마지막 성공 실행 기록이 없어요.`; `[]` → `[환경 차이] 마지막 성공 실행과 달라진 것이 없어요.`; `EnvChange(name: 'docker', after: '24.0.7')` → `#E1 docker 없음 → 24.0.7`.
- `'로그 못 읽음·없음·긴 줄'` — `logs: null` → `[로그] 로그를 읽지 못했어요.`; `[]` → `[로그] 남은 로그가 없어요.`; 400자 줄 → `input.logs!.single.length == 301` 이고 `endsWith('…')`.
- `'다른 항목이 없으면 그 줄을 뺀다'` — items가 api 하나뿐 → `[같은 실행의 다른 항목]` 없음.
- `'failureReasonText'` — 위 api → `시작하자마자 종료됐어요 (종료 코드 1).`; reason `준비 시간(120초)을 넘겼어요.`+exitCode 143 → `준비 시간(120초)을 넘겼어요. · 종료 코드 143`; exitCode 2만 → `종료 코드 2`; 둘 다 없음 → `이유를 알 수 없어요.`
- `'collect: 가짜 로그·환경 차이를 모은다'` — `FakeLogExcerpt(projects, logs: {('my-team-project', 'api'): [...]})`, `FakeEnvDiff(projects, changes: {'my-team-project': [node 변화]})` → service id `api`, logs·envChanges 그대로, envAvailable true.
- `'collect: EnvDiff·LogExcerpt 가 없으면 못 읽음으로'` — `logs: null, envDiff: null` → `input.logs == null`, `envAvailable == false`.
- `'collect: 지워진 프로젝트여도 던지지 않는다'` — item·run의 projectId `gone`, 가짜들은 `withSamples()` → `service == null`, `logs == null`, `envAvailable == false`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ai && flutter test test/failure_analysis_test.dart`
Expected: FAIL (`failure_analysis.dart` 없음)

- [ ] **Step 3: Implement `failure_analysis.dart`**

시각은 `M/d HH:mm`(`finishedAt`, 0 채움은 시·분만). 종류 라벨: `ProcessService` 내 컴퓨터에서 실행 · `ComposeService` Docker Compose · `RemoteService` 원격 연결. 설정 첫 줄은 있는 것만 ` · `로 잇는다(포트 비면 뺌, `envFile` null이면 뺌, compose `services` 비면 `서비스 파일 전체`). 둘째 줄은 두 칸 들여쓰기로 준비 조건, `dependsOn`이 있으면 ` · 먼저 떠야 하는 항목 {a, b}`. `NoneReady`만 `(N초 안)`을 붙이지 않는다. 결과 라벨은 `성공`/`실패`/`건너뜀`, 이유가 있으면 `(이유)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ai && flutter test test/failure_analysis_test.dart && flutter analyze`
Expected: All tests passed, No issues found

- [ ] **Step 5: Commit**

```bash
git add ai/lib/src/failure_analysis.dart ai/test/failure_analysis_test.dart
git commit -m "feat(ai): AI-02 원인 분석에 보낼 글 (실패 이유·실행 설정·환경 차이·로그)"
```

---

### Task 2: AI 지시와 답 읽기 (`failure_analysis.dart`에 추가)

**Files:**
- Modify: `ai/lib/src/failure_analysis.dart`
- Test: `ai/test/failure_analysis_test.dart`

**Interfaces:**
- Consumes: `FailureAnalysisInput` (Task 1).
- Produces:
  - `const String failureAnalysisSystem` — 설계 §3 지시: 쉬운 한국어 존댓말(~해요), 후보 1~3개 가능성 높은 순, 후보마다 원인 한두 문장·`likelihood`(`high`/`possible`)·근거 번호(`logs`는 #L 번호, `env`는 #E 번호, `reason`은 #R을 근거로 쓰면 true)·`fixes` 1~4단계(명령은 그대로 칠 수 있게), 글에 없는 값 지어내지 않기, 데이터를 지우는 명령(`rm -rf`, `docker compose down -v`)은 제안하지 않고 꼭 필요하면 무엇이 지워지는지 먼저 말하기, JSON 하나만 `{"candidates":[{"cause":"…","likelihood":"high","logs":[2],"env":[1],"reason":false,"fixes":["…"]}]}`.
  - `enum Likelihood { high, possible }`, `String likelihoodLabel(Likelihood l)` — `가능성 높음` / `가능성 있음`.
  - `class FailureCandidate { const FailureCandidate({required String cause, required Likelihood likelihood, List<String> logLines = const [], List<EnvChange> envChanges = const [], bool reason = false, List<String> fixes = const []}); … }` — `logLines`·`envChanges`는 AI가 고른 번호로 찾은 **입력의 실제 값**.
  - `List<FailureCandidate>? parseFailureAnalysis(String reply, FailureAnalysisInput input)`

- [ ] **Step 1: Write the failing tests**

- `'울타리를 벗기고 근거 번호로 실제 줄을 찾는다'` — reply ```` ```json\n{"candidates":[{"cause":"Node 버전이 바뀌었어요.","likelihood":"high","logs":[2],"env":[1],"fixes":["npm install 을 다시 해 주세요."]}]}\n``` ```` → 1개, `logLines == ['Error: The module was compiled against a different Node.js version']`, `envChanges.single.name == 'node'`, `likelihood == Likelihood.high`.
- `'범위 밖·숫자 아닌 번호는 그 번호만 무시'` — `"logs":[2, 9, "1", 0, 2]` → `logLines`가 2번 줄 하나.
- `'근거가 하나도 남지 않은 후보는 뺀다, reason 만 있어도 남는다'` — 후보 A `logs:[9]`(빠짐), 후보 B `reason:true`만(남음, `reason == true`).
- `'cause 가 비면 뺀다, likelihood 가 없거나 모르는 값이면 가능성 있음'`.
- `'가능성 높음을 앞으로, 후보 3개·방법 4개까지'` — 순서 possible(P1), high(H1), possible(P2), high(H2) → `[H1, H2, P1]`. `fixes: ["a", "", " b ", "c", "d", "e"]` → `['a', 'b', 'c', 'd']`.
- `'로그를 못 읽은 입력에 logs 번호가 오면 무시'` — `logs: null` 입력 + `"logs":[1],"env":[]` → null.
- `'JSON 이 아니거나 남는 후보가 없으면 null'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ai && flutter test test/failure_analysis_test.dart`
Expected: FAIL (`parseFailureAnalysis` 없음)

- [ ] **Step 3: Implement** — JSON 꺼내기는 `parseQaSummary`와 같은 방식(첫 `{` ~ 마지막 `}`). 정렬은 안정 정렬(`high` 먼저) 뒤 앞 3개. 번호는 중복을 빼고 AI가 준 순서대로.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ai && flutter test test/failure_analysis_test.dart && flutter analyze`
Expected: All tests passed, No issues found

- [ ] **Step 5: Commit**

```bash
git add ai/lib/src/failure_analysis.dart ai/test/failure_analysis_test.dart
git commit -m "feat(ai): AI-02 원인 분석 지시와 답 읽기 (근거는 실제 값으로)"
```

---

### Task 3: 보내기 공통 조각 (`ai_request.dart`) 과 AI-03 패널 옮기기

**Files:**
- Create: `ai/lib/src/ai_request.dart`
- Modify: `ai/lib/src/qa_summary_panel.dart`
- Test: 기존 `ai/test/qa_summary_panel_test.dart`, `ai/test/ai_screen_test.dart` (고치지 않는다)

**Interfaces:**
- Produces:
  - `const aiWorkingText = '분석하고 있어요. 그동안에도 실행·종료 같은 다른 기능은 그대로 쓸 수 있어요.';`
  - `class AiRequestView<T extends Object> extends StatefulWidget { const AiRequestView({super.key, required LlmClient client, required ApiKeyStore keys, required String requestName, required Future<String> Function() content, required T? Function(String reply) parse, required Widget Function(BuildContext context, T result, VoidCallback again) done, required String startLabel, required String againLabel, String? system, List<String> notes = const [], String? description, ApiKeyCheck? checkKey, VoidCallback? onKeysChanged}); }`
    - `content`는 [startLabel]·[againLabel]·오류의 [다시 시도]를 누를 때마다 새로 부른다.
    - 상태와 화면은 지금 `_QaSummaryPanelState`의 `missingKey`·`keyUnreadable`·`ready`·`working`·`done`·`failed`·`unreadable`·`cancelled`와 같다. `ready`는 `description`(있을 때만, muted) + primary [startLabel]. `cancelled`는 `분석을 멈췄어요.` + `description`(있을 때) + primary [startLabel]. `unreadable`은 `AI 답을 읽지 못했어요.` + [againLabel].
    - 늦은 답 버리기(`_attempt`), 확인 창 [취소] 시 이전 상태로, 보내기 전 비`LlmException` 오류 → `keyUnreadable`, 보낸 뒤 → `network`, 키 입력 창 실패 스낵바 `보안 저장소를 쓰지 못해 키 입력 창을 열지 못했어요.`, `onKeysChanged`는 지금 코드 그대로 옮긴다.
- `QaSummaryPanel`은 `loading`·`empty`(`검사할 항목이 없어요.`)·`allPassed`(`모든 검사를 통과했어요.`)만 직접 그리고, 나머지는 `AiRequestView<List<QaSummarySentence>>(key: ObjectKey(_input), …, startLabel: 'AI 요약', againLabel: '다시 요약', description: _description, notes: const [_sendNote], system: qaSummarySystem)`에 맡긴다. `done`은 지금 `_done`의 내용(문장·근거·플래그·`요약 완료 · {modelName}`·`_afterNotice`·[다시 요약]=`again`).

- [ ] **Step 1: Confirm the AI-03 tests pass before moving code**

Run: `cd ai && flutter test test/qa_summary_panel_test.dart test/ai_screen_test.dart`
Expected: All tests passed

- [ ] **Step 2: Create `ai_request.dart` and move the sending flow out of `qa_summary_panel.dart`**

- [ ] **Step 3: Run the AI-03 tests unchanged**

Run: `cd ai && flutter test && flutter analyze && git diff --stat -- ai/test`
Expected: All tests passed, No issues found, `ai/test` 변경 없음

- [ ] **Step 4: Commit**

```bash
git add ai/lib/src/ai_request.dart ai/lib/src/qa_summary_panel.dart
git commit -m "refactor(ai): 보내기 과정(키 확인·확인 창·취소·오류)을 AiRequestView 로 빼기"
```

---

### Task 4: 원인 분석 패널 (`failure_analysis_panel.dart`)

**Files:**
- Create: `ai/lib/src/failure_analysis_panel.dart`
- Modify: `ai/lib/ai.dart` (export 한 줄)
- Test: `ai/test/failure_analysis_panel_test.dart`

**Interfaces:**
- Consumes: `FailureAnalysisInput.collect`, `parseFailureAnalysis`, `failureAnalysisSystem`, `FailureCandidate`, `likelihoodLabel`, `envChangeLabel`, `failureReasonText` (Task 1·2), `AiRequestView` (Task 3).
- Produces:
  - `const failureAnalysisRequestName = '실행 실패 원인 분석';` `const failureAnalysisDescription = '실패한 항목의 로그와 …(Global Constraints 문구)';`
  - `class FailureAnalysisPanel extends StatefulWidget { const FailureAnalysisPanel({super.key, required ItemResult item, required RunSummary run, required LlmClient client, required ApiKeyStore keys, required ProjectRepository projects, LogExcerpt? logs, EnvDiff? envDiff, String? description, ApiKeyCheck? checkKey, VoidCallback? onKeysChanged}); }`
  - `ai.dart`: `export 'src/failure_analysis_panel.dart' show FailureAnalysisPanel, failureAnalysisDescription, failureAnalysisRequestName;`
- `content`는 매번 `collect`로 새로 모아 state에 두고(`parse`가 그 입력으로 읽게) `prompt`를 돌려준다. `startLabel: '원인 분석'`, `againLabel: '다시 분석'`, notes는 Global Constraints 문구.
- 완료 화면(후보마다): `StatusChip('원인 후보 · ${likelihoodLabel(l)}', l == Likelihood.high ? C.warn : C.idle)` → 원인 문장 → (`logLines` 있으면) `근거 로그 · {item.serviceId} 마지막 실행` + 줄마다 `mono` → `환경 차이 · {envChangeLabel}` → (`reason`이면) `실패 이유 · {failureReasonText(item)}` → (`fixes` 있으면) `해결 방법` + `1. …`. 끝에 `분석 완료 · {modelName}`(mono), 주의 문구, [다시 분석]=`again`.

- [ ] **Step 1: Write the failing tests** (`failure_analysis_panel_test.dart`)

준비: `FakeProjectRepository.withSamples()`, Task 1의 `api`·`run`, `MemoryApiKeyStore('AQ.test-key-abcdefghijklmnop')`, `FakeLogExcerpt(projects, logs: {('my-team-project','api'): ['Starting backend', 'Error: The module was compiled against a different Node.js version']})`, `FakeEnvDiff(projects, changes: {'my-team-project': [EnvChange(name: 'node', before: '20.11.0', after: '22.3.0')]})`. 답을 붙잡는 가짜 AI는 이 파일 안에 따로 둔다(`qa_summary_panel_test.dart`는 고치지 않는다).

- `'AT-21: [보내기] 전과 [취소] 뒤 요청 0건, 보낸 내용에 환경변수·호스트·키가 없다'` — [원인 분석] → 확인 창 → `FakeLlmClient.sent` 비어 있음 → [취소] → 비어 있음 → 다시 [원인 분석] → [보내기] → `sent.single`에 `SPRING_PROFILES_ACTIVE`·`localhost`·저장된 키가 없다.
- `'AT-22: Node 20 → 22 로 실패하면 후보에 환경 차이와 실제 로그 줄'` — 답 `{"candidates":[{"cause":"지어낸 줄: Error: fake","likelihood":"high","logs":[2],"env":[1],"fixes":["npm install 을 다시 해 주세요."]}]}` → `원인 후보 · 가능성 높음`, `근거 로그 · api 마지막 실행`, `Error: The module was compiled against a different Node.js version`, `환경 차이 · node 20.11.0 → 22.3.0`, `1. npm install 을 다시 해 주세요.`, `분석 완료 · {modelName}`, 주의 문구, [다시 분석]이 보인다.
- `'Review 1: 로그에 남은 비밀값은 가리고 몇 곳인지 알린다'` — 로그에 `DB_PASSWORD=hunter2` → 확인 창에 `비밀값으로 보이는 1곳을 가렸어요.`가 들어간 글, 보낸 글에 `hunter2` 없음.
- `'Review 5: [다시 분석]은 새 로그로 다시 보낸다'` — 첫 분석 뒤 `FakeLogExcerpt`에 넘긴 목록 대신 새 줄이 나오도록(로그 맵을 바꿀 수 있는 작은 `LogExcerpt` 가짜를 파일 안에 둔다) → [다시 분석] → [보내기] → `sent.last`에 새 줄이 있다.
- `'AT-19: 키가 없으면 API 키 필요와 [키 입력], [원인 분석]은 없다'` — `MemoryApiKeyStore()` + `FakeLlmClient(configured: false)`.
- `'오류는 llmErrorText 로, 답을 못 읽으면 [다시 분석]'` — `failWith: LlmFailure.quotaExceeded` → `사용량을 넘었어요`·[다시 시도]; 답 `not json` → `AI 답을 읽지 못했어요.`·[다시 분석].
- `'분석 중 [취소]하면 분석을 멈췄어요, 늦은 답은 버린다'`.
- `'설명은 넘길 때만 보인다'` — `description: null`이면 `failureAnalysisDescription` 없음·[원인 분석]만, 넘기면 보인다.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ai && flutter test test/failure_analysis_panel_test.dart`
Expected: FAIL (`FailureAnalysisPanel` 없음)

- [ ] **Step 3: Implement `failure_analysis_panel.dart` and the export**

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ai && flutter test && flutter analyze`
Expected: All tests passed, No issues found

- [ ] **Step 5: Commit**

```bash
git add ai/lib/src/failure_analysis_panel.dart ai/lib/ai.dart ai/test/failure_analysis_panel_test.dart
git commit -m "feat(ai): AI-02 원인 분석 패널 (원인 후보·근거·해결 방법)"
```

---

### Task 5: 화면 8 카드·등록·기획서

**Files:**
- Modify: `ai/lib/src/ai_screen.dart`, `ai/lib/ai.dart`
- Modify: `ai/test/ai_screen_test.dart` (147·155행 문구 확인 2곳 + 새 group), `ai/test/ai_register_test.dart` (`TestRegistry.read` + 새 test)
- Modify: `docs/포폴링_개발기획서.md` §2 AI 표 AI-02 줄
- Add: `docs/superpowers/specs/2026-11-23-ai-failure-analysis-design.md`, `docs/superpowers/plans/2026-11-23-ai-failure-analysis.md`

**Interfaces:**
- Consumes: `FailureAnalysisPanel`, `failureAnalysisDescription`, `failureReasonText` (Task 1·4).
- Produces: `AiScreen`에 `ProjectRepository? projects`, `LogExcerpt? logs`, `EnvDiff? envDiff` 생성자 인자.
- 카드는 `projectId`·`orchestrator`·`projects`가 모두 있을 때 `헬스체크 결과 요약` 카드 **위**에 그린다. `initState`에서 `lastRun`을 한 번 읽는다(예외면 null). 머리 시각은 기존 `_when(finishedAt)`. 실패 행마다 `FailureAnalysisPanel(key: ValueKey('${item.serviceId}-$_status'), …, onKeysChanged: _load)`, 설명은 카드에 한 번만.
- 프로젝트가 있으면 "준비 중" 줄을 지우고, 없으면 Global Constraints의 안내 문구.
- `register()`: 파일 안 `T? _tryRead<T extends Object>(AppRegistry app)`(`StateError`면 null)로 `projects`·`logs`·`envDiff`를 프로젝트 ID가 있을 때만 꺼낸다. 기존 `qa`·`orchestrator` 꺼내기는 그대로.
- 테스트의 `TestRegistry.read`는 `app/`의 `Registry`처럼 없으면 `StateError`를 던지게 바꾼다(지금은 `!`라 `TypeError`).

- [ ] **Step 1: Write the failing tests**

`ai_screen_test.dart`:
- 147행 기대 문구 → `프로젝트 대시보드에서 [AI 검사]를 누르면 그 프로젝트의 실행 실패 원인 분석과 헬스체크 결과 요약을 볼 수 있어요.` / 155행 `실행 실패 원인 분석은 준비 중이에요.` → `findsNothing`.
- group `'실행 실패 원인 분석 카드 (AI-02)'` (`FakeOrchestrator(projects, failing: {ref('api')})`, `projects`, `FakeLogExcerpt`, `FakeEnvDiff`를 넘긴다):
  - `'전체 실행 기록이 없으면 실패한 실행이 없어요'`
  - `'실패 항목마다 [원인 분석], 건너뜀은 버튼 없이, 설명은 한 번'` — `runAll` 뒤: `textContaining('api · 실패 · 시작하자마자 종료됐어요')`, `textContaining('web · 건너뜀')`, `btn('원인 분석')` 하나, 설명 문구 하나, `textContaining('전체 실행 기준')`.
  - `'원인 분석 카드는 헬스체크 결과 요약 카드 위에'` — 두 제목의 `getTopLeft().dy` 비교.
  - `'머리에서 키를 넣으면 카드의 [키 입력]이 [원인 분석]으로 바뀐다'`.

`ai_register_test.dart`:
- `'/ai 에 프로젝트를 넘기면 EnvDiff·LogExcerpt 가 등록되지 않아도 원인 분석을 연다'` — `ProjectRepository`·`QaRunner`·`Orchestrator`(api 실패로 `runAll` 끝낸 것)만 등록, 키는 `FlutterSecureStorage.setMockInitialValues` → `/ai`를 `arguments: 'my-team-project'`로 열기 → [원인 분석] → `find.byKey(const Key('send-preview'))`의 글에 `환경 비교를 아직 쓸 수 없어요.`와 `로그를 읽지 못했어요.` → [취소].

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ai && flutter test test/ai_screen_test.dart test/ai_register_test.dart`
Expected: FAIL (새 문구·카드 없음)

- [ ] **Step 3: Implement the card and registration in `ai_screen.dart`·`ai.dart`**

- [ ] **Step 4: Run all checks**

Run: `cd ai && flutter test && flutter analyze` 그리고 저장소 루트에서 `bash .github/scripts/check-imports.sh`
Expected: All tests passed, No issues found, import 검사 통과

- [ ] **Step 5: Update 기획서 §2 AI-02 줄**

"보내는 데이터" 칸 `실패 로그 일부, 환경 비교 결과(FR-16)` → `실패 로그 일부, 환경 비교 결과(FR-16), 항목 실행 설정(명령·폴더·포트·준비 조건. 환경변수는 보내지 않음)`. 다른 줄은 건드리지 않는다.

- [ ] **Step 6: Commit**

```bash
git add ai/lib/src/ai_screen.dart ai/lib/ai.dart ai/test/ai_screen_test.dart ai/test/ai_register_test.dart "docs/포폴링_개발기획서.md" docs/superpowers/specs/2026-11-23-ai-failure-analysis-design.md docs/superpowers/plans/2026-11-23-ai-failure-analysis.md
git commit -m "feat(ai): 화면 8 실행 실패 원인 분석 카드 (AI-02), 기획서 보내는 데이터 갱신"
```

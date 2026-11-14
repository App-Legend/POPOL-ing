# RuntimeQuery 계약 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 포트를 쓰는 프로세스가 포폴링이 띄운 내 항목인지 답하는 `RuntimeQuery` 계약·가짜 구현·약속 테스트를 `core/`에 추가한다.

**Architecture:** 기존 계약(`PortProbe`·`LogExcerpt`)과 같은 4종 세트. `contracts/`의 인터페이스, `fakes/`의 가짜 구현, `testing/`의 약속 테스트 묶음, `test/fakes_contract_test.dart`의 그룹 하나. 각 묶음 파일(`contracts.dart`·`fakes.dart`·`testing.dart`·`models.dart`)에 export 한 줄씩.

**Tech Stack:** Dart / Flutter, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-11-12-runtime-query-design.md`

## Global Constraints

- 기존 계약 파일은 고치지 않고 추가만 한다(`core/` 1.0 규칙).
- 패키지 추가 없음.
- 주석·테스트 이름은 한국어, 기존 파일 말투(`~다`)를 따른다.
- 프로세스를 종료하는 코드 없음. `ownerOf`는 예외를 던지지 않는다.

## Review Focus

- 포트는 맞고 PID가 다름(외부 프로그램이 포트를 가져감) → null. Task 1 테스트 2.
- 프로세스 항목인데 `PortInUse.pid == null`(권한 부족) → null. Task 1 테스트 3.
- Compose 항목은 PID가 docker 쪽(아무 값)이거나 null이어도 → 그 항목. Task 1 테스트 4.
- 항목을 중지해 기록에서 빠진 뒤 같은 포트 → null. 가짜 구현만의 동작 테스트(Task 1 Step 5).

---

### Task 1: `ItemRef` 모델, `RuntimeQuery` 계약, 가짜 구현, 약속 테스트

**Files:**
- Create: `core/lib/models/item_ref.dart`
- Create: `core/lib/contracts/runtime_query.dart`
- Create: `core/lib/fakes/fake_runtime_query.dart`
- Create: `core/lib/testing/runtime_query_contract.dart`
- Modify: `core/lib/models.dart`, `core/lib/contracts.dart`, `core/lib/fakes.dart`, `core/lib/testing.dart` (export 한 줄씩, 알파벳 순서 자리)
- Test: `core/test/fakes_contract_test.dart`

**Interfaces:**
- Produces:
  - `typedef ItemRef = ({String projectId, String serviceId});` (레코드라 `==` 비교가 된다)
  - `abstract interface class RuntimeQuery { Future<ItemRef?> ownerOf(PortInUse usage); }`
  - `typedef OwnedPort = ({int port, int? pid, ItemRef item});` (`pid == null`이면 Compose 항목, 포트만으로 판단)
  - `class FakeRuntimeQuery implements RuntimeQuery { FakeRuntimeQuery({Iterable<OwnedPort> owned = const []}); final List<OwnedPort> owned; }`
  - `class RuntimeQueryFixture { query, processPort, processPid, processItem, composePort, composeItem, unownedPort }` + `void runtimeQueryContract(Future<RuntimeQueryFixture> Function() setUp)`

- [ ] **Step 1: 약속 테스트 묶음과 그룹을 먼저 쓴다**

`runtime_query_contract.dart`의 테스트(이름과 단언):
1. `포트와 PID 가 실행 기록과 맞으면 그 항목이다`: `ownerOf(PortInUse(processPort, pid: processPid))` == `processItem`
2. `포트만 맞고 PID 가 다르면 null 이다(외부 프로그램)`: `pid: processPid + 1` → `isNull`
3. `프로세스 항목인데 PID 를 모르면 null 이다`: `PortInUse(processPort)` → `isNull`
4. `Compose 항목은 PID 와 상관없이 포트로 판단한다`: `PortInUse(composePort)`와 `PortInUse(composePort, pid: 99999)` 모두 == `composeItem`
5. `기록에 없는 포트는 null 이다`: `PortInUse(unownedPort, pid: processPid)` → `isNull`

`fakes_contract_test.dart`에 그룹 추가:
```dart
group('FakeRuntimeQuery', () {
  runtimeQueryContract(() async => RuntimeQueryFixture(
        query: FakeRuntimeQuery(owned: [
          (port: 5173, pid: 4321, item: (projectId: 'shop-clone', serviceId: 'web')),
          (port: 3306, pid: null, item: (projectId: 'my-team-project', serviceId: 'db')),
        ]),
        processPort: 5173, processPid: 4321, processItem: (projectId: 'shop-clone', serviceId: 'web'),
        composePort: 3306, composeItem: (projectId: 'my-team-project', serviceId: 'db'),
        unownedPort: 8080,
      ));
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd core && flutter test test/fakes_contract_test.dart`
Expected: 컴파일 실패(`FakeRuntimeQuery`·`runtimeQueryContract` 없음)

- [ ] **Step 3: 모델·계약·가짜 구현을 만든다**

- `item_ref.dart`: typedef 하나 + 한 줄 주석(화면 이름은 C가 `ProjectRepository`에서 찾는다).
- `runtime_query.dart`: `port_probe.dart`처럼 진짜 구현(A `runner/`)·쓰는 곳(C 포트 확인 FR-06, AT-03·17)·지켜야 할 약속 1~4를 주석으로. 약속 3에는 "Compose 포트는 C 의 `ItemLauncher` 로 조회한다"를 적는다.
- `fake_runtime_query.dart`: `owned`에서 `port`가 같고 (`pid == null` 또는 `usage.pid != null && pid == usage.pid`)인 첫 항목의 `item`, 없으면 null. `FakePortProbe`처럼 사용 예시 주석.
- 묶음 파일 4개에 export 추가.

- [ ] **Step 4: 통과 확인**

Run: `cd core && flutter test && flutter analyze`
Expected: 모든 테스트 통과, analyze 문제 없음

- [ ] **Step 5: 가짜 구현만의 동작 테스트 추가**

`가짜 구현만의 동작` 그룹에:
`FakeRuntimeQuery 는 항목을 목록에서 빼면 바로 null 이 된다`: `owned.clear()` 뒤 `ownerOf(PortInUse(5173, pid: 4321))` → `isNull`

- [ ] **Step 6: 통과 확인 후 커밋**

Run: `cd core && flutter test`
Expected: PASS

```bash
git add core/lib core/test docs/superpowers
git commit -m "feat(core): RuntimeQuery 계약과 가짜 구현·약속 테스트 추가"
```

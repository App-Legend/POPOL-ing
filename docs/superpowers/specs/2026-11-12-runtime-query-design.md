# RuntimeQuery 계약 설계

- 날짜: 2026-11-12
- 담당: A(실행 제어) 제공, C(포트 확인) 사용
- 브랜치: `feat/runtime-query`

## 목적

포트를 쓰고 있는 프로세스가 포폴링이 띄운 **내 항목**인지 알려준다. C의 포트 확인(FR-06, AT-03·17)이 이 답으로 화면을 나눈다.

- 내 항목: "shop-clone / web 이 사용 중" + [이동]·[그 항목 중지]
- 외부 프로그램: 프로그램 이름·PID만 보여주고 종료하지 않는다

C의 `PortProbe.whoUses()`는 `PortInUse(port, pid?, processName?)`까지만 알려준다. 그 포트가 내 항목인지 판단하는 일은 `PortInUse` 주석에서 A의 `RuntimeQuery`로 넘겨 두었다.

## 방식 비교

| 방식 | 내용 | 장단점 |
|---|---|---|
| 1. 포트 번호만 받기 | `ownerOfPort(8080)` | 가장 단순하다. 하지만 설정상 내 항목 포트라는 이유만으로 내 것이라고 답한다. 내 항목이 포트를 못 잡아 실패했고 실제로는 외부 프로그램이 그 포트를 쓰고 있어도 "내 항목 사용 중"으로 잘못 표시된다(AT-03과 어긋남) |
| **2. `PortInUse`를 통째로 받기 (선택)** | 받은 PID가 내가 띄운 프로세스 그룹에 들어 있는지 실행 기록과 비교한다. Compose는 포트 매핑으로 판단한다 | C가 `whoUses` 결과를 그대로 넘기면 된다. "포트나 PID 하나만으로 판단하지 않는다"는 원칙에 맞는다 |

2번을 고른 이유: 외부 프로그램을 내 항목으로 착각하면 잘못된 [중지] 버튼이 생긴다. 이걸 막는 쪽이 원칙(CLAUDE.md "꼭 지킬 것")에 맞다.

## 계약

`core/lib/contracts/runtime_query.dart`

```dart
abstract interface class RuntimeQuery {
  /// [usage] 의 포트를 포폴링이 띄운 내 항목이 쓰고 있으면 그 항목, 아니면 null.
  Future<ItemRef?> ownerOf(PortInUse usage);
}
```

모델 `ItemRef(projectId, serviceId)`. 화면에 보여줄 이름은 C가 `ProjectRepository`에서 찾는다. 그래서 여기에는 ID만 둔다.

## 지켜야 할 약속

1. **프로세스 항목**: 포트와 PID가 모두 실행 기록과 맞을 때만 내 항목이다. 포트만 맞고 PID가 다르면 null(외부 프로그램)이다.
2. **PID를 모를 때**(`pid == null`, 권한 부족 등): 프로세스 항목은 null이다. 확인할 수 없으면 내 것이라고 하지 않는다.
3. **Compose 항목**: PID가 docker 쪽이라 맞지 않는다. 그래서 `ppoling-<프로젝트ID>` 프로젝트의 포트 매핑으로 판단한다. 이건 진짜 구현의 몫이고, 가짜 구현에서는 PID가 없는 항목으로 흉내 낸다.
4. 프로세스를 종료하지 않는다. 예외를 던지지 않고, 모르면 null을 돌려준다.

## 만들 것

| 파일 | 내용 |
|---|---|
| `core/lib/models/item_ref.dart` | `ItemRef` 모델. `models.dart`에서 내보냄 |
| `core/lib/contracts/runtime_query.dart` | 계약. `contracts.dart`에서 내보냄 |
| `core/lib/fakes/fake_runtime_query.dart` | `FakeRuntimeQuery(owned: [...])`. 테스트 중에 목록을 바꿀 수 있다(항목을 중지하면 목록에서 빠짐). 형태는 `FakePortProbe`와 같다 |
| `core/lib/testing/runtime_query_contract.dart` | `runtimeQueryContract`: 약속 1·2와 "기록에 없는 포트는 null"을 확인한다 |
| `core/test/fakes_contract_test.dart` | `FakeRuntimeQuery` 그룹 추가 |

## 하지 않는 것

- `Orchestrator`, `core/events`: 다음 작업으로 미룬다.
- 진짜 구현(`runner/`의 실행 기록 대조): 3주차 전반에 한다.
- Compose 포트 매핑 조회: `runner/`는 `compose/`를 import할 수 없다. 그래서 C의 `ItemLauncher` 계약에 "띄운 Compose 항목의 포트" 조회를 넣어 달라고 요청하고, A의 진짜 구현은 그 계약을 부른다(윤서와 협의). A가 `docker compose ps`를 직접 부르면 Compose 코드가 두 곳으로 나뉜다.

## 구현자에게 맡기는 것

- 가짜 구현이 받을 항목 목록의 자료 모양(레코드 또는 작은 클래스)
- 약속 테스트 준비물(fixture)의 필드 구성. 기존 `PortProbeFixture`·`LogExcerptFixture` 방식을 따른다

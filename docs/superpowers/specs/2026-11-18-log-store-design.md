# 로그 저장(LogStore) 설계

- 날짜: 2026-11-18
- 담당: A(실행 제어)
- 브랜치: `feat/runner`

## 목적

포폴링이 띄운 프로세스 항목의 출력을 파일에 남긴다. 지금은 출력이 준비 확인(`LogReady`)에만 쓰이고 버려져서, 서버가 죽어도 무슨 말을 남겼는지 볼 수 없다.

이 파일을 쓰는 곳:
- FR-03 시작 실패 시 "로그 위치" 표시
- FR-09 로그 화면·[파일 열기]
- 금요일 `LogExcerpt`(AI-02로 보낼 실패 로그 끝부분)

## 방식 비교

| 방식 | 장단점 |
|---|---|
| **1. `_upProcess`에서 출력을 `LogStore`에도 흘리기 (선택)** | `.env` 값을 아는 곳이라 쓰기 전에 가릴 수 있다. 고칠 곳이 한 군데 |
| 2. OS별 `ProcessLauncher`에서 쓰기 | `.env` 값을 몰라 가릴 수 없다. 두 OS 구현에 같은 코드가 생긴다 |
| 3. `core` 계약으로 만들기 | `runner/` 안에서만 쓰는 부품이라 계약이 필요 없다 |

## 정한 것

1. **범위:** 프로세스 항목만. Compose 로그는 Docker가 보관하므로 `ItemLauncher.logs`로 읽는다(사용자 결정).
2. **위치:** `<앱 데이터>/logs/<프로젝트ID>/<항목ID>.log`. 앱 데이터 폴더는 `path_provider`의 `getApplicationSupportDirectory()`로 구한다(`runner/pubspec.yaml`에 추가, `project/`와 같은 `^2.1.5` — 사용자 승인).
3. **이어 쓰기:** 다시 실행하면 같은 파일 끝에 `--- 시작 <ISO 시각> ---` 구분 줄을 넣고 이어 쓴다.
4. **줄 형식:** `<ISO 시각> out | <내용>`, stderr는 `err`. FR-09의 stdout/stderr 구분을 파일에서도 알 수 있게.
5. **비밀값:** 그 항목 `.env` 값 중 비어 있지 않은 것을 모두 `****`로 바꾼 뒤 쓴다(기획서 §13, AT-11). 짧은 값도 가린다. 읽기 불편함보다 새는 쪽이 더 나쁘다.
6. **회전:** 10MB를 넘으면 `.log` → `.log.1` → `.log.2`, 3개까지 남긴다(기획서 §13 초안).
7. **쓰기 실패:** 디스크 가득 참 등으로 실패해도 실행은 계속한다. 로그 때문에 서버가 멈추면 안 된다.
8. **ID 검사는 하지 않는다:** 프로젝트ID(`Project.idPattern`)·항목ID(`config_reader.dart`의 `_serviceIdPattern`)는 `core`가 이미 걸러, 경로를 벗어나는 글자(`/`·`\`·`..`)가 들어올 수 없다. 설정 문제가 있으면 시작 전에 막힌다.

## 이번에 하지 않는 것

화면용 최근 5,000줄 버퍼, `LogExcerpt`(금요일), Compose 로그 저장, 오래된 로그 폴더 정리.

## 바뀌는 파일

- 새로: `runner/lib/src/log/log_store.dart`, `runner/test/log_store_test.dart`
- 수정: `runner/lib/src/orchestrator/runner_orchestrator.dart`, `runner/lib/runner.dart`, `runner/pubspec.yaml`

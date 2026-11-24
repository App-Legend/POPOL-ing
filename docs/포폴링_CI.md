# 포폴링 CI

PR을 올리면 GitHub가 자동으로 하는 검사. 설정: `.github/workflows/ci.yml`

## 언제 도나요

- `dev`·`main`으로 가는 PR을 열거나 새 커밋을 푸시할 때
- `dev`·`main`에 코드가 들어갈 때

## 무엇을 검사하나요

| 컴퓨터 | 검사 |
|---|---|
| Linux | import 규칙, 분석, `compose/` 테스트 |
| macOS | 나머지 패키지 테스트, 앱 빌드 |
| Windows | 나머지 패키지 테스트, 앱 빌드 |

## 왜 이렇게 나눴나요

- 테스트는 지원 OS인 macOS·Windows에서 한다.
- Linux는 지원 OS가 아니라 검사용 컴퓨터다.
- import 규칙·분석은 코드만 읽어 OS와 거의 상관없다. 맥 서버가 밀려도 먼저 볼 수 있다.
- `compose/` 테스트는 실제 Docker가 켜져 있어야 확인되는 항목이 있다. Linux 서버에는 켜져 있고 macOS 서버에는 없는 것을 확인했다. Windows 서버는 미확인.
- 빌드는 OS마다 도구와 중계를 넣는 방법이 달라 각각 해 봐야 한다.

## CI가 확인하지 못하는 것

- 실제 화면과 버튼 동작: PR 체크박스의 macOS·Windows 확인으로 사람이 본다.
- Windows에서 건너뛰는 테스트(`runner_orchestrator_test.dart` 등)
- 배포용(release) 빌드

## 실패하면

1. PR의 Details에서 로그를 본다.
2. 고쳐서 같은 브랜치에 푸시한다.
3. 맥 서버 부족이면 Re-run failed jobs.

지금은 실패해도 병합이 막히지 않으니 병합 전에 직접 확인한다.

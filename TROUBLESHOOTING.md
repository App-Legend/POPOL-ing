# 문제 해결 기록

한 번 겪은 문제를 **문제 → 원인 → 해결** 순서로 남겨요. 비슷한 증상이 보이면 여기부터 확인하세요. 새로 겪으면 맨 위에 추가해요.

형식:

```md
## <증상을 사용자가 본 그대로 한 줄>

- **날짜:** YYYY-MM-DD
- **문제:** <무엇이 보였나, 오류 문구·코드 그대로>
- **원인:** <진짜 원인, 로그·예외 메시지 포함>
- **해결:** `<파일>`의 `<함수>`: <무엇을 바꿨나>
```

---

## `flutter analyze`가 "FormatException: Unterminated string"으로 멈춤

- **날짜:** 2026-11-14
- **문제:** `project/`에서 `flutter analyze`를 실행하면 결과 없이 `Unhandled exception: FormatException: Unterminated string (at character 644)` … `analysis server exited with code 255`가 나온다. 오류 위치에 퍼센트 인코딩된 폴더 경로(`...%E1%84%92...POPOL-ing/project/`)가 보인다.
- **원인:** 확인하지 못함. 저장소 경로의 한글 폴더명(`모바일 통합구현2`)이 분석 서버에 넘어가며 깨진 것으로 추정한다. 코드 문제는 아니다(`dart analyze`는 정상 동작).
- **해결:** 같은 폴더에서 `dart analyze`로 대신 검사한다. CI(영문 경로)에서는 `flutter analyze`가 그대로 돈다. 근본 해결은 저장소를 영문 경로로 옮기는 것(미확인).

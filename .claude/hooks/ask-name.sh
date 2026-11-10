#!/usr/bin/env bash
# SessionStart 훅: 첫 답 전에 사용자 이름과 역할부터 확인하게 한다.
cat <<'EOF'
[세션 시작 규칙] 사용자의 첫 요청에 답하기 전에, 메모리에서 사용자 이름과 역할(A~D)을 찾는다.
없는 것이 있으면 다른 작업보다 먼저 AskUserQuestion으로 묻고(역할은 docs/포폴링_역할분담.md의 A~D를 선택지로), 답을 받으면 메모리에 이름은 user-name.md, 역할은 user-role.md로 따로 남긴다. 둘 다 있으면 묻지 않는다.
EOF

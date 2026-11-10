#!/bin/sh
# git commit 전에 타임라인을 적을지 사용자에게 묻게 한다.
# timeline/ 폴더가 있는 저장소에서만 동작하고, 같은 세션·같은 HEAD에서는 한 번만 막는다(다시 실행하면 통과).
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."')
sid=$(printf '%s' "$input" | jq -r '.session_id // "none"')
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$root/timeline" ] || exit 0

head=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)
mark="${TMPDIR:-/tmp}/claude-timeline-asked-$sid-$head"
[ -e "$mark" ] && exit 0
touch "$mark"

jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"커밋 전에 사용자에게 timeline/<이름>.md 맨 위에 오늘 한 일을 적을지 먼저 물어보세요(AskUserQuestion). 적기로 하면 적은 뒤, 아니면 그대로 같은 커밋 명령을 다시 실행하면 통과합니다."}}'

#!/usr/bin/env bash
# block-risky.sh 자체 점검. 사용: .claude/hooks/block-risky.test.sh
# 현재 브랜치가 main인 임시 저장소를 만들어 "브랜치 생략" 경우까지 본다.
set -u
hook="$(cd "$(dirname "$0")" && pwd)/block-risky.sh"
fail=0

check() { # 기대(block|ask|pass) 명령 [작업 폴더]
  local out code got
  out=$(cd "${3:-.}" && jq -n --arg c "$2" '{tool_input:{command:$c}}' | "$hook" 2>&1)
  code=$?
  if ((code == 2)); then got=block; elif [[ $out == *'"ask"'* ]]; then got=ask; else got=pass; fi
  [[ $got == "$1" ]] || { echo "✗ $2 (기대 $1, 실제 $got)"; fail=1; }
}

on_main=$(mktemp -d)
git -C "$on_main" init -q -b main
on_feat=$(mktemp -d)
git -C "$on_feat" init -q -b feat/x

check block 'git push origin main'
check block 'git push -u origin main'
check block 'git push origin +main'
check block 'git push origin HEAD:main'
check block 'git push origin feat/x:refs/heads/main'
check block 'git push --all origin'
check block 'cd app && git push origin main'
check block 'git push' "$on_main"
check block 'git push origin HEAD' "$on_main"
check block "git -C $on_main push"
check block 'docker push foo'
check block 'rm -rf build'
check ask 'git push origin feat/harness'
check ask 'git push -o ci.skip origin dev'
check ask 'git push origin main:feat/x'
check ask 'git push' "$on_feat"
check pass 'git status'

rm -r "$on_main" "$on_feat"
((fail)) || echo "✓ block-risky 점검 통과"
exit "$fail"

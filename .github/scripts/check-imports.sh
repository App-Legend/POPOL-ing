#!/usr/bin/env bash
# 기능 폴더는 core/ 만 import 한다(역할분담 §3). 다른 기능을 직접 쓰면 실패한다.
# 맨 위 폴더 중 pubspec.yaml 이 있는 것을 패키지로 보고, 이름은 ppoling_<폴더명> 이어야 한다.
# 사용: .github/scripts/check-imports.sh [저장소 경로]
set -euo pipefail
cd "${1:-.}"

fail=0
for pub in */pubspec.yaml; do
  dir=${pub%/pubspec.yaml}
  [ "$dir" = app ] && continue # 조립하는 곳이라 모든 기능을 import 한다.
  self="ppoling_$dir"

  if ! grep -qE "^name: $self\s*$" "$pub"; then
    echo "✗ $pub: 패키지 이름은 $self 여야 합니다."
    fail=1
  fi

  # core 는 아무 기능도, 기능은 core 와 자기 자신만 쓸 수 있다.
  allowed="ppoling_core|$self"
  deps=$(grep -nE '^[[:space:]]+ppoling_[a-z_]+:' "$pub" | grep -vE "[[:space:]]($allowed):" || true)
  imports=$(grep -rnoE --include='*.dart' --exclude-dir=.dart_tool --exclude-dir=build \
    'package:ppoling_[a-z_]+' "$dir" | grep -vE ":package:($allowed)$" || true)

  if [ -n "$deps$imports" ]; then
    echo "✗ $dir/ 가 다른 기능 패키지를 씁니다. core/ 의 계약으로 바꿔 주세요."
    [ -n "$deps" ] && echo "$deps" | sed "s|^|  $pub:|"
    [ -n "$imports" ] && echo "$imports" | sed 's|^|  |'
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "✓ import 규칙 통과"
exit "$fail"

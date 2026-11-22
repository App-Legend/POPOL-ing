#!/bin/sh
# 앱 번들(Contents/MacOS)에 중계(ppoling-relay)를 넣는다. 실행 제어(runner)가 서비스를 이 중계로 띄운다.
# Xcode 빌드 단계 "Build Relay" 가 부른다. 중계 소스가 바뀌지 않았으면 다시 컴파일하지 않는다.
set -e
RELAY_DIR="$PROJECT_DIR/../../runner/relay"
OUT="$BUILT_PRODUCTS_DIR/$EXECUTABLE_FOLDER_PATH/ppoling-relay"
DART="$FLUTTER_ROOT/bin/dart"

if [ -f "$OUT" ] && [ -z "$(find "$RELAY_DIR" -name '*.dart' -newer "$OUT")" ]; then
  exit 0
fi
"$DART" pub get --directory "$RELAY_DIR" > /dev/null
"$DART" compile exe "$RELAY_DIR/bin/ppoling_relay.dart" -o "$OUT"
# 앱을 서명하기 전에 안에 든 실행 파일부터 서명해야 앱 서명이 깨지지 않는다.
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$OUT"

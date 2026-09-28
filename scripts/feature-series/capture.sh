#!/bin/bash
# Shoot the DEBUG capture screens an episode needs, in one UI language.
#   scripts/feature-series/capture.sh ko transcript talkdetail-cards say-again-reading say-again-done
# Needs a simulator build (`xcodebuild … -derivedDataPath build build`) and a booted simulator.
set -euo pipefail
LANG_CODE=${1:?ui language, e.g. ko}; shift
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SIM=${SIM:-$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}')}
APP="$ROOT/build/Build/Products/Debug-iphonesimulator/FutureVoice.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
OUT="$(dirname "$0")/out/$LANG_CODE/raw"; mkdir -p "$OUT"
xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
for m in "$@"; do
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$BUNDLE" -capture "$m" -futurevoice.nativeLanguage "$LANG_CODE" \
    -AppleLanguages "($LANG_CODE)" >/dev/null
  sleep "${WAIT:-7}"
  xcrun simctl io "$SIM" screenshot "$OUT/$m.png" >/dev/null 2>&1
  echo "$OUT/$m.png"
done

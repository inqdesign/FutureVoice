#!/bin/bash
# capture.sh <capture-name> <out.png> [lang=ko]
# Screenshot the REAL app in a state from the DEBUG capture harness
# (FutureVoice/Views/DebugCaptureHarness.swift: `case "…"` names), on a booted simulator
# with the dev build installed. The simulator is shared: one capture at a time, and
# tell the lead before installing a new build.
set -euo pipefail
NAME=$1; OUT=$2; LANG_=${3:-ko}
UDID=${SIM_UDID:-$(xcrun simctl list devices booted | grep -m1 -o '[0-9A-F-]\{36\}')}
BUNDLE=com.roro.futurevoice.dev
LOCALE=$([ "$LANG_" = ko ] && echo ko_KR || echo en_US)
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -capture "$NAME" -AppleLanguages "($LANG_)" -AppleLocale "$LOCALE" >/dev/null
sleep "${CAPTURE_WAIT:-8}"
xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null
echo "$OUT"

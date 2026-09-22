#!/usr/bin/env bash
# Shoot every capture mode on the emulator and record whether it survived.
#
#   scripts/android/capture-sweep.sh <out-dir> [lang] [mode ...]
#
# Writes <out-dir>/<mode>.png for each mode and <out-dir>/result.tsv with
# one line per mode: mode, status (ok | crash), seconds. Modes default to
# every mode the harness registers (read from CaptureRouter.kt).
# CAPTURE_WAIT (default 15 s): a mode's first launch seeds the stores and
# cold-starts the app; 6 s caught 42 of 103 on the splash or a spinner.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?out dir}; LANG_=${2:-ko}; shift 2 2>/dev/null || shift $#
mkdir -p "$OUT"
PKG=com.roro.futurevoice.capture
ACT=$PKG/com.roro.futurevoice.MainActivity
ROUTER=android/app/src/capture/java/com/roro/futurevoice/capture/CaptureRouter.kt
if [ $# -gt 0 ]; then MODES=("$@"); else
  MODES=($(awk '/val iosModes/,/^    \)/' "$ROUTER" | grep -oE '"[a-z0-9-]+"' | tr -d '"'))
fi
: > "$OUT/result.tsv"
# Warm-up: the first cold start after an install or a night-mode switch runs
# long enough to be photographed on the splash. Spend it on a throwaway shot.
adb shell am start -n $ACT --es capture paywall --es lang "$LANG_" >/dev/null 2>&1; sleep 20
# System bar frames, for the "covered control" check.
adb shell dumpsys window 2>/dev/null | grep -oE "type=(statusBars|navigationBars)[^}]*frame=\[[0-9,]+\]\[[0-9,]+\]" | sort -u > "$OUT/insets.txt"
for m in "${MODES[@]}"; do
  adb shell am force-stop $PKG
  adb logcat -c
  start=$(date +%s)
  adb shell am start -n $ACT --es capture "$m" --es lang "$LANG_" >/dev/null 2>&1
  sleep ${CAPTURE_WAIT:-15}
  if adb logcat -d -b crash 2>/dev/null | grep -q "FATAL EXCEPTION"; then status=crash
    adb logcat -d -b crash > "$OUT/$m.crash.txt" 2>/dev/null
  else status=ok; fi
  adb exec-out screencap -p > "$OUT/$m.png"
  # The view tree, for the automatic checks (gallery_page.py): which text is
  # on screen and where every tappable element sits.
  adb shell uiautomator dump /sdcard/cap.xml >/dev/null 2>&1 && adb exec-out cat /sdcard/cap.xml > "$OUT/$m.xml"
  printf '%s\t%s\t%s\n' "$m" "$status" "$(( $(date +%s) - start ))" >> "$OUT/result.tsv"
  echo "$m $status"
done

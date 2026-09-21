#!/usr/bin/env bash
# The side-by-side gallery (master plan 1.2): every capture mode on iOS and on
# Android, one row each, with the automatic verdicts beside them.
#
#   scripts/android/gallery.sh <out-dir> [lang=ko] [appearance=light] [mode ...]
#
# iOS runs the REFERENCE build on its own simulator, so nothing another
# session has installed on the everyday simulator is touched:
#   IOS_APP     path to the reference FutureVoice.app (Debug, simulator)
#   IOS_UDID    the gallery simulator (created once: "Gallery iPhone 17 Pro")
# Android runs the `capture` build type (scripts/android/capture-sweep.sh).
#
# Writes <out-dir>/ios/<mode>.jpg, <out-dir>/android/<mode>.jpg,
# <out-dir>/verdicts.tsv and <out-dir>/index.html.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?out dir}; LANG_=${2:-ko}; LOOK=${3:-light}; shift 3 2>/dev/null || shift $#
IOS_APP=${IOS_APP:-/Users/eunggyuelee/FutureVoice-ref54/build/Build/Products/Debug-iphonesimulator/FutureVoice.app}
IOS_UDID=${IOS_UDID:-D3093DB2-AE18-4DE3-9811-D123DF3B2FD2}
IOS_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$IOS_APP/Info.plist")
ROUTER=android/app/src/capture/java/com/roro/futurevoice/capture/CaptureRouter.kt
if [ $# -gt 0 ]; then MODES=("$@"); else
  MODES=($(awk '/val iosModes/,/^    \)/' "$ROUTER" | grep -oE '"[a-z0-9-]+"' | tr -d '"'))
fi
mkdir -p "$OUT/ios" "$OUT/android-raw" "$OUT/android"

# --- iOS -------------------------------------------------------------------
xcrun simctl boot "$IOS_UDID" 2>/dev/null || true
xcrun simctl ui "$IOS_UDID" appearance "$LOOK"
xcrun simctl install "$IOS_UDID" "$IOS_APP"
for m in "${MODES[@]}"; do
  xcrun simctl terminate "$IOS_UDID" "$IOS_BUNDLE" 2>/dev/null
  xcrun simctl launch "$IOS_UDID" "$IOS_BUNDLE" -capture "$m" \
    -futurevoice.nativeLanguage "$LANG_" -AppleLanguages "($LANG_)" >/dev/null 2>&1
  sleep "${IOS_WAIT:-8}"
  xcrun simctl io "$IOS_UDID" screenshot "$OUT/ios/$m.png" >/dev/null 2>&1
  echo "ios $m"
done

# --- Android ---------------------------------------------------------------
if [ "$LOOK" = dark ]; then adb shell cmd uimode night yes >/dev/null; else adb shell cmd uimode night no >/dev/null; fi
scripts/android/capture-sweep.sh "$OUT/android-raw" "$LANG_" "${MODES[@]}"

# --- Verdicts + page --------------------------------------------------------
python3 scripts/android/gallery_page.py "$OUT" "$LANG_" "$LOOK" "${MODES[@]}"
echo "gallery: $OUT/index.html"

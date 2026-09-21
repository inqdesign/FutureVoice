#!/usr/bin/env bash
# Bring the Pixel_9 emulator up (or confirm it is up) and wait for boot.
# The emulator dies between long sessions; every capture run starts here.
set -euo pipefail
ADB=~/Library/Android/sdk/platform-tools/adb
if "$ADB" get-state >/dev/null 2>&1 && [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
  echo "emulator up"; exit 0
fi
rm -f ~/.android/avd/Pixel_9.avd/*.lock 2>/dev/null || true
nohup ~/Library/Android/sdk/emulator/emulator -avd Pixel_9 -no-snapshot-save -no-audio >/dev/null 2>&1 &
"$ADB" wait-for-device
for _ in $(seq 1 100); do
  [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 3
done
"$ADB" shell svc wifi disable || true   # the emulator's wifi breaks DNS; cellular works
echo "emulator booted"

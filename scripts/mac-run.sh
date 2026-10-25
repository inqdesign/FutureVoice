#!/bin/bash
#
# Build the Mac app (Mac Catalyst) and open it.
#
#   ./scripts/mac-run.sh            # Debug: "nawana dev", its own data, beside nothing
#   ./scripts/mac-run.sh release    # Release: the shipping bundle id (real prices,
#                                   # the account's real iCloud container)
#
# Signs with the team's development profile (-allowProvisioningUpdates): the
# Mac build needs a real signature, because CloudKit traps at launch in an app
# without its entitlements. See "The Mac app" in CLAUDE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

config=Debug
[ "${1:-}" = release ] && config=Release

xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project FutureVoice.xcodeproj -scheme FutureVoice -configuration "$config" \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build-mac \
  -allowProvisioningUpdates build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | sort -u

app="build-mac/Build/Products/${config}-maccatalyst/FutureVoice.app"
[ -d "$app" ] || { echo "no app at $app"; exit 1; }
open "$app"

#!/bin/bash
#
# Ship a TestFlight build. Everything Xcode's Archive menu does, minus the
# parts that are easy to get wrong by hand.
#
#   ./scripts/beta.sh              # bump, archive, export, upload
#   ./scripts/beta.sh --no-bump    # re-archive + upload the current build number
#
# Why a script and not fastlane: the Fastfile has the same lane, but fastlane
# 2.x doesn't run on this machine's Ruby 4.0 (default gems were removed and its
# dependency set can't resolve). This needs nothing but Xcode.
#
# Uploading needs NO API key: it goes through the Apple ID already signed into
# Xcode, the same way the Organizer's Distribute button does.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_PLIST="FutureVoice/Resources/Info.plist"
WIDGET_PLIST="FutureVoiceWidget/Info.plist"
ARCHIVE="build/nawana.xcarchive"
EXPORT_DIR="build/export"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
set_plist() { /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1"; }

# --- 1. Build number -------------------------------------------------------
# The widget is an embedded extension: App Store Connect rejects the archive
# unless its CFBundleVersion matches the host app's EXACTLY. Bumping one and
# forgetting the other is the single most common way this fails, ten minutes
# into an upload — so they always move together, here, in one place.
VERSION=$(plist "$APP_PLIST" CFBundleShortVersionString)
BUILD=$(plist "$APP_PLIST" CFBundleVersion)

if [[ "${1:-}" != "--no-bump" ]]; then
  BUILD=$((BUILD + 1))
  set_plist "$APP_PLIST" CFBundleVersion "$BUILD"
  set_plist "$WIDGET_PLIST" CFBundleVersion "$BUILD"
  echo "▸ Build number → $BUILD (app + widget)"
fi

WIDGET_BUILD=$(plist "$WIDGET_PLIST" CFBundleVersion)
if [[ "$BUILD" != "$WIDGET_BUILD" ]]; then
  echo "✗ App build $BUILD ≠ widget build $WIDGET_BUILD. Apple will reject this." >&2
  exit 1
fi
echo "▸ Shipping $VERSION ($BUILD)"

# --- 2. Project ------------------------------------------------------------
# The .xcodeproj is generated from project.yml — archive what the spec says,
# never a stale project someone forgot to regenerate.
command -v xcodegen >/dev/null || { echo "✗ xcodegen not installed" >&2; exit 1; }
xcodegen generate >/dev/null
echo "▸ Project regenerated"

# --- 3. Archive ------------------------------------------------------------
# Release only. Debug installs beside the beta as `nawana dev` (project.yml)
# and must never reach App Store Connect.
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project FutureVoice.xcodeproj \
  -scheme FutureVoice \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  | grep -E '^\*\* |error: ' || true

[[ -d "$ARCHIVE" ]] || { echo "✗ Archive failed" >&2; exit 1; }
echo "▸ Archived"

# --- 4. Export -------------------------------------------------------------
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>PXS8Q4NT67</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  | grep -E '^\*\* |error: ' || true

IPA=$(find "$EXPORT_DIR" -name '*.ipa' | head -1)
[[ -n "$IPA" ]] || { echo "✗ Export produced no .ipa" >&2; exit 1; }
echo "▸ Exported $IPA"

# --- 5. Upload ------------------------------------------------------------
# NO API KEY NEEDED. `-exportArchive` with `destination: upload` hands the
# archive to App Store Connect using the Apple ID already signed into Xcode
# (Settings → Accounts) — the same path the Organizer's Distribute button
# takes. An earlier version of this script gated uploading on an ASC API key
# and, finding none, stopped at the .ipa and told the operator to open
# Transporter by hand. That was never necessary.
#
# The `.ipa` above is still exported first: it is the artifact to re-upload
# from Transporter if this leg fails, and proof of what was signed.
echo "▸ Uploading to App Store Connect…"
cat > build/UploadOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>PXS8Q4NT67</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

if xcodebuild -exportArchive \
     -archivePath "$ARCHIVE" \
     -exportOptionsPlist build/UploadOptions.plist \
     -allowProvisioningUpdates \
     | grep -E '^\*\* |Upload succeeded|error: ' ; then
  echo "✓ $VERSION ($BUILD) uploaded — it appears in TestFlight once Apple finishes processing."
  echo "  Commit the bumped build number:  git add $APP_PLIST $WIDGET_PLIST"
else
  cat <<NOTE

✗ Upload failed, but $VERSION ($BUILD) is built and signed:
  → $IPA

  Most likely the Apple ID in Xcode needs re-authenticating:
  Xcode → Settings → Accounts → sign in again, then re-run:
      ./scripts/beta.sh --no-bump

  Or upload by hand: open Transporter.app and drop that .ipa in.
NOTE
  exit 1
fi

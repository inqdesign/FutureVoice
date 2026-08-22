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

# --- 6. Tell the app a newer build exists ---------------------------------
# `app_release.latest_build` is what a running install compares its own
# CFBundleVersion against (see AppUpdateService). Uploading without moving it
# means the update sheet never appears, so this is not a separate chore — it is
# the last step OF shipping, and it lives here so it cannot be forgotten.
#
# AFTER a successful upload on purpose: announcing a build that failed to
# upload would send every tester to an App Store page that doesn't have it.
#
# Release notes come from the same files App Store Connect gets, so the sheet
# and the store never say different things.
#
# `min_build` is deliberately NOT touched. It locks people out and belongs to a
# decision, not a build: raise it by hand only when the SERVER has moved
# somewhere older clients misreport it.
publish_release_row() {
  local raw token notes_ko notes_en payload
  raw=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null) || {
    echo "  ! Supabase token not in the keychain — app_release NOT updated." >&2
    echo "    Testers will not be offered $VERSION ($BUILD) until you run:" >&2
    echo "    update app_release set latest_build=$BUILD, latest_version='$VERSION' where platform='ios';" >&2
    return 0
  }
  token=$(echo "${raw#go-keyring-base64:}" | base64 -d)
  notes_ko=$(cat fastlane/metadata/ko/release_notes.txt 2>/dev/null || echo "")
  notes_en=$(cat fastlane/metadata/en-US/release_notes.txt 2>/dev/null || echo "")

  payload=$(BUILD="$BUILD" VERSION="$VERSION" NOTES_KO="$notes_ko" NOTES_EN="$notes_en" python3 - <<'PYEOF'
import json, os
# Dollar-quoting, not quote-doubling: the notes are multi-line and the English
# ones contain an apostrophe, which is exactly what silently broke the first
# version of this. The tag is checked against the text so it can never be
# closed early by the content itself.
def q(text: str) -> str:
    tag = "n"
    while f"${tag}$" in text:
        tag += "n"
    return f"${tag}${text}${tag}$"

sql = (
    "update public.app_release set "
    f"latest_build = {int(os.environ['BUILD'])}, "
    f"latest_version = {q(os.environ['VERSION'])}, "
    f"notes_ko = {q(os.environ['NOTES_KO'])}, "
    f"notes_en = {q(os.environ['NOTES_EN'])}, "
    "updated_at = now() where platform = 'ios';"
)
print(json.dumps({"query": sql}))
PYEOF
)
  if curl -sf -X POST \
       "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
       -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
       -d "$payload" >/dev/null; then
    echo "▸ app_release.latest_build → $BUILD (older installs now see the update sheet)"
  else
    echo "  ! app_release update failed — testers will not be offered $BUILD yet." >&2
  fi
}

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
  publish_release_row
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

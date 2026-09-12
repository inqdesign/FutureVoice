#!/bin/bash
#
# Ship a TestFlight build. Everything Xcode's Archive menu does, minus the
# parts that are easy to get wrong by hand.
#
#   ./scripts/beta.sh              # bump, archive, export, upload (TestFlight)
#   ./scripts/beta.sh --no-bump    # re-archive + upload the current build number
#   ./scripts/beta.sh released     # AFTER App Review: tell App Store installs
#                                  # about the build that is now live
#
# Two audiences, two numbers (20260911140000_app_release_testflight): an
# upload moves `latest_testflight_build`; only `released` moves `latest_build`,
# and only once the App Store's own lookup shows the version. App Store users
# were being told about builds the store didn't have yet.
#
# RELEASE NOTES ARE PART OF THE BUILD. fastlane/metadata/*/release_notes.txt is
# what the update sheet shows AND what App Store Connect gets, so the script
# prints them and refuses to archive behind a placeholder ("performance and
# stability") or notes unchanged since the last published build. Write them
# before running this; that is the point at which they get written.
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

SUPABASE_REF=chhzjtigzdotacutwcyo
APP_STORE_ID=6792794655
NOTES_KO_FILE=fastlane/metadata/ko/release_notes.txt
NOTES_EN_FILE=fastlane/metadata/en-US/release_notes.txt

supabase_token() {
  local raw
  raw=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null) || return 1
  echo "${raw#go-keyring-base64:}" | base64 -d
}

# One SQL statement against production, via the Management API. Prints the
# JSON result; non-zero on HTTP failure.
supabase_sql() {
  local token payload
  token=$(supabase_token) || { echo "  ! Supabase token not in the keychain" >&2; return 1; }
  payload=$(SQL="$1" python3 -c 'import json,os; print(json.dumps({"query": os.environ["SQL"]}))')
  curl -sf -X POST "https://api.supabase.com/v1/projects/$SUPABASE_REF/database/query" \
       -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
       -d "$payload"
}

# Dollar-quoted SQL literal for multi-line notes (an apostrophe in the English
# notes is what silently broke the quote-doubling version of this).
sql_text() {
  TEXT="$1" python3 -c '
import os
t = os.environ["TEXT"]; tag = "n"
while f"${tag}$" in t: tag += "n"
print(f"${tag}${t}${tag}$")'
}

# --- 0. `released`: the build is live on the App Store ----------------------
# Run after App Review approves and the version shows on the store. Checks the
# store first — announcing a build the store hasn't got is exactly the bug
# this command exists to end.
if [[ "${1:-}" == "released" ]]; then
  VERSION=$(plist "$APP_PLIST" CFBundleShortVersionString)
  BUILD=${2:-$(plist "$APP_PLIST" CFBundleVersion)}
  live=$(curl -s "https://itunes.apple.com/lookup?id=$APP_STORE_ID&t=$(date +%s)" \
         | python3 -c 'import json,sys; r=json.load(sys.stdin)["results"]; print(r[0]["version"] if r else "")')
  if [[ "$live" != "$VERSION" ]]; then
    echo "✗ App Store shows version '${live:-none}', this tree is $VERSION ($BUILD)." >&2
    echo "  Not released yet, or the lookup cache is behind (it can lag ~an hour). Try again later." >&2
    exit 1
  fi
  notes_ko=$(cat "$NOTES_KO_FILE"); notes_en=$(cat "$NOTES_EN_FILE")
  supabase_sql "update public.app_release set latest_build = $BUILD, latest_version = $(sql_text "$VERSION"), notes_ko = $(sql_text "$notes_ko"), notes_en = $(sql_text "$notes_en"), updated_at = now() where platform = 'ios';" >/dev/null \
    && echo "✓ app_release.latest_build → $BUILD ($VERSION). App Store installs now see the update sheet." \
    || { echo "✗ app_release update failed" >&2; exit 1; }
  exit 0
fi

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

# --- 1a. Release notes -----------------------------------------------------
# Shown to every install behind this build (UpdateAvailableSheet) and pasted
# into App Store Connect. A placeholder here is a placeholder on both. Checked
# BEFORE the ten-minute archive so a bad note costs seconds, not a rebuild.
notes_ko=$(cat "$NOTES_KO_FILE" 2>/dev/null || true)
notes_en=$(cat "$NOTES_EN_FILE" 2>/dev/null || true)
if [[ -z "$notes_ko" || -z "$notes_en" ]]; then
  echo "✗ Release notes missing ($NOTES_KO_FILE / $NOTES_EN_FILE). Write them first." >&2
  exit 1
fi
if grep -qiE '성능과 안정성|성능 및 안정성|performance and stability|bug fixes and improvements' \
     "$NOTES_KO_FILE" "$NOTES_EN_FILE"; then
  echo "✗ Release notes are the generic placeholder. Say what changed — that is what the update sheet shows." >&2
  exit 1
fi
if prev=$(supabase_sql "select notes_ko, latest_version, latest_build, latest_testflight_build from public.app_release where platform = 'ios'" 2>/dev/null); then
  if PREV="$prev" NOTES="$notes_ko" python3 -c '
import json, os, sys
row = json.loads(os.environ["PREV"])[0]
same = (row.get("notes_ko") or "").strip() == os.environ["NOTES"].strip()
sys.exit(0 if same else 1)'; then
    if [[ "${FORCE_SAME_NOTES:-}" != "1" ]]; then
      echo "✗ Release notes are unchanged since the last published build. Edit them, or FORCE_SAME_NOTES=1 to re-ship the same notes." >&2
      exit 1
    fi
  fi
fi
echo "▸ Release notes ($VERSION):"
sed 's/^/    /' "$NOTES_KO_FILE"
echo
if [[ -t 0 && "${YES:-}" != "1" ]]; then
  read -r -p "  Ship with these notes? [y/N] " ok
  [[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "  Stopped. Edit the notes and re-run."; exit 1; }
fi

# --- 1b. Upload credentials ------------------------------------------------
# Uploading through the Apple ID signed into Xcode works right up until the
# session token in the login keychain disappears — which is not a rare event
# on this machine: an EAS/Expo build in another project inserts its own
# temporary keychain into the search list and takes Xcode's token with it when
# it cleans up. The archive then builds and signs perfectly and the upload
# dies on "Failed to Use Accounts" (2026-09-07, and not the first time).
#
# An App Store Connect API key has no session to lose. Drop the .p8 in
# ~/.appstoreconnect/private_keys/ (the path Apple's own tools search) and put
# the issuer id beside it in `issuer_id`, or export ASC_KEY_ID/ASC_ISSUER_ID.
# With no key present nothing changes: the Apple ID path runs exactly as
# before.
AUTH=()
KEY_DIR="$HOME/.appstoreconnect/private_keys"
ASC_KEY_ID="${ASC_KEY_ID:-}"
# Plain `if`, not `${X:-$( [[ -f … ]] && … )}`: with `set -e` the failed
# `[[ -f ]]` inside that substitution exits the whole script — silently, right
# after "Shipping …" — on every machine WITHOUT a key (2026-09-08).
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
if [[ -z "$ASC_ISSUER_ID" && -f "$HOME/.appstoreconnect/issuer_id" ]]; then
  ASC_ISSUER_ID=$(tr -d '[:space:]' < "$HOME/.appstoreconnect/issuer_id")
fi
if [[ -z "$ASC_KEY_ID" ]]; then
  KEY_FILE=$(ls "$KEY_DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)
  if [[ -n "$KEY_FILE" ]]; then
    ASC_KEY_ID=$(basename "$KEY_FILE" .p8); ASC_KEY_ID=${ASC_KEY_ID#AuthKey_}
  fi
fi
if [[ -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" && -f "$KEY_DIR/AuthKey_$ASC_KEY_ID.p8" ]]; then
  AUTH=(-authenticationKeyPath "$KEY_DIR/AuthKey_$ASC_KEY_ID.p8"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "▸ Using App Store Connect API key $ASC_KEY_ID"
fi

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
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
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
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
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
#
# TESTFLIGHT ONLY. This moves `latest_testflight_build` and the notes; App
# Store installs read `latest_build`, which `./scripts/beta.sh released` sets
# once App Review has actually put the build on the store.
publish_release_row() {
  if supabase_sql "update public.app_release set latest_testflight_build = $BUILD, latest_version = $(sql_text "$VERSION"), notes_ko = $(sql_text "$notes_ko"), notes_en = $(sql_text "$notes_en"), updated_at = now() where platform = 'ios';" >/dev/null; then
    echo "▸ app_release.latest_testflight_build → $BUILD (TestFlight installs now see the update sheet)"
    echo "  When App Review approves and the store shows $VERSION:  ./scripts/beta.sh released"
  else
    echo "  ! app_release update failed — testers will not be offered $BUILD yet. Run by hand:" >&2
    echo "    update app_release set latest_testflight_build=$BUILD, latest_version='$VERSION' where platform='ios';" >&2
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
     -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
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

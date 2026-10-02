#!/usr/bin/env bash
# Moves the update sheet the moment a build goes live on the App Store, so
# `./scripts/beta.sh released` is never again a step someone has to remember.
#
# It was forgotten twice: 2026-09-16, and again for 1.1.2 AND 1.1.3 — the
# store served 1.1.3 for a day while `app_release.latest_build` still said 62,
# so nobody behind it was told to update, and a learner on 1.1.2 kept hearing
# voicemails without the sentence pauses 1.1.3 shipped.
#
# Every run: ask App Store Connect which build is READY_FOR_SALE
# (scripts/asc-live-build.py — the iTunes lookup knows the version, never the
# build), compare with `app_release.latest_build`, and if the store is ahead
# run `beta.sh released <build>` with that version and ITS store notes — the
# same command a person would run, community post included. Idempotent: a
# run with nothing new does one ASC call and one SELECT.
#
# Runs from launchd every 30 min (scripts/release-watch.plist).
set -euo pipefail
cd "$(dirname "$0")/.."

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
read -r version build < <(python3 scripts/asc-live-build.py "$tmp/ko.txt" "$tmp/en.txt") \
  || { log "ASC lookup failed"; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { log "odd build '$build' for $version"; exit 1; }

raw=$(security find-generic-password -s "Supabase CLI" -w) || { log "no Supabase token"; exit 1; }
token=$(echo "${raw#go-keyring-base64:}" | base64 -d)
current=$(curl -sf -X POST "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
  -d '{"query":"select latest_build from public.app_release where platform = '"'ios'"'"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["latest_build"])') \
  || { log "app_release read failed"; exit 1; }

if (( build <= current )); then exit 0; fi

log "store is on $version ($build), update sheet on $current → releasing"
RELEASE_VERSION="$version" NOTES_KO_FILE="$tmp/ko.txt" NOTES_EN_FILE="$tmp/en.txt" \
  ./scripts/beta.sh released "$build"

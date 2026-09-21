#!/usr/bin/env bash
# What an iOS release changed that Android may owe — the list the master plan's
# 2단계 is built from when the baseline moves.
#
#   scripts/android/ios-delta.sh <from-release-commit> <to-release-commit>
#
# Every iOS commit that touches the app, the server or the gateway is listed
# under one of three headings, read off its `Android:` trailer:
#   옮길 것   — the trailer says what to port
#   해당 없음 — `Android: n/a`
#   분류 안 됨 — no trailer; someone has to read it (the old way)
# Release/i18n/admin chores are skipped: they never carry Android work.
set -euo pipefail
from=${1:?from commit}; to=${2:?to commit}
paths=(FutureVoice supabase gateway)

port=(); na=(); unclassified=()
while IFS= read -r sha; do
  subject=$(git log -1 --format=%s "$sha")
  case "$subject" in chore\(release\)*|chore\(i18n\)*|*\(admin\)*) continue ;; esac
  trailer=$(git log -1 --format='%(trailers:key=Android,valueonly)' "$sha" | sed '/^$/d' | head -1)
  line="$sha $subject"
  if [[ -z "$trailer" ]]; then unclassified+=("$line")
  elif [[ "$(echo "$trailer" | tr 'A-Z' 'a-z')" == "n/a" ]]; then na+=("$line")
  else port+=("$line"$'\n      → '"$trailer"); fi
done < <(git log --no-merges --reverse --format=%h "$from..$to" -- "${paths[@]}")

section() { local title=$1; shift; echo "## $title ($#)"; for l in "$@"; do echo "- $l"; done; echo; }
section "옮길 것" "${port[@]+"${port[@]}"}"
section "분류 안 됨 — 읽어야 함" "${unclassified[@]+"${unclassified[@]}"}"
section "해당 없음" "${na[@]+"${na[@]}"}"

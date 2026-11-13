#!/usr/bin/env bash
# Puts the server half of Simplified Chinese live (iOS 0197dcbc, Android 471575fd).
#
#   scripts/deploy-chinese-server.sh            # checks, shows what ships, asks, deploys
#   scripts/deploy-chinese-server.sh --dry-run  # checks and shows, deploys nothing
#
# What ships, all from the COMMITTED tree (HEAD), never the working tree, so a
# session's uncommitted edits can't ride along:
#   1. Edge functions `pronunciation` (zh-CN, without IPA) and `tts` + its old
#      name `elevenlabs-tts` (the shared preset map: Chinese slot voices).
#   2. The realtime gateway (gateway/src/presets.ts: the same map for calls).
#      A gateway deploy resets every live call, so it refuses while anyone is
#      talking (usage_ledger talk_time in the last 5 minutes) and waits.
#
# HEAD also carries French (ea09ee2a) and anything else committed to those
# files since their last deploy; the script lists those commits before asking.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="chhzjtigzdotacutwcyo"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
NODE22="/opt/homebrew/opt/node@22/bin"
FUNCTIONS=(pronunciation tts elevenlabs-tts)

say() { printf '\n== %s\n' "$*"; }

# --- Supabase management token (same as every other prod script) ----------
RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
sql() {
  curl -s -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}
live_calls() {
  sql "select count(distinct user_id) as n from usage_ledger where action='talk_time' and created_at > now() - interval '5 minutes'" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r[0]["n"] if isinstance(r,list) else "ERR "+str(r))'
}

# --- 1. The commit being shipped must contain the Chinese work ---------------
cd "$ROOT"
HEAD_SHA=$(git rev-parse --short HEAD)
git merge-base --is-ancestor 0197dcbc HEAD || { echo "HEAD ($HEAD_SHA) does not contain the Chinese commit 0197dcbc."; exit 1; }
grep -q 'zh: "zh-CN"' <(git show HEAD:supabase/functions/pronunciation/index.ts) || { echo "pronunciation at HEAD has no zh-CN"; exit 1; }
grep -q '^  zh: \[' <(git show HEAD:gateway/src/presets.ts) || { echo "gateway presets at HEAD have no zh"; exit 1; }

say "Shipping commit $HEAD_SHA"
say "Commits since 2026-11-13 14:48 UTC (last gateway deploy) touching what ships:"
git log --since='2026-11-13T14:48:00Z' --format='  %h %ad %s' --date=format:'%m-%d %H:%M' -- \
  gateway/ supabase/functions/pronunciation supabase/functions/tts supabase/functions/_shared

# --- 2. Export HEAD (not the working tree) -----------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git archive HEAD supabase gateway | tar -x -C "$TMP"
ln -s "$ROOT/gateway/node_modules" "$TMP/gateway/node_modules"

N=$(live_calls)
say "People in a call right now (last 5 min): $N"

if [ "$DRY" = 1 ]; then
  say "Dry run: nothing deployed."
  exit 0
fi

printf '\nDeploy edge functions (%s) and the gateway from %s? [y/N] ' "${FUNCTIONS[*]}" "$HEAD_SHA"
read -r ok; [ "$ok" = "y" ] || { echo "Stopped."; exit 1; }

# --- 3. Edge functions (no call is dropped by these) ------------------------
for f in "${FUNCTIONS[@]}"; do
  say "Deploying edge function $f"
  supabase functions deploy "$f" --project-ref "$PROJECT_REF" --workdir "$TMP" --use-api
done

# --- 4. Gateway, only when nobody is talking --------------------------------
while true; do
  N=$(live_calls)
  case "$N" in
    0) break ;;
    ERR*) echo "Could not check live calls: $N"; exit 1 ;;
    *) echo "  $N in a call; waiting 60 s (Ctrl-C to stop; edge functions are already live)"; sleep 60 ;;
  esac
done
say "Nobody in a call. Deploying the gateway"
( cd "$TMP/gateway" && PATH="$NODE22:$PATH" npx wrangler deploy )

say "Done: pronunciation, tts, elevenlabs-tts and the gateway are live from $HEAD_SHA."

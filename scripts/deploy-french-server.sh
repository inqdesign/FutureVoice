#!/usr/bin/env bash
# Puts the server half of French as a learning language live
# (iOS ea09ee2a + 625f56ba, Android aa482542).
#
#   scripts/deploy-french-server.sh            # checks, shows what ships, asks, deploys
#   scripts/deploy-french-server.sh --dry-run  # checks and shows, deploys nothing
#
# What ships, all from the COMMITTED tree (HEAD), never the working tree, so a
# session's uncommitted edits can't ride along:
#   1. Migration 20261113160000_speech_challenges_french.sql: French speech
#      Season 1 and its two challenges (the bundled sample and the ageing
#      study). Skipped when it is already recorded.
#   2. Edge functions:
#        tts, voice-remix (+ their old names elevenlabs-tts, elevenlabs-voice-remix):
#          the Parisian / Canadian accents and the French preset voices
#        voice-clone (+ elevenlabs-voice-clone), speech-reference: same shared file
#        pronunciation: Azure fr-FR / fr-CA
#        session-summary: Android's summary, the spoken-French line
#   3. The realtime gateway (presets.ts, cartesia-tts.ts: the French voices
#      and accents in calls). A gateway deploy resets every live call, so it
#      refuses while anyone is talking (usage_ledger talk_time in the last
#      5 minutes) and waits.
#
# HEAD also carries whatever else was committed to those files since their
# last deploy (Chinese, for one); the script lists those commits before asking.
# Running scripts/deploy-chinese-server.sh as well is fine: same HEAD, same files.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="chhzjtigzdotacutwcyo"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
NODE22="/opt/homebrew/opt/node@22/bin"
MIGRATION="supabase/migrations/20261113160000_speech_challenges_french.sql"
FUNCTIONS=(tts elevenlabs-tts voice-remix elevenlabs-voice-remix voice-clone elevenlabs-voice-clone
           speech-reference pronunciation session-summary)

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
french_challenges() {
  sql "select count(*) as n from speech_challenges where language='fr'" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r[0]["n"] if isinstance(r,list) else "ERR "+str(r))'
}

# --- 1. The commit being shipped must contain the French work ----------------
cd "$ROOT"
HEAD_SHA=$(git rev-parse --short HEAD)
for c in ea09ee2a 625f56ba; do
  git merge-base --is-ancestor "$c" HEAD || { echo "HEAD ($HEAD_SHA) does not contain $c."; exit 1; }
done
grep -q 'fr: "fr-FR"' <(git show HEAD:supabase/functions/pronunciation/index.ts) || { echo "pronunciation at HEAD has no fr-FR"; exit 1; }
grep -q '^  fr: \[' <(git show HEAD:gateway/src/presets.ts) || { echo "gateway presets at HEAD have no fr"; exit 1; }
grep -q '"parisian": "fr"' <(git show HEAD:gateway/src/cartesia-tts.ts) || { echo "gateway accents at HEAD have no parisian"; exit 1; }
grep -q '"parisian": "fr"' <(git show HEAD:supabase/functions/_shared/cartesia.ts) || { echo "edge accents at HEAD have no parisian"; exit 1; }
git cat-file -e "HEAD:$MIGRATION" || { echo "$MIGRATION is not committed"; exit 1; }

say "Shipping commit $HEAD_SHA"
say "Commits on 2026-11-13 or later touching what ships:"
git log --since='2026-11-13T00:00:00Z' --format='  %h %ad %s' --date=format:'%m-%d %H:%M' -- \
  gateway/src supabase/functions/_shared "${FUNCTIONS[@]/#/supabase/functions/}" "$MIGRATION"

# --- 2. Export HEAD (not the working tree) -----------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git archive HEAD supabase gateway scripts/apply-migration.sh | tar -x -C "$TMP"
ln -s "$ROOT/gateway/node_modules" "$TMP/gateway/node_modules"

FR=$(french_challenges)
N=$(live_calls)
say "French speech challenges on the server now: $FR (2 once the migration is in)"
say "People in a call right now (last 5 min): $N"

if [ "$DRY" = 1 ]; then
  say "Dry run: nothing deployed."
  exit 0
fi

printf '\nApply the migration, deploy edge functions (%s) and the gateway from %s? [y/N] ' "${FUNCTIONS[*]}" "$HEAD_SHA"
read -r ok; [ "$ok" = "y" ] || { echo "Stopped."; exit 1; }

# --- 3. Migration (no call is dropped by this) ------------------------------
if [ "$FR" = "0" ]; then
  say "Applying $MIGRATION"
  ( cd "$TMP" && bash scripts/apply-migration.sh "$MIGRATION" )
  FR=$(french_challenges)
  [ "$FR" = "2" ] || { echo "Expected 2 French challenges after the migration, found $FR. Stopping."; exit 1; }
else
  say "French challenges already on the server ($FR): migration skipped"
fi

# --- 4. Edge functions (no call is dropped by these) ------------------------
for f in "${FUNCTIONS[@]}"; do
  say "Deploying edge function $f"
  supabase functions deploy "$f" --project-ref "$PROJECT_REF" --workdir "$TMP" --use-api
done

# --- 5. Gateway, only when nobody is talking --------------------------------
while true; do
  N=$(live_calls)
  case "$N" in
    0) break ;;
    ERR*) echo "Could not check live calls: $N"; exit 1 ;;
    *) echo "  $N in a call; waiting 60 s (Ctrl-C to stop; the rest is already live)"; sleep 60 ;;
  esac
done
say "Nobody in a call. Deploying the gateway"
( cd "$TMP/gateway" && PATH="$NODE22:$PATH" npx wrangler deploy )

say "Done: French migration, edge functions and the gateway are live from $HEAD_SHA."

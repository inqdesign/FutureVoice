#!/usr/bin/env bash
# Archive every learner's ORIGINAL clone recording into its own folder.
#
# The source is the private `voice-originals` bucket: `elevenlabs-voice-clone`
# (Cartesia only since 2026-10-15, the endpoint keeps its name) writes the
# multipart takes it receives straight into it, so this is the EXACT
# recording, in the format the phone sent. `voice_clones.original_path` names
# the folder. KEPT SERVER-SIDE FOR 24h ONLY (`purge-voice-originals`), so this
# poller has a day to collect it and a Mac asleep for a weekend still misses
# those clones. (Until 2026-10-16 an ElevenLabs sample was the fallback; with
# ElevenLabs gone there is no second copy anywhere.)
#
#   ~/Desktop/beta audio/voices/<voice name>-<voice_id>/
#       original-NN.wav                  the recording as the phone sent it
#       .done                            archived — never re-fetched
#       .missing                         no original on the server (purged or never kept)
#
# Rows come from prod `voice_clones` (Management API, keychain token — see
# memory/prod-db-query-access.md).
# Idempotent, so it is safe to run every few minutes from launchd
# (scripts/voice-archive.plist) — that is how a NEW voice gets archived before
# the learner replaces it.
#
#   scripts/voice-archive.sh                 # everything not yet archived
#   scripts/voice-archive.sh <voice_id>...   # just these
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${VOICE_ARCHIVE_DIR:-$HOME/Desktop/beta audio/voices}"
PROJECT_REF="chhzjtigzdotacutwcyo"
LOG="$OUT/archive.log"
mkdir -p "$OUT"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

RAW="$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null)" || { log "no Supabase CLI token in keychain"; exit 1; }
TOKEN="$(printf '%s' "${RAW#go-keyring-base64:}" | base64 -d)"

# Storage needs a project key, not the Management token. Revealed at run time
# from the same keychain credential rather than written to disk — there is
# then no second secret to leak, and rotating the key needs no edit here.
SUPABASE_URL="https://$PROJECT_REF.supabase.co"
SERVICE_KEY="$(curl -s "https://api.supabase.com/v1/projects/$PROJECT_REF/api-keys?reveal=true" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c 'import json,sys
try:
    for r in json.load(sys.stdin):
        if r.get("name") == "service_role": print(r.get("api_key") or ""); break
except Exception: pass')"
[ -n "$SERVICE_KEY" ] || { log "no service_role key"; exit 1; }

# ---- 1. the voices to archive ------------------------------------------
if [ $# -gt 0 ]; then
  IDS="$(printf "'%s'," "$@")"; IDS="${IDS%,}"
  WHERE="where v.elevenlabs_voice_id in ($IDS)"
else
  WHERE=""
fi
SQL="select v.elevenlabs_voice_id as voice_id, coalesce(v.name, 'Future') as name, v.created_at::text as created_at, v.user_id::text as user_id, coalesce(v.original_path, '') as original_path, (v.created_at < now() - interval '25 hours')::text as stale from voice_clones v $WHERE order by v.created_at"
ROWS="$(curl -s -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$SQL")")"
case "$ROWS" in \[*) ;; *) log "voice_clones query failed: ${ROWS:0:300}"; exit 1;; esac

# ---- 2. one folder per voice -------------------------------------------
NEW=0
while IFS=$'\t' read -r VOICE_ID NAME CREATED USER_ID ORIGINAL_PATH STALE; do
  [ -n "$VOICE_ID" ] || continue
  SAFE_NAME="$(printf '%s' "$NAME" | tr '/:' '__' | tr -s ' ' ' ')"
  DIR="$OUT/$SAFE_NAME-$VOICE_ID"
  if [ -e "$DIR/.done" ]; then continue; fi
  mkdir -p "$DIR"

  # ---- 2a. the original the server kept --------------------------------
  if [ -n "$ORIGINAL_PATH" ] && [ -n "$SERVICE_KEY" ]; then
    GOT=0
    while IFS= read -r OBJ; do
      [ -n "$OBJ" ] || continue
      DEST="$DIR/original-$OBJ"
      S="$(curl -s -o "$DEST" -w '%{http_code}' \
        "$SUPABASE_URL/storage/v1/object/voice-originals/$ORIGINAL_PATH/$OBJ" \
        -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY")"
      if [ "$S" = "200" ]; then GOT=$((GOT+1)); else rm -f "$DEST"; fi
    done < <(curl -s -X POST "$SUPABASE_URL/storage/v1/object/list/voice-originals" \
      -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
      -H "Content-Type: application/json" \
      --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"prefix": sys.argv[1], "limit": 100}))' "$ORIGINAL_PATH")" \
      | python3 -c 'import json,sys
try:
    for o in json.load(sys.stdin):
        n = o.get("name")
        if n and o.get("id"): print(n)
except Exception: pass')

    if [ "$GOT" -gt 0 ]; then
      rm -f "$DIR/.missing"
      printf '%s\tuser %s\tcreated %s\tsource original (%s file(s))\n' \
        "$(date -u +%FT%TZ)" "$USER_ID" "$CREATED" "$GOT" > "$DIR/.done"
      NEW=$((NEW+1)); log "SAVED   $SAFE_NAME $VOICE_ID → $DIR (original, $GOT file(s))"
      continue
    fi
  fi

  # Nothing on the server: purged after 24h, or a clone from before the
  # bucket existed. Only rows from the last day can still appear, so retry
  # those; anything older is remembered as missing.
  if [ "$STALE" = "t" ]; then
    [ -e "$DIR/.missing" ] || { echo "no original on the server" > "$DIR/.missing"; log "MISSING $SAFE_NAME $VOICE_ID (created $CREATED)"; }
  fi
done < <(python3 -c '
import json,sys
for r in json.loads(sys.argv[1]):
    print("\t".join([r["voice_id"], r["name"], r["created_at"], r["user_id"], r.get("original_path") or "", "t" if str(r.get("stale")).lower() in ("true","t") else "f"]))' "$ROWS")

[ "$NEW" -gt 0 ] && log "archived $NEW new voice(s)"
exit 0

#!/usr/bin/env bash
# Archive every learner's ORIGINAL clone recording into its own folder.
#
# We never keep the recording ourselves (elevenlabs-voice-clone forwards it
# straight to ElevenLabs), so the only copy off the phone is the sample
# ElevenLabs holds on the voice — and a voice is deleted the moment the
# learner re-records or picks an accent. This pulls each sample down once,
# while it still exists, into
#
#   ~/Desktop/beta audio/voices/<voice name>-<voice_id>/
#       voice.json                       ElevenLabs voice metadata
#       <original file name>.mp3         the recording (ElevenLabs serves mp3)
#       .done                            archived — never re-fetched
#       .missing                         voice already gone upstream
#
# Rows come from prod `voice_clones` (Management API, keychain token — see
# memory/prod-db-query-access.md); the ElevenLabs key from gateway/.dev.vars.
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

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || { log "no ElevenLabs key (gateway/.dev.vars or ELEVENLABS_API_KEY)"; exit 1; }

RAW="$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null)" || { log "no Supabase CLI token in keychain"; exit 1; }
TOKEN="$(printf '%s' "${RAW#go-keyring-base64:}" | base64 -d)"

# ---- 1. the voices to archive ------------------------------------------
if [ $# -gt 0 ]; then
  IDS="$(printf "'%s'," "$@")"; IDS="${IDS%,}"
  WHERE="where v.elevenlabs_voice_id in ($IDS)"
else
  WHERE=""
fi
SQL="select v.elevenlabs_voice_id as voice_id, coalesce(v.name, 'Future') as name, v.created_at::text as created_at, v.user_id::text as user_id from voice_clones v $WHERE order by v.created_at"
ROWS="$(curl -s -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$SQL")")"
case "$ROWS" in \[*) ;; *) log "voice_clones query failed: ${ROWS:0:300}"; exit 1;; esac

# ---- 2. one folder per voice -------------------------------------------
NEW=0
while IFS=$'\t' read -r VOICE_ID NAME CREATED USER_ID; do
  [ -n "$VOICE_ID" ] || continue
  SAFE_NAME="$(printf '%s' "$NAME" | tr '/:' '__' | tr -s ' ' ' ')"
  DIR="$OUT/$SAFE_NAME-$VOICE_ID"
  if [ -e "$DIR/.done" ] || [ -e "$DIR/.missing" ]; then continue; fi
  mkdir -p "$DIR"

  META="$DIR/voice.json"
  STATUS="$(curl -s -o "$META" -w '%{http_code}' "https://api.elevenlabs.io/v1/voices/$VOICE_ID" -H "xi-api-key: $KEY")"
  if [ "$STATUS" != "200" ]; then
    # Gone upstream (re-record / accent pick deletes the old voice) — remember
    # so the next run doesn't ask again. Any other status: leave it for retry.
    if [ "$STATUS" = "404" ] || [ "$STATUS" = "400" ] || [ "$STATUS" = "422" ]; then
      printf 'HTTP %s\n' "$STATUS" > "$DIR/.missing"; log "MISSING $SAFE_NAME $VOICE_ID (HTTP $STATUS, created $CREATED)"
    else
      log "RETRY   $SAFE_NAME $VOICE_ID (HTTP $STATUS)"
    fi
    rm -f "$META"; continue
  fi

  OK=1
  while IFS=$'\t' read -r SAMPLE_ID FILE_NAME; do
    [ -n "$SAMPLE_ID" ] || continue
    DEST="$DIR/${FILE_NAME:-$SAMPLE_ID.mp3}"
    S="$(curl -s -o "$DEST" -w '%{http_code}' "https://api.elevenlabs.io/v1/voices/$VOICE_ID/samples/$SAMPLE_ID/audio" -H "xi-api-key: $KEY")"
    if [ "$S" != "200" ]; then rm -f "$DEST"; OK=0; log "RETRY   $SAFE_NAME $VOICE_ID sample $SAMPLE_ID (HTTP $S)"; fi
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for s in d.get("samples") or []:
    print(s["sample_id"] + "\t" + (s.get("file_name") or ""))' "$META")

  if [ "$OK" = 1 ]; then
    printf '%s\tuser %s\tcreated %s\n' "$(date -u +%FT%TZ)" "$USER_ID" "$CREATED" > "$DIR/.done"
    NEW=$((NEW+1)); log "SAVED   $SAFE_NAME $VOICE_ID → $DIR"
  fi
done < <(python3 -c '
import json,sys
for r in json.loads(sys.argv[1]):
    print("\t".join([r["voice_id"], r["name"], r["created_at"], r["user_id"]]))' "$ROWS")

[ "$NEW" -gt 0 ] && log "archived $NEW new voice(s)"
exit 0

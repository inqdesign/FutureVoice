#!/usr/bin/env bash
# List the ElevenLabs generation history for one voice — what was said, by
# which model, when. The answer to "why are there so many entries in the
# dashboard": every item carries its purpose-revealing model
# (eleven_multilingual_v2 = greeting / comparison / scene, eleven_turbo_v2_5
# = opener prewarm / talk / daily call) and the first words of the text.
#
# Same key rules as voice-sample.sh (gateway/.dev.vars, else the env var).
#
#   scripts/eleven-history.sh <elevenlabs_voice_id> [count=50]
#   scripts/eleven-history.sh all [count=50]          # every voice
set -euo pipefail

VOICE_ID="${1:?usage: eleven-history.sh <elevenlabs_voice_id|all> [count]}"
COUNT="${2:-50}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or fill gateway/.dev.vars" >&2; exit 1; }

URL="https://api.elevenlabs.io/v1/history?page_size=$COUNT"
[ "$VOICE_ID" != "all" ] && URL="$URL&voice_id=$VOICE_ID"

curl -sf "$URL" -H "xi-api-key: $KEY" | python3 -c '
import json, sys, datetime
d = json.load(sys.stdin)
items = d.get("history") or []
print(f"{len(items)} items (has_more={d.get(\"has_more\")})")
for h in items:
    t = datetime.datetime.fromtimestamp(h["date_unix"], datetime.timezone.utc).strftime("%H:%M:%S")
    chars = h.get("character_count_change_to", 0) - h.get("character_count_change_from", 0)
    text = (h.get("text") or "").replace("\n", " ")[:60]
    print(f"{t}Z  {h.get(\"voice_name\",\"\")[:14]:14} {h.get(\"voice_id\",\"\")}  {h.get(\"model_id\",\"\"):22} {chars:4}ch  {text}")
'

#!/usr/bin/env bash
# Download the ORIGINAL recording(s) behind an ElevenLabs voice clone.
#
# We never keep the learner's recording ourselves — elevenlabs-voice-clone
# forwards the multipart body straight to /v1/voices/add — so the only copy
# outside the phone is the sample ElevenLabs stores on the voice. This pulls
# it back down.
#
# The app holds NO provider key (Config/FutureVoice.xcconfig leaves
# ELEVENLABS_API_KEY empty — every call goes through the edge functions), so
# the account key is read from gateway/.dev.vars (the gateway Worker's local
# secrets, gitignored), else $ELEVENLABS_API_KEY, else ~/keys/elevenlabs.txt.
#
#   scripts/voice-sample.sh <elevenlabs_voice_id> [out_dir]
#
# Find the voice id in prod: select elevenlabs_voice_id from voice_clones
# where name ilike '%<name>%' and is_active.
set -euo pipefail

VOICE_ID="${1:?usage: voice-sample.sh <elevenlabs_voice_id> [out_dir]}"
OUT="${2:-$HOME/Desktop/beta audio/$VOICE_ID}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/Config/FutureVoice.xcconfig")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

mkdir -p "$OUT"
META="$OUT/voice.json"
STATUS="$(curl -s -o "$META" -w '%{http_code}' "https://api.elevenlabs.io/v1/voices/$VOICE_ID" -H "xi-api-key: $KEY")"
if [ "$STATUS" != "200" ]; then
  echo "ElevenLabs returned HTTP $STATUS for voice $VOICE_ID:" >&2
  cat "$META" >&2; echo >&2
  rm -f "$META"
  exit 1
fi

python3 - "$META" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"voice: {d.get('name')}  ({d.get('category')})")
for s in d.get("samples") or []:
    print(f"  sample {s['sample_id']}  {s.get('file_name')}  {s.get('duration_secs')}s  {s.get('mime_type')}")
EOF

python3 -c 'import json,sys; [print(s["sample_id"], s.get("file_name") or (s["sample_id"]+".wav")) for s in (json.load(open(sys.argv[1])).get("samples") or [])]' "$META" \
| while read -r SAMPLE_ID FILE_NAME; do
    DEST="$OUT/$FILE_NAME"
    curl -sf "https://api.elevenlabs.io/v1/voices/$VOICE_ID/samples/$SAMPLE_ID/audio" -H "xi-api-key: $KEY" -o "$DEST"
    echo "saved $DEST"
    afplay "$DEST" || open "$DEST"
  done

#!/usr/bin/env bash
# Audio for the carousel's "why your own voice" card, in three beats:
#   1. the founder's real voice — one line cut from the website recording
#   2. a stock American voice (Mark, one of the app's presets) reading the English line
#   3. the founder's clone reading the same English line
# Beats 2 and 3 are made TAKES times each so the founder picks by ear.
# Production voice settings and speed, turbo — the model every call runs on.
#
#   scripts/marketing/voice-compare.sh [out_dir]
#   TAKES=3  LINE="..."  SPEED=0.9
#
# Founder decision 2026-10-12: the founder's own voice and clone, public.
# Never point this at a learner's voice. Run it yourself — it spends credits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$HOME/Desktop/beta audio/marketing-voice-compare}"
CLONE="31fQLzd8XYV6VPyG3GWA"          # the founder's clone
NATIVE="UgBBYS2sOqTuMpoF3BR0"         # Mark (American, male) — VoicePreset.catalog
LINE="${LINE:-Now I can say what I mean, the way I mean it.}"
SPEED="${SPEED:-0.9}"
TAKES="${TAKES:-3}"
SRC="$HOME/Desktop/beta audio/nawana-web-audio/ko-02-출시본.mp3"
FROM="69.53"; TO="75.30"              # "다만 제가 하고 싶었던 말을, 하고 싶었던 방식으로는 못 했어요."

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

mkdir -p "$OUT"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
ffmpeg -v error -y -ss "$FROM" -to "$TO" -i "$SRC" -af "afade=t=in:d=0.05,afade=t=out:st=$(python3 -c "print(round($TO-$FROM-0.15,2))"):d=0.15" "$OUT/1-my-voice.mp3"
echo "1-my-voice.mp3  (cut ${FROM}-${TO})"

BODY="$(python3 - "$LINE" "$SPEED" <<'PY'
import json, sys
text, speed = sys.argv[1:3]
settings = {"stability": 0.55, "similarity_boost": 0.90, "style": 0, "use_speaker_boost": True}
s = float(speed)
if 0.7 <= s <= 1.2: settings["speed"] = s
print(json.dumps({"text": text, "model_id": "eleven_turbo_v2_5", "voice_settings": settings}))
PY
)"

for t in $(seq 1 "$TAKES"); do
  for side in native clone; do
    case "$side" in native) v="$NATIVE"; n=2;; clone) v="$CLONE"; n=3;; esac
    f="$OUT/$n-$side-take$t.mp3"
    code=$(curl -s -o "$f" -w '%{http_code}' "https://api.elevenlabs.io/v1/text-to-speech/$v" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" -d "$BODY")
    if [ "$code" != "200" ]; then echo "  ! $side take $t → HTTP $code"; head -c 300 "$f"; echo; rm -f "$f"; continue; fi
    echo "$(basename "$f")"
  done
done

echo
echo "Listen: 1 → 2 → 3. Tell me which native take and which clone take to use."
echo "  open \"$OUT\""

#!/usr/bin/env bash
# "!" makes the voice SHOUT — reported 2026-10-05: a line with an exclamation
# mark jumps in volume and sounds like yelling. A/B by ear: the same line with
# its "!" kept (what ships) and turned into "." (what the fix would send),
# production settings, speed 0.9, Korean pinned for Hangul lines.
#
#   scripts/tts-exclaim-probe.sh [voice_id] [out_dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VOICE_ID="${1:-31fQLzd8XYV6VPyG3GWA}"
OUT="${2:-$HOME/Desktop/beta audio/tts-exclaim-probe}"
KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || { echo "no ElevenLabs key" >&2; exit 1; }

LINES=(
  "ko|와, 진짜 대단하다! 나도 그거 해 보고 싶었어!"
  "ko|좋아! 그럼 내일 같이 가자!"
  "ko|축하해! 드디어 해냈구나!"
  "ko|헐, 말도 안 돼! 진짜야?"
  "ko|오, 좋은 생각이다! 그거 꼭 해 봐."
  "en|Wow, that's amazing! I've always wanted to try that!"
  "en|Congrats! You finally did it!"
)
mkdir -p "$OUT"
n=0
for entry in "${LINES[@]}"; do
  n=$((n + 1)); lang="${entry%%|*}"; text="${entry#*|}"
  for variant in bang period; do
    if [ "$variant" = period ]; then t="${text//!/.}"; else t="$text"; fi
    body="$(python3 - "$t" "$lang" <<'PY'
import json, sys
t, lang = sys.argv[1:3]
b = {"text": t, "model_id": "eleven_turbo_v2_5",
     "voice_settings": {"stability": 0.55, "similarity_boost": 0.9, "style": 0,
                        "use_speaker_boost": True, "speed": 0.9}}
if lang == "ko": b["language_code"] = "ko"
print(json.dumps(b))
PY
)"
    f="$OUT/$(printf '%02d' $n)-$lang-$variant.mp3"
    code=$(curl -s -o "$f" -w '%{http_code}' "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" -d "$body")
    [ "$code" = 200 ] || { echo "HTTP $code $f"; head -c 200 "$f"; rm -f "$f"; }
  done
done
echo "→ $OUT"

#!/usr/bin/env bash
# A clone recorded in Korean speaks English with an INDIAN accent — can the
# request fix it, or only the model? A/B by ear, in that learner's voice.
#
# Reported 2026-09-30: a Korean learner of English (voice "Future 메이",
# hpABu4jArAg9SPo3ryS7) re-cloned once because of it and heard the same
# accent again.
#
# Nothing in the request holds the accent today: the clone carries no
# language or accent label, and neither the TTS function nor the gateway
# sends `language_code`, so eleven_turbo_v2_5 decides everything from the
# reference audio. Since 2026-09-26 every clone line is turbo — the scene
# lines used to be multilingual_v2, the model built for cross-lingual
# transfer.
#
# Each English line is synthesized three ways with the PRODUCTION voice
# settings and speed:
#   turbo-auto   what ships today
#   turbo-en     `language_code: "en"` pinned — one field, same price
#   multi        eleven_multilingual_v2 — ~2x per character
# Files: <n>-<label>-<variant>.mp3. Listen in triples. If turbo-en fixes the
# accent, the fix is one field in supabase/functions/elevenlabs-tts and one
# in gateway/src/eleven-tts.ts. If only multi does, that is a pricing
# decision, not a code change. Decide by ear, not before.
#
#   scripts/tts-accent-probe.sh <voice_id> [out_dir]
#   SPEED=0.9        the app's default rung (Relaxed)
#   LINES_FILE=path  `label|text` lines instead of the built-ins
#
# About 15 short syntheses. The key is read the way every probe reads it;
# run it yourself.
set -euo pipefail

VOICE_ID="${1:?usage: tts-accent-probe.sh <elevenlabs_voice_id> [out_dir]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-$HOME/Desktop/beta audio/tts-accent-probe-$VOICE_ID}"
SPEED="${SPEED:-0.9}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

# label|text — a call opener, ordinary turns, and the sounds an Indian-English
# reading gives away first (retroflex t/d, "w"/"v", unreduced vowels).
LINES=(
  "opener|Hey, it's you from a few years on. I'm really glad we get to talk today. So, how's your week been so far?"
  "turn-short|Oh nice, that sounds like a good weekend. What did you end up doing on Sunday?"
  "turn-long|Honestly, I think the hardest part was just getting started. Once I'd done it a couple of times, it stopped feeling like a big deal."
  "tell-sounds|We were walking to the water, and it was very, very windy, but totally worth it."
  "numbers|The meeting's at a quarter to three, on the thirtieth, and it'll probably run about forty minutes."
)

if [ -n "${LINES_FILE:-}" ]; then
  LINES=()
  while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < "$LINES_FILE"
fi

mkdir -p "$OUT"
MANIFEST="$OUT/manifest.tsv"
printf 'n\tlabel\tvariant\tmodel\tlanguage_code\tfile\ttext\n' > "$MANIFEST"

say() { printf '%s\n' "$*" >&2; }
say "voice  $VOICE_ID"
say "speed  $SPEED"
say "out    $OUT"
say ""

n=0
for entry in "${LINES[@]}"; do
  n=$((n + 1))
  label="${entry%%|*}"; text="${entry#*|}"
  for variant in turbo-auto turbo-en multi; do
    case "$variant" in
      turbo-auto) model="eleven_turbo_v2_5";      lang="";;
      turbo-en)   model="eleven_turbo_v2_5";      lang="en";;
      multi)      model="eleven_multilingual_v2"; lang="";;
    esac
    file="$OUT/$(printf '%02d' "$n")-$label-$variant.mp3"
    BODY="$(python3 - "$text" "$model" "$SPEED" "$lang" <<'PY'
import json, sys
text, model, speed, lang = sys.argv[1:5]
# Production voice settings — supabase/functions/elevenlabs-tts/index.ts.
settings = {"stability": 0.55, "similarity_boost": 0.90,
            "style": 0, "use_speaker_boost": True}
s = float(speed)
if 0.7 <= s <= 1.2:
    settings["speed"] = s
body = {"text": text, "model_id": model, "voice_settings": settings}
if lang:
    body["language_code"] = lang
print(json.dumps(body))
PY
)"
    code=$(curl -s -o "$file" -w '%{http_code}' \
      "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" \
      -d "$BODY")
    if [ "$code" != "200" ]; then
      say "  ! $label/$variant → HTTP $code"
      head -c 300 "$file" >&2; say ""
      rm -f "$file"
      continue
    fi
    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$label" "$variant" "$model" "${lang:-auto}" "$(basename "$file")" "$text" >> "$MANIFEST"
    say "  $label  $variant"
  done
done

say ""
say "Listen in triples (same number). Two questions per line:"
say "  1. which one has the accent gone?"
say "  2. of those, which still sounds like the speaker?"
say ""
say "  open \"$OUT\""

#!/usr/bin/env bash
# A/B Japanese synthesis by ear: does pinning `language_code` help, and does
# the rewritten first-call greeting read better than the shipped one?
#
# Reported 2026-09-18 on the first Japanese build: the greeting "doesn't
# breathe right". Two suspects, and only an ear can tell them apart:
#   1. THE TEXT — the shipped greeting put a comma between a modifier and its
#      noun (流暢に話す、未来のきみ), and the synthesizer pauses at every comma.
#   2. THE SYNTHESIS — neither the app's TTS function nor the gateway sends
#      `language_code`, so eleven_turbo_v2_5 GUESSES the language, and a short
#      kanji-heavy line is exactly where that guess wavers.
#
# Every line is synthesized twice with the production model and voice
# settings: `auto` (what ships today) and `ja` (language pinned). Files land
# as <n>-<label>-<auto|ja>.mp3. Listen in pairs; if `ja` is better, the fix is
# one field in supabase/functions/elevenlabs-tts and one query parameter in
# gateway/src/eleven-tts.ts — not before.
#
# Key discovery mirrors voice-remix-probe.sh. About 10 short syntheses.
#
#   scripts/tts-language-probe.sh <voice_id> [out_dir]
#   LANG_CODE=ja   the language to pin (default ja)
set -euo pipefail

VOICE_ID="${1:?usage: tts-language-probe.sh <elevenlabs_voice_id> [out_dir]}"
OUT="${2:-$HOME/Desktop/beta audio/tts-language-probe-$VOICE_ID}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANG_CODE="${LANG_CODE:-ja}"
MODEL="eleven_turbo_v2_5"   # ElevenLabsClient.conversationModelId, gateway CONVERSATION_MODEL

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

# label|text
LINES=(
  "intro-shipped|こんにちは。流暢に話す、未来のきみだよ。これから交わす話が楽しみでならない。あきらめないで、今のきみがここまで来られるように、一緒にやっていこう。それで、最近はどんな感じ？"
  "intro-rewritten|やあ、未来のきみだよ。日本語、もうすらすら話せるようになったんだ。これからいっぱい話せるの、すごく楽しみ。今のきみがここまで来られるように、あきらめないで一緒にがんばろう。で、最近どうしてる？"
  "fallback|やあ、話せてうれしいよ。今日はどんな一日だった？"
  "turn-kanji|昨日は友達と映画を見に行ったんだけど、けっこう面白かったよ。きみは週末、何してた？"
  "turn-short|今日は一日中、家事に追われてた。"
)

mkdir -p "$OUT"
MANIFEST="$OUT/manifest.tsv"
printf 'n\tlabel\tvariant\tfile\ttext\n' > "$MANIFEST"

n=0
for entry in "${LINES[@]}"; do
  n=$((n + 1))
  label="${entry%%|*}"; text="${entry#*|}"
  for variant in auto "$LANG_CODE"; do
    BODY="$(python3 - "$text" "$MODEL" "$variant" <<'PY'
import json, sys
text, model, variant = sys.argv[1:4]
# Production voice settings (supabase/functions/elevenlabs-tts, gateway/src/eleven-tts.ts).
body = {"text": text, "model_id": model,
        "voice_settings": {"stability": 0.55, "similarity_boost": 0.9,
                           "style": 0, "use_speaker_boost": True}}
if variant != "auto": body["language_code"] = variant
print(json.dumps(body, ensure_ascii=False))
PY
)"
    file="$n-$label-$variant.mp3"
    STATUS="$(curl -s -o "$OUT/$file" -w '%{http_code}' -X POST \
      "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_128" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" --data "$BODY")"
    if [ "$STATUS" != "200" ]; then
      echo "  $file: HTTP $STATUS" >&2; head -c 400 "$OUT/$file" >&2; echo >&2
      rm -f "$OUT/$file"; continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$label" "$variant" "$file" "$text" >> "$MANIFEST"
    echo "  $file"
  done
done

echo
echo "Takes in: $OUT"
echo "Compare each pair (auto vs $LANG_CODE), then intro-shipped vs intro-rewritten."

#!/usr/bin/env bash
# Does a Watch scene need a better model than Talk? A/B by ear, in YOUR voice.
#
# The clone's lines in a scene ran `eleven_multilingual_v2` (1.0 credit per
# character) while Talk has always run `eleven_turbo_v2_5` (0.5) in the same
# cloned voice. Measured over the launch window that half was 26,514 credits
# against the counterpart's 11,354 — 70% of a scene's ElevenLabs bill for the
# same number of lines — so dropping it takes a scene from ~$0.112 to ~$0.073.
#
# The question a spreadsheet cannot answer is whether you can HEAR it. The
# app's own rule is that speaker similarity is the product, so this is
# settled with ears, not arithmetic (same discipline as voice-remix-probe.sh
# and tts-speed-probe.sh).
#
# Each line is synthesized twice — turbo and multilingual — with the
# PRODUCTION voice settings and the production speech speed, so the only
# difference between the two files is the model. Files land as
# <n>-<label>-<turbo|multi>.mp3, side by side, in the same folder.
#
# LISTEN FOR: "is that me?" (timbre, the shape of your vowels), and
# cross-lingual transfer — a voice recorded in one language speaking another
# is where multilingual_v2 is supposed to earn its 2x, and it is exactly what
# this app does. If turbo holds up on the target-language lines, take the 35%.
#
#   scripts/tts-model-probe.sh [voice_id] [out_dir]
#   SPEED=0.9        the speech speed the app sends (default 0.9 = Relaxed)
#   LINES_FILE=path  a file of `label|text` lines to use instead of the built-ins
#
# Costs about 12 short syntheses. The key is read the same way every probe
# reads it; run it yourself — nothing here runs on its own.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The founder's active clone (voice_clones.is_active, 2026-08-11). Pass your
# own as $1 for anyone else's voice.
VOICE_ID="${1:-31fQLzd8XYV6VPyG3GWA}"
OUT="${2:-$HOME/Desktop/beta audio/tts-model-probe-$VOICE_ID}"
SPEED="${SPEED:-0.9}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

# label|text — scene lines, the length and register a scene actually produces.
# English and German are the cross-lingual cases (a clone recorded in Korean
# speaking them); the Korean pair is the control, where the model has the
# least to transfer and should sound identical.
LINES=(
  "en-scene-open|Hi, I have a reservation under Lee. It's for two nights, checking out on Friday."
  "en-scene-complication|I'm sorry, but this isn't what I ordered. I asked for the one without cheese — could you check the ticket?"
  "en-scene-long|So the way it usually works is, you send over the brief on Monday, we come back with two directions by Thursday, and then we pick one together before anything gets built."
  "de-scene|Entschuldigung, ich glaube, da ist ein Fehler auf der Rechnung. Können Sie das bitte noch einmal prüfen?"
  "ko-scene|어제 말한 그 카페 있잖아, 거기 결국 못 갔어. 다음 주에 같이 갈래?"
  "ko-long|나는 원래 아침형 인간이 아니었는데, 아이 등원시키다 보니까 어쩔 수 없이 일찍 일어나게 되더라고."
)

if [ -n "${LINES_FILE:-}" ]; then
  LINES=()
  while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < "$LINES_FILE"
fi

mkdir -p "$OUT"
MANIFEST="$OUT/manifest.tsv"
printf 'n\tlabel\tmodel\tchars\tcredits\tfile\ttext\n' > "$MANIFEST"

say() { printf '%s\n' "$*" >&2; }
say "voice  $VOICE_ID"
say "speed  $SPEED"
say "out    $OUT"
say ""

n=0
total_turbo=0
total_multi=0
for entry in "${LINES[@]}"; do
  n=$((n + 1))
  label="${entry%%|*}"; text="${entry#*|}"
  chars=$(printf '%s' "$text" | wc -m | tr -d ' ')
  for variant in turbo multi; do
    case "$variant" in
      turbo) model="eleven_turbo_v2_5"; credits=$(( chars / 2 ));;
      multi) model="eleven_multilingual_v2"; credits=$chars;;
    esac
    file="$OUT/$(printf '%02d' "$n")-$label-$variant.mp3"
    BODY="$(python3 - "$text" "$model" "$SPEED" <<'PY'
import json, sys
text, model, speed = sys.argv[1:4]
# Production voice settings — supabase/functions/elevenlabs-tts/index.ts.
# `style` MUST stay 0 for a cloned voice; anything above pulls the output
# away from the reference speaker, which would make this A/B measure the
# wrong thing.
settings = {"stability": 0.55, "similarity_boost": 0.90,
            "style": 0, "use_speaker_boost": True}
s = float(speed)
if 0.7 <= s <= 1.2:
    settings["speed"] = s
print(json.dumps({"text": text, "model_id": model, "voice_settings": settings}))
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
    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$label" "$model" "$chars" "$credits" "$(basename "$file")" "$text" >> "$MANIFEST"
    say "  $label  $variant  ${chars}자 → ${credits}cr"
    case "$variant" in
      turbo) total_turbo=$((total_turbo + credits));;
      multi) total_multi=$((total_multi + credits));;
    esac
  done
done

say ""
say "credits over these lines:  turbo $total_turbo   multilingual $total_multi"
say ""
say "Listen in pairs (same number, -turbo vs -multi). If you cannot pick the"
say "multilingual file out reliably — especially on the English and German"
say "lines — the scene keeps turbo and a scene costs 35% less."
say ""
say "  open \"$OUT\""

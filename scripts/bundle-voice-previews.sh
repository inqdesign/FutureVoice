#!/usr/bin/env bash
# Make the preset-voice preview clips the app SHIPS, so tapping ▶ in a voice
# picker plays a file from the bundle instead of synthesizing the same line
# again for every learner (2026-10-12: every learner was paying ElevenLabs for
# four identical clips per language).
#
# One clip per (target language × preset slot). The text and the voice must
# match what the app would have asked for:
#   text  = VoicePresetPickerView.previewLine(for:)   (CounterpartsListSheet.swift)
#   voice = VoicePreset.speaking(slot, in: language)  (Models.swift — ko/ja
#           slots are voiced by native Korean library voices)
# Re-run this whenever either of those changes; the app falls back to live
# synthesis for any clip that is missing.
#
# Usage: scripts/bundle-voice-previews.sh            (all languages)
#        LANGS="ko ja" scripts/bundle-voice-previews.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/FutureVoice/Resources/VoicePreviews"
LANGS="${LANGS:-en es de fr it pt ja ko}"
MODEL="eleven_turbo_v2_5"
SPEED="0.9"   # SpeechSpeed's default rung

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

SLOTS="NDTYOmYEjbDIVCKB35i3 UgBBYS2sOqTuMpoF3BR0 FF59babHL8N8gfTgtBMT L0Dsvb3SLTyegXwtm47J"

voice_for() {  # $1 lang, $2 slot  → the voice that speaks that slot
  case "$1" in
    ko|ja)
      case "$2" in
        NDTYOmYEjbDIVCKB35i3) echo 5n5gqmaQi9Ewevrz7bOS ;;
        UgBBYS2sOqTuMpoF3BR0) echo L4az9Gb378GIycFl2nAB ;;
        FF59babHL8N8gfTgtBMT) echo 8jHHF8rMqMlg8if2mOUe ;;
        L0Dsvb3SLTyegXwtm47J) echo AKF7f2y1L8ktV5vxXILw ;;
      esac ;;
    *) echo "$2" ;;
  esac
}

line_for() {  # must stay byte-identical to previewLine(for:)
  case "$1" in
    es) echo '¡Hola! Qué alegría verte. <break time="0.5s" /> ¿Empezamos?' ;;
    de) echo 'Hallo! Schön, dich zu sehen. <break time="0.5s" /> Sollen wir anfangen?' ;;
    fr) echo 'Bonjour ! Ça me fait plaisir de te voir. <break time="0.5s" /> On commence ?' ;;
    it) echo 'Ciao! Che bello vederti. <break time="0.5s" /> Iniziamo?' ;;
    pt) echo 'Oi! Que bom te ver. <break time="0.5s" /> Vamos começar?' ;;
    ja) echo 'こんにちは！会えてうれしいです。<break time="0.5s" />始めましょうか？' ;;
    ko) echo '안녕하세요! 만나서 반가워요. <break time="0.5s" /> 시작해 볼까요?' ;;
    zh) echo '你好！很高兴见到你。<break time="0.5s" />我们开始吧？' ;;
    *)  echo 'Hi! It'"'"'s good to see you. <break time="0.5s" /> Shall we get started?' ;;
  esac
}

mkdir -p "$OUT"
for lang in $LANGS; do
  text="$(line_for "$lang")"
  for slot in $SLOTS; do
    voice="$(voice_for "$lang" "$slot")"
    file="$OUT/preview-$lang-$slot.mp3"
    BODY="$(python3 - "$text" "$MODEL" "$SPEED" <<'PY'
import json, sys
text, model, speed = sys.argv[1:4]
# Production voice settings (supabase/functions/elevenlabs-tts/index.ts).
vs = {"stability": 0.55, "similarity_boost": 0.9, "style": 0,
      "use_speaker_boost": True, "speed": float(speed)}
print(json.dumps({"text": text, "model_id": model, "voice_settings": vs}, ensure_ascii=False))
PY
)"
    STATUS="$(curl -s -o "$file" -w '%{http_code}' -X POST \
      "https://api.elevenlabs.io/v1/text-to-speech/$voice?output_format=mp3_44100_64" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" --data "$BODY")"
    if [ "$STATUS" != "200" ]; then
      echo "$lang/$slot: HTTP $STATUS" >&2; head -c 300 "$file" >&2; echo >&2
      rm -f "$file"; continue
    fi
    echo "$lang/$slot → $(basename "$file") ($(wc -c < "$file" | tr -d ' ') bytes)"
  done
done

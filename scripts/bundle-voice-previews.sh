#!/usr/bin/env bash
# Make the preset-voice preview clips the app SHIPS, so tapping ▶ in a voice
# picker plays a file from the bundle instead of synthesizing the same line
# again for every learner (2026-10-12: every learner was paying for
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
LANGS="${LANGS:-en de ja ko es}"   # the selectable targets
MODEL="sonic-3.6"
SPEED="1.1667"   # SpeechSpeed's default rung (0.9) on Cartesia's scale (cartesia.ts cartesiaSpeed)

KEY="$(tr -d '[:space:]' < "$HOME/keys/cartesia.txt")"

SLOTS="NDTYOmYEjbDIVCKB35i3 UgBBYS2sOqTuMpoF3BR0 FF59babHL8N8gfTgtBMT L0Dsvb3SLTyegXwtm47J"

voice_for() {  # $1 lang, $2 slot  → the voice that speaks that slot (Cartesia since 2026-10-12)
  case "$1:$2" in
    en:NDTYOmYEjbDIVCKB35i3) echo 999df508-4de5-40a7-8bd3-8c12f678c284 ;;
    en:UgBBYS2sOqTuMpoF3BR0) echo c961b81c-a935-4c17-bfb3-ba2239de8c2f ;;
    en:FF59babHL8N8gfTgtBMT) echo e5d4c33a-d8f6-46e8-a10f-b5afecc35648 ;;
    en:L0Dsvb3SLTyegXwtm47J) echo 3d5ce2fb-e56c-42f0-9ed9-4662484063b4 ;;
    de:NDTYOmYEjbDIVCKB35i3) echo 1ade29fc-6b82-4607-9e70-361720139b12 ;;
    de:UgBBYS2sOqTuMpoF3BR0) echo dff81230-ff75-49a4-af44-f6b2f43500d8 ;;
    de:FF59babHL8N8gfTgtBMT) echo 3f4ade23-6eb4-4279-ab05-6a144947c4d5 ;;
    de:L0Dsvb3SLTyegXwtm47J) echo afa425cf-5489-4a09-8a3f-d3cb1f82150d ;;
    ko:NDTYOmYEjbDIVCKB35i3) echo cac92886-4b7c-4bc1-a524-e0f79c0381be ;;
    ko:UgBBYS2sOqTuMpoF3BR0) echo 537a82ae-4926-4bfb-9aec-aff0b80a12a5 ;;
    ko:FF59babHL8N8gfTgtBMT) echo cd6c48a9-774b-4397-98b4-9948c0a790f0 ;;
    ko:L0Dsvb3SLTyegXwtm47J) echo f7755efb-1848-4321-aa22-5e5be5d32486 ;;
    ja:NDTYOmYEjbDIVCKB35i3) echo c7eafe22-8b71-40cd-850b-c5a3bbd8f8d2 ;;
    ja:UgBBYS2sOqTuMpoF3BR0) echo b8e1169c-f16a-4064-a6e0-95054169e553 ;;
    ja:FF59babHL8N8gfTgtBMT) echo 7be83d14-4707-43ad-9774-e24eb38320f0 ;;
    ja:L0Dsvb3SLTyegXwtm47J) echo 6b92f628-be90-497c-8f4c-3b035002df71 ;;
    es:NDTYOmYEjbDIVCKB35i3) echo 3797b3c0-ab71-40dc-bfa0-a8c6ff9c1e8b ;;
    es:UgBBYS2sOqTuMpoF3BR0) echo 7b001dff-b8b2-4da7-92e4-5c794798effa ;;
    es:FF59babHL8N8gfTgtBMT) echo 727f663b-0e90-4031-90f2-558b7334425b ;;
    es:L0Dsvb3SLTyegXwtm47J) echo e9f0368b-3662-4a01-b037-e13ca5203c74 ;;
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
    BODY="$(python3 - "$text" "$MODEL" "$SPEED" "$voice" "$lang" <<'PY'
import json, sys
text, model, speed, voice, lang = sys.argv[1:6]
print(json.dumps({"model_id": model, "transcript": text, "voice": {"mode": "id", "id": voice},
                  "language": lang, "output_format": {"container": "mp3", "sample_rate": 44100, "bit_rate": 64000},
                  "generation_config": {"speed": float(speed), "emotion": "neutral"}}, ensure_ascii=False))
PY
)"
    STATUS="$(curl -s -o "$file" -w '%{http_code}' -X POST https://api.cartesia.ai/tts/bytes \
      -H "Authorization: Bearer $KEY" -H "Cartesia-Version: 2026-08-14" \
      -H "Content-Type: application/json" --data "$BODY")"
    if [ "$STATUS" != "200" ]; then
      echo "$lang/$slot: HTTP $STATUS" >&2; head -c 300 "$file" >&2; echo >&2
      rm -f "$file"; continue
    fi
    echo "$lang/$slot → $(basename "$file") ($(wc -c < "$file" | tr -d ' ') bytes)"
  done
done

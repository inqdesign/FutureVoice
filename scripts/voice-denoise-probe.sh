#!/usr/bin/env bash
# Does cleaning the recording before a Cartesia clone take the room noise
# out of the voice? (2026-10-13)
#
# Clones the SAME recording twice on Cartesia — as recorded, and after
# ElevenLabs' Audio Isolation — speaks the same lines with both, and deletes
# both clones. Listen to raw-* against clean-* in the output folder.
#
#   scripts/voice-denoise-probe.sh <recording> [out_dir]
#
# Use the founder's own recording only (never a learner's — consent covers
# ElevenLabs cloning, not vendor tests).
set -euo pipefail
cd "$(dirname "$0")/.."
IN="${1:?recording}"
OUT="${2:-$HOME/Desktop/beta audio/denoise-probe-$(date +%Y%m%d-%H%M)}"
if [[ -e "$OUT" ]]; then echo "exists: $OUT" >&2; exit 1; fi
mkdir -p "$OUT"
EL=$(grep '^ELEVENLABS_API_KEY=' gateway/.dev.vars | cut -d= -f2- | tr -d '"')
CA=$(tr -d '\n' < ~/keys/cartesia.txt)
V=2026-08-14

ffmpeg -loglevel error -i "$IN" -ac 1 -ar 44100 "$OUT/recording-raw.wav"

echo "▸ isolating voice (ElevenLabs)"
curl -sf -X POST https://api.elevenlabs.io/v1/audio-isolation \
  -H "xi-api-key: $EL" -F "audio=@$OUT/recording-raw.wav" -o "$OUT/recording-clean.mp3"
ffmpeg -loglevel error -i "$OUT/recording-clean.mp3" -ac 1 -ar 44100 "$OUT/recording-clean.wav"

# Same levelling the server does before a clone (-20 dBFS speech).
for k in raw clean; do
  ffmpeg -loglevel error -y -i "$OUT/recording-$k.wav" -af loudnorm=I=-20:TP=-1.5 -ar 44100 "$OUT/clip-$k.wav"
done

clone() {
  curl -sf -X POST https://api.cartesia.ai/voices/clone \
    -H "Authorization: Bearer $CA" -H "Cartesia-Version: $V" \
    -F "clip=@$1" -F "name=denoise-probe-$2" -F "language=en" |
    python3 -c "import json,sys;print(json.load(sys.stdin)['id'])"
}
RAW_ID=$(clone "$OUT/clip-raw.wav" raw)
CLEAN_ID=$(clone "$OUT/clip-clean.wav" clean)
echo "▸ clones: raw=$RAW_ID clean=$CLEAN_ID"

say() {  # voice lang text file
  curl -sf -X POST https://api.cartesia.ai/tts/bytes \
    -H "Authorization: Bearer $CA" -H "Cartesia-Version: $V" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"model_id":"sonic-3.6","transcript":sys.argv[3],"voice":{"mode":"id","id":sys.argv[1]},"language":sys.argv[2],"output_format":{"container":"wav","encoding":"pcm_s16le","sample_rate":44100},"generation_config":{"speed":1.17,"emotion":"neutral"}}))' "$1" "$2" "$3")" \
    -o "$4"
}
i=0
while IFS='|' read -r lang text; do
  i=$((i+1))
  for k in raw clean; do
    id=$RAW_ID; [[ $k == clean ]] && id=$CLEAN_ID
    say "$id" "$lang" "$text" "$OUT/$k-$i-$lang.wav"
  done
done <<'LINES'
en|Hey, it's me. I just got back from the bakery, and honestly, the line was out the door again.
en|So what did you end up doing this weekend? Anything fun, or did you just rest?
de|Morgen früh hole ich zwei Brötchen beim Bäcker, danach fahre ich mit dem Zug nach München.
ko|오늘은 좀 일찍 일어나서 산책을 했는데, 공기가 생각보다 훨씬 차가웠어.
LINES

for id in "$RAW_ID" "$CLEAN_ID"; do
  curl -s -X DELETE "https://api.cartesia.ai/voices/$id" -H "Authorization: Bearer $CA" -H "Cartesia-Version: $V" >/dev/null
done
echo "→ $OUT"
ls "$OUT"

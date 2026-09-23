#!/usr/bin/env bash
# A/B the fluent self's speaking SPEED by ear.
#
# Asked 2026-09-23: can the learner slow the future self down? ElevenLabs
# takes `voice_settings.speed` (0.7–1.2) and NOTHING in this repo sends it —
# neither supabase/functions/elevenlabs-tts nor gateway/src/eleven-tts.ts.
# Before either of those grows a field, the value has to be chosen by ear,
# because of the one thing already measured about it:
#
#   `speed: 0.9` slows the WORDS and shrinks the PAUSES
#   (CoachingLanguage.breathPunctuation, 2026-09-15).
#
# So a slower voice may also be a less breathing one, and only a listener can
# say where that trade turns bad. Every line here is synthesized at each speed
# with the PRODUCTION model and voice settings, so what you hear is what a
# learner would get. Files land as <n>-<label>-<speed>.mp3.
#
# The manifest reports, per take, the audio's length and how much of it is
# SILENCE (ffmpeg silencedetect, edges excluded) — that is the breath axis in
# numbers, next to the ear's verdict. Trust the ear; the numbers only say
# which suspicion to hold.
#
# Key discovery mirrors scripts/voice-remix-probe.sh: $ELEVENLABS_API_KEY,
# else gateway/.dev.vars, else ~/keys/elevenlabs.txt. ~15 short syntheses.
#
#   scripts/tts-speed-probe.sh [voice_id] [out_dir]
#
#   SPEEDS="off 0.95 0.9 0.85 0.8"   "off" omits the field = what ships today
#   MODEL=eleven_turbo_v2_5          live talk; eleven_multilingual_v2 = Watch
#   LINES=both                       both | en | ko
set -euo pipefail

# Default: the founder's own live clone ("Future Eunggyu"). Re-cloning or an
# accent save mints a NEW id, so pass one explicitly if this one 404s.
VOICE_ID="${1:-31fQLzd8XYV6VPyG3GWA}"
OUT="${2:-$HOME/Desktop/beta audio/tts-speed-probe-$VOICE_ID}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEEDS="${SPEEDS:-off 0.95 0.9 0.85 0.8}"
MODEL="${MODEL:-eleven_turbo_v2_5}"   # ElevenLabsClient.conversationModelId
LINES="${LINES:-both}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

# lang|label|text — real fluent-self shapes: a short reaction, a full turn at
# ConversationEngine's three-sentence ceiling, and a Korean line, since the
# pause complaint that produced the breath rule was Korean.
ALL_LINES=(
  "en|short|Oh, that's rough. How did you end up handling it?"
  "en|turn|I ended up walking there instead, because the bus was packed and I wasn't in the mood. It took about forty minutes, but honestly it was the best part of my day. What about you, did you get out at all?"
  "en|teach|That's the word I'd use too, though most people would just say you're swamped. Try it next time someone asks how work is going."
  "ko|turn|나도 그때는 진짜 아무 말도 못 했는데, 지나고 나니까 한마디라도 해볼 걸 싶더라. 너는 그런 순간에 보통 어떻게 해?"
  "ko|short|아 그래? 그거 재밌었겠다."
)

mkdir -p "$OUT"
MANIFEST="$OUT/manifest.tsv"
printf 'n\tlang\tlabel\tspeed\tfile\tseconds\tsilence_s\tsilence_n\ttext\n' > "$MANIFEST"

n=0
for entry in "${ALL_LINES[@]}"; do
  lang="${entry%%|*}"; rest="${entry#*|}"
  label="${rest%%|*}"; text="${rest#*|}"
  [ "$LINES" = "both" ] || [ "$LINES" = "$lang" ] || continue
  n=$((n + 1))
  echo "[$n] $lang/$label"
  for S in $SPEEDS; do
    BODY="$(python3 - "$text" "$MODEL" "$S" <<'PY'
import json, sys
text, model, speed = sys.argv[1:4]
# Production voice settings, verbatim (supabase/functions/elevenlabs-tts/index.ts,
# gateway/src/eleven-tts.ts). style MUST stay 0 for a cloned voice.
vs = {"stability": 0.55, "similarity_boost": 0.9, "style": 0, "use_speaker_boost": True}
if speed != "off":
    vs["speed"] = float(speed)
print(json.dumps({"text": text, "model_id": model, "voice_settings": vs}, ensure_ascii=False))
PY
)"
    file="$n-$label-$S.mp3"
    STATUS="$(curl -s -o "$OUT/$file" -w '%{http_code}' -X POST \
      "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_128" \
      -H "xi-api-key: $KEY" -H "Content-Type: application/json" --data "$BODY")"
    if [ "$STATUS" != "200" ]; then
      echo "  $file: HTTP $STATUS" >&2; head -c 400 "$OUT/$file" >&2; echo >&2
      rm -f "$OUT/$file"; continue
    fi
    # Length + internal silence. Edge silences are dropped: a leading or
    # trailing gap is the render, not a breath.
    read -r SECS SIL SILN <<<"$(ffmpeg -hide_banner -nostats -i "$OUT/$file" \
        -af silencedetect=noise=-35dB:d=0.12 -f null - 2>&1 |
      python3 -c '
import re, sys
t = sys.stdin.read()
m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", t)
dur = int(m.group(1))*3600 + int(m.group(2))*60 + float(m.group(3)) if m else 0.0
starts = [float(x) for x in re.findall(r"silence_start: ([\d.\-]+)", t)]
ends    = [float(x) for x in re.findall(r"silence_end: ([\d.\-]+)", t)]
tot, cnt = 0.0, 0
for s, e in zip(starts, ends):
    if s < 0.05 or e > dur - 0.05:   # edges are not breaths
        continue
    tot += e - s; cnt += 1
print(f"{dur:.2f} {tot:.2f} {cnt}")')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$n" "$lang" "$label" "$S" "$file" "$SECS" "$SIL" "$SILN" "$text" >> "$MANIFEST"
    echo "  $S → ${SECS}s, ${SIL}s silence in ${SILN} gaps"
  done
done

echo
python3 - "$MANIFEST" <<'PY'
import collections, csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
base = {(r["n"]): float(r["seconds"]) for r in rows if r["speed"] == "off"}
by = collections.defaultdict(list)
for r in rows: by[r["speed"]].append(r)
print("speed  longer than today   silence per 10s of audio")
for sp, rs in by.items():
    grow = [float(r["seconds"]) / base[r["n"]] for r in rs if r["n"] in base and base[r["n"]]]
    sil  = [float(r["silence_s"]) / float(r["seconds"]) * 10 for r in rs if float(r["seconds"])]
    g = sum(grow)/len(grow) if grow else 0
    s = sum(sil)/len(sil) if sil else 0
    print(f"{sp:>5}  {(g-1)*100:+6.1f}%             {s:.2f}s")
PY

echo
echo "Takes in: $OUT"
echo "Listen one LINE at a time, fastest first:"
echo "  cd \"$OUT\" && for f in 1-*.mp3; do echo \"\$f\"; afplay \"\$f\"; done"
echo
echo "Pick the slowest speed that still sounds like a person talking, not a"
echo "recording played slow — and check it still BREATHES (that is the column"
echo "above, and the reason 0.9 was rejected once already)."

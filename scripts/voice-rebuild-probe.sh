#!/usr/bin/env bash
# Rebuild ONE learner's voice from their original recording, cleaned up, and
# hear the accent remix on each version — by ear, before touching their account.
#
# For a clone that came out bad because the RECORDING was bad (room noise,
# distance). Three sources are cloned side by side:
#   0-original   the recording as made
#   1-isolated   ElevenLabs Voice Isolator over it (/v1/audio-isolation)
#   2-cloneflag  the original, cloned with remove_background_noise=true
# For each: a plain line in the clone (production voice settings, turbo) and
# three accent-remix takes at the app's own prompt + prompt_strength.
#
# Every temporary clone is DELETED at the end (account slots are 160), so
# nothing reaches the learner. Applying a picked take to their account is a
# separate, deliberate step.
#
#   scripts/voice-rebuild-probe.sh <recording.wav> [out_dir]
#   ACCENT=en-US|en-GB|en-AU   (default en-US)   STRENGTH=0.3   KEEP=1 keeps clones
set -euo pipefail

SRC="${1:?usage: voice-rebuild-probe.sh <recording.wav> [out_dir]}"
OUT="${2:-$HOME/Desktop/beta audio/rebuild-probe-$(date +%m%d-%H%M)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCENT="${ACCENT:-en-US}"
STRENGTH="${STRENGTH:-0.3}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key" >&2; exit 1; }

case "$ACCENT" in
  en-US) ACCENT_TEXT="General American English accent" ;;
  en-GB) ACCENT_TEXT="British English accent with standard Southern British pronunciation" ;;
  en-AU) ACCENT_TEXT="Australian English accent" ;;
  *) echo "unknown ACCENT $ACCENT" >&2; exit 1 ;;
esac
DESCRIPTION="Keep this exact same voice: the same person, timbre, pitch, age and character. Change ONLY the accent — the speaker now has a natural, consistent ${ACCENT_TEXT}. Do not change anything else about how the voice sounds."
REMIX_TEXT="Right — let me think about tomorrow. I'll grab a bottle of water and a cup of coffee on the way, probably around half past eight. I can't be late again; the last bus leaves at twenty to nine. Honestly, the weather's been better lately, hasn't it? Maybe I'll walk through the park instead, and I'll call you when I get there."
PLAIN_TEXT="Hey, it's me. I was just thinking about what we talked about yesterday, and honestly, I think you should go for it."

mkdir -p "$OUT"
cp "$SRC" "$OUT/source-0-original.wav"
CREATED=()
cleanup() {
  [ "${KEEP:-}" = "1" ] && { echo "KEEP=1 — clones left: ${CREATED[*]:-none}"; return; }
  for v in "${CREATED[@]:-}"; do
    [ -n "$v" ] && curl -s -o /dev/null -X DELETE "https://api.elevenlabs.io/v1/voices/$v" -H "xi-api-key: $KEY" && echo "deleted temp clone $v"
  done
}
trap cleanup EXIT

echo "→ Voice Isolator …"
STATUS="$(curl -s -o "$OUT/source-1-isolated.mp3" -w '%{http_code}' -X POST \
  "https://api.elevenlabs.io/v1/audio-isolation" -H "xi-api-key: $KEY" -F "audio=@$SRC")"
[ "$STATUS" = "200" ] || { echo "isolation HTTP $STATUS" >&2; cat "$OUT/source-1-isolated.mp3" >&2; exit 1; }

probe() {  # <label> <file> <remove_background_noise>
  local label="$1" file="$2" denoise="$3" resp vid
  echo "→ $label: clone …"
  resp="$(curl -s -X POST https://api.elevenlabs.io/v1/voices/add -H "xi-api-key: $KEY" \
    -F "name=rebuild-probe-$label" -F "remove_background_noise=$denoise" -F "files=@$file")"
  vid="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("voice_id",""))' "$resp")"
  [ -n "$vid" ] || { echo "  clone failed: $resp" >&2; return; }
  CREATED+=("$vid")

  curl -s -o "$OUT/$label-plain.mp3" -X POST \
    "https://api.elevenlabs.io/v1/text-to-speech/$vid?output_format=mp3_44100_128" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" \
    --data "$(python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"model_id":"eleven_turbo_v2_5","voice_settings":{"stability":0.55,"similarity_boost":0.9,"style":0,"use_speaker_boost":True,"speed":0.9}}))' "$PLAIN_TEXT")"
  echo "  $label-plain.mp3"

  python3 - "$vid" "$label" "$OUT" "$KEY" "$DESCRIPTION" "$REMIX_TEXT" "$STRENGTH" <<'PY'
import base64, json, sys, urllib.request
vid, label, out, key, d, t, s = sys.argv[1:8]
req = urllib.request.Request(
    f"https://api.elevenlabs.io/v1/text-to-voice/{vid}/remix?output_format=mp3_44100_128",
    data=json.dumps({"voice_description": d, "text": t, "prompt_strength": float(s)}).encode(),
    headers={"xi-api-key": key, "Content-Type": "application/json", "User-Agent": "rebuild-probe"})
previews = json.load(urllib.request.urlopen(req, timeout=120)).get("previews", [])
with open(f"{out}/manifest.tsv", "a") as m:
    for i, p in enumerate(previews, 1):
        name = f"{label}-accent-take{i}.mp3"
        open(f"{out}/{name}", "wb").write(base64.b64decode(p["audio_base_64"]))
        m.write(f"{label}\t{name}\t{p['generated_voice_id']}\n")
        print(f"  {name}")
PY
}

printf 'source\tfile\tgenerated_voice_id\n' > "$OUT/manifest.tsv"
probe 0-original  "$SRC"                          false
probe 1-isolated  "$OUT/source-1-isolated.mp3"    false
probe 2-cloneflag "$SRC"                          true

echo
echo "Listen in: $OUT"
echo "source-*.wav/mp3 = what was cloned · *-plain = the clone itself · *-accent-take* = $ACCENT remix at $STRENGTH"
echo "manifest.tsv keeps each take's generated_voice_id (previews expire upstream within ~a day)."

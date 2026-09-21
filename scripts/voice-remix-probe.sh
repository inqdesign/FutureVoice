#!/usr/bin/env bash
# A/B the accent remix's prompt_strength on ONE voice, by ear.
#
# Generates remix previews of an ElevenLabs voice you own at several
# prompt strengths — the app's own accent prompt and sample text, so what you
# hear is exactly what a learner would get — and writes every take to disk as
# <strength>-takeN.mp3 next to a manifest. Listen, pick the strength that
# still sounds like the speaker, and put it in `VoiceAccentCatalog.promptStrength`.
#
# The voice MUST be an un-remixed clone (category "cloned" in ElevenLabs), or
# the probe measures drift on top of drift. A voice that already carries an
# accent has no original left upstream — rebuild one from the phone's saved
# recording first (Me → Voice → Regenerate from saved recording, or "Remove
# accent"), then probe THAT id.
#
# Key discovery mirrors scripts/voice-sample.sh: $ELEVENLABS_API_KEY, else
# gateway/.dev.vars, else ~/keys/elevenlabs.txt. Each strength is one remix
# call (a few previews each) billed by the sample text's length.
#
#   scripts/voice-remix-probe.sh <voice_id> [out_dir]
#
#   STRENGTHS="default 0.15 0.3 0.5"   which prompt_strength values to try
#                                      ("default" = omit the parameter, i.e.
#                                       what every accent before 2026-09-18 got)
#   ACCENT=en-GB                       en-US | en-GB | en-AU (default en-GB)
#   GUIDANCE=                          optional guidance_scale (upstream default 2)
set -euo pipefail

VOICE_ID="${1:?usage: voice-remix-probe.sh <elevenlabs_voice_id> [out_dir]}"
OUT="${2:-$HOME/Desktop/beta audio/remix-probe-$VOICE_ID}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRENGTHS="${STRENGTHS:-default 0.15 0.3 0.5}"
ACCENT="${ACCENT:-en-GB}"
GUIDANCE="${GUIDANCE:-}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt" >&2; exit 1; }

# The app's prompt and sample text, verbatim from VoiceAccent.swift.
case "$ACCENT" in
  en-US) ACCENT_TEXT="General American English accent" ;;
  en-GB) ACCENT_TEXT="British English accent with standard Southern British pronunciation" ;;
  en-AU) ACCENT_TEXT="Australian English accent" ;;
  *) echo "unknown ACCENT $ACCENT (en-US | en-GB | en-AU)" >&2; exit 1 ;;
esac
DESCRIPTION="Keep this exact same voice: the same person, timbre, pitch, age and character. Change ONLY the accent — the speaker now has a natural, consistent ${ACCENT_TEXT}. Do not change anything else about how the voice sounds."
TEXT="Right — let me think about tomorrow. I'll grab a bottle of water and a cup of coffee on the way, probably around half past eight. I can't be late again; the last bus leaves at twenty to nine. Honestly, the weather's been better lately, hasn't it? Maybe I'll walk through the park instead, and I'll call you when I get there."

mkdir -p "$OUT"
META="$OUT/voice.json"
STATUS="$(curl -s -o "$META" -w '%{http_code}' "https://api.elevenlabs.io/v1/voices/$VOICE_ID" -H "xi-api-key: $KEY")"
[ "$STATUS" = "200" ] || { echo "ElevenLabs returned HTTP $STATUS for voice $VOICE_ID" >&2; cat "$META" >&2; exit 1; }
CATEGORY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("category",""))' "$META")"
echo "voice $VOICE_ID · category=$CATEGORY"
if [ "$CATEGORY" != "cloned" ]; then
  echo "WARNING: not an un-remixed clone (category=$CATEGORY) — this probes drift on top of drift." >&2
fi

MANIFEST="$OUT/manifest.tsv"
printf 'strength\tfile\tgenerated_voice_id\tduration_s\n' > "$MANIFEST"

for S in $STRENGTHS; do
  BODY="$(python3 - "$DESCRIPTION" "$TEXT" "$S" "$GUIDANCE" <<'PY'
import json, sys
d, t, s, g = sys.argv[1:5]
body = {"voice_description": d, "text": t}
if s != "default": body["prompt_strength"] = float(s)
if g: body["guidance_scale"] = float(g)
print(json.dumps(body))
PY
)"
  echo "→ prompt_strength=$S …"
  RESP="$OUT/.resp-$S.json"
  STATUS="$(curl -s -o "$RESP" -w '%{http_code}' -X POST \
    "https://api.elevenlabs.io/v1/text-to-voice/$VOICE_ID/remix?output_format=mp3_44100_128" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" --data "$BODY")"
  if [ "$STATUS" != "200" ]; then
    echo "  HTTP $STATUS:" >&2; head -c 600 "$RESP" >&2; echo >&2
    continue
  fi
  python3 - "$RESP" "$OUT" "$S" "$MANIFEST" <<'PY'
import base64, json, sys
resp, out, s, manifest = sys.argv[1:5]
previews = json.load(open(resp)).get("previews", [])
with open(manifest, "a") as m:
    for i, p in enumerate(previews, 1):
        name = f"{s}-take{i}.mp3"
        open(f"{out}/{name}", "wb").write(base64.b64decode(p["audio_base_64"]))
        m.write(f"{s}\t{name}\t{p['generated_voice_id']}\t{p.get('duration_secs','')}\n")
        print(f"  {name}  ({p.get('duration_secs','?')} s)")
PY
  rm -f "$RESP"
done

echo
echo "Takes in: $OUT"
echo "Listen side by side (the original is the voice's own sample: scripts/voice-sample.sh $VOICE_ID)."
echo "Nothing was saved upstream — previews expire on their own; pick a strength and set VoiceAccentCatalog.promptStrength."

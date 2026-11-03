#!/usr/bin/env bash
# Score one recording against Azure's pronunciation assessment, straight from
# this Mac — the same request the `pronunciation` edge function makes, so a
# number here is the number the app would show. For deciding, by ear, whether
# the scores track what a listener hears BEFORE anything ships (2026-11-03).
#
#   scripts/pronunciation-probe.sh <audio> <locale> "<reference text>"
#
#   <audio>   any file ffmpeg can read; converted to 16 kHz mono PCM16 WAV
#   <locale>  en-US | en-GB | en-AU | de-DE | ja-JP | ko-KR | es-MX | es-ES
#
# Reads AZURE_SPEECH_KEY / AZURE_SPEECH_REGION from ~/keys/azure-speech.env.
# Prints the full-text scores, then every word with its accuracy, error type
# and the phonemes under 70. Use the founder's OWN takes, never a learner's
# recording (vendor probes are not something a learner consented to).

set -euo pipefail

AUDIO="${1:?audio file}"
LOCALE="${2:?locale, e.g. en-US}"
REFERENCE="${3:?reference text}"

ENV_FILE="$HOME/keys/azure-speech.env"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (AZURE_SPEECH_KEY=…, AZURE_SPEECH_REGION=…)" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${AZURE_SPEECH_KEY:?}" "${AZURE_SPEECH_REGION:?}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WAV="$TMP/take.wav"
ffmpeg -v error -y -i "$AUDIO" -ac 1 -ar 16000 -sample_fmt s16 -t 30 "$WAV"

PROSODY=false
[ "$LOCALE" = "en-US" ] && PROSODY=true
PA_JSON=$(printf '{"ReferenceText":%s,"GradingSystem":"HundredMark","Granularity":"Phoneme","Dimension":"Comprehensive","EnableMiscue":true,"EnableProsodyAssessment":%s,"PhonemeAlphabet":"IPA"}' \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$REFERENCE")" "$PROSODY")
PA_B64=$(printf '%s' "$PA_JSON" | base64 | tr -d '\n')

URL="https://${AZURE_SPEECH_REGION}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=${LOCALE}&format=detailed"
START=$(python3 -c 'import time; print(time.time())')
HTTP=$(curl -sS -o "$TMP/out.json" -w '%{http_code}' -X POST "$URL" \
  -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
  -H "Content-Type: audio/wav; codecs=audio/pcm; samplerate=16000" \
  -H "Accept: application/json" \
  -H "Pronunciation-Assessment: $PA_B64" \
  --data-binary @"$WAV")
END=$(python3 -c 'import time; print(time.time())')

if [ "$HTTP" != "200" ]; then
  echo "HTTP $HTTP"; cat "$TMP/out.json"; echo; exit 1
fi

python3 -I - "$TMP/out.json" "$START" "$END" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
print(f"round trip: {float(sys.argv[3]) - float(sys.argv[2]):.2f}s   status: {r.get('RecognitionStatus')}")
best = (r.get("NBest") or [{}])[0]
# REST puts scores flat on each object; the SDK nests them. Read either.
def g(o, k):
    return o.get(k, (o.get("PronunciationAssessment") or {}).get(k))
print("recognized:", best.get("Display"))
print("  score(PronScore) {}  accuracy {}  fluency {}  completeness {}  prosody {}".format(
    g(best, "PronScore"), g(best, "AccuracyScore"), g(best, "FluencyScore"),
    g(best, "CompletenessScore"), g(best, "ProsodyScore")))
print()
for w in best.get("Words") or []:
    acc = g(w, "AccuracyScore")
    err = g(w, "ErrorType") or "None"
    weak = [f"{p['Phoneme']}:{int(g(p, 'AccuracyScore'))}"
            for p in (w.get("Phonemes") or [])
            if (g(p, "AccuracyScore") or 100) < 70]
    flag = "  <--" if (acc is not None and acc < 60) or err != "None" else ""
    print(f"  {w['Word']:<18} {str(acc):>5}  {err:<16} {' '.join(weak)}{flag}")
EOF

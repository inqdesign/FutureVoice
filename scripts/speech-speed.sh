#!/usr/bin/env bash
# Retune the fluent self's DEFAULT speaking speed for everyone, without a build.
#
#   scripts/speech-speed.sh              # show what the server says today
#   scripts/speech-speed.sh 0.85         # everyone on the default rung → 0.85
#   scripts/speech-speed.sh default      # back to the app's own 0.9
#
# `app_release.default_speech_speed` is read once per launch by
# AppUpdateService and mirrored into defaults (`SpeechSpeed.remoteDefaultMultiplier`),
# so a change reaches an install the next time it is opened — and only installs
# running build 58 or later, which is where the knob first existed.
#
# Only the DEFAULT rung moves. Normal (1.0) and Slow (0.8) are the ladder's
# ends and stay in the build, where an ear can be put on them first. A learner
# who deliberately picked a rung keeps the rung; its speed is what changes.
#
# Range is ElevenLabs' own 0.7–1.2, and the app DROPS anything outside rather
# than clamping — out of range means the row is wrong, and guessing which edge
# was meant is how a typo becomes a voice nobody recognises.
#
# Cached audio is untouched by construction: the default rung's cache tag is
# empty, so lines already synthesized keep playing as they are (that is
# PhraseAudioStore's standing rule — what is produced is never re-made).
#
# Pick the number with scripts/tts-speed-probe.sh and your ears, never by feel.
set -euo pipefail

PROJECT_REF=chhzjtigzdotacutwcyo
ARG="${1:-}"

raw="$(security find-generic-password -s "Supabase CLI" -w)"
TOKEN="$(echo "${raw#go-keyring-base64:}" | base64 -d)"

run_sql() {
  curl -sf -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
       -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d "$(SQL="$1" python3 -c 'import json,os; print(json.dumps({"query": os.environ["SQL"]}))')"
}

show() {
  run_sql "select coalesce(default_speech_speed::text, 'null (app default, 0.9)') as v
             from app_release where platform = 'ios'" |
    python3 -c 'import json,sys; print("server default speech speed:", json.load(sys.stdin)[0]["v"])'
}

if [[ -z "$ARG" ]]; then show; exit 0; fi

if [[ "$ARG" == "default" || "$ARG" == "null" ]]; then
  VALUE=null
else
  python3 - "$ARG" <<'PY'
import sys
try: v = float(sys.argv[1])
except ValueError: sys.exit(f"not a number: {sys.argv[1]}")
if not (0.7 <= v <= 1.2): sys.exit(f"{v} is outside ElevenLabs' 0.7–1.2 — the app would drop it")
PY
  VALUE="$ARG"
fi

run_sql "update app_release set default_speech_speed = $VALUE where platform = 'ios'" >/dev/null
show
echo "Takes effect on each install's next launch (build 58+)."

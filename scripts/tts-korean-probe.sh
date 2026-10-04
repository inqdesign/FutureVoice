#!/usr/bin/env bash
# How does a NON-KOREAN speaker's clone sound speaking Korean?
#
# A learner of Korean who isn't comfortable reading Korean records the
# ENGLISH clone script (`CloneScriptStore` defaults by self-rated level), so
# their fluent self is an English recording asked to speak Korean — the same
# cross-lingual gap that gave a Korean-recorded clone an Indian accent in
# English (2026-09-30). Nothing had measured it for Korean, and the accent
# remix that fixed English (`VoiceAccentCatalog`) has no Korean option.
#
# Real learners' recordings are not used: an experiment is outside what they
# consented to. The stand-ins need nobody's consent:
#   en-mark, en-emma   English library voices (the app's English presets)
#   proxy-mark         an INSTANT CLONE made the way the app makes one — Mark
#                      reads the app's English clone script, that audio is
#                      uploaded as a new voice, and the voice is DELETED when
#                      the run ends (one of the account's monthly voice adds)
#   ko-sian, ko-joon   native Korean library voices — the CONTROL: if the
#                      judge can't tell these from the English voices, the
#                      judge is useless and only ears decide
#
# Every Korean line is made three ways with the production voice settings
# and the default speed (0.9):
#   turbo      what ships today (eleven_turbo_v2_5, no language_code)
#   turbo-ko   language_code "ko" pinned — one field, same price
#   multi      eleven_multilingual_v2 — ~2x per character
#
# Then: scripts/korean-voice-judge.py <out_dir>   (Gemini, blind)
#
#   scripts/tts-korean-probe.sh [out_dir]
#   NO_PROXY=1     skip the instant clone (ElevenLabs refuses a clone of
#                  its own library voice — 403 detected_captcha_voice)
#   ONLY_CONTROL=1 add only the accent control to an existing run
#   SPEED=0.9
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HOME/Desktop/beta audio/tts-korean-probe}"
SPEED="${SPEED:-0.9}"

KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$KEY" ] || KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$KEY" ] || [ ! -f "$HOME/keys/elevenlabs.txt" ] || KEY="$(tr -d '[:space:]' < "$HOME/keys/elevenlabs.txt")"
[ -n "$KEY" ] || { echo "no ElevenLabs key" >&2; exit 1; }

say() { printf '%s\n' "$*" >&2; }
API="https://api.elevenlabs.io/v1"

VOICES=(
  "en-mark|UgBBYS2sOqTuMpoF3BR0"
  "en-emma|FF59babHL8N8gfTgtBMT"
  "ko-sian|5n5gqmaQi9Ewevrz7bOS"
  "ko-joon|AKF7f2y1L8ktV5vxXILw"
)

# label|text — the fluent self's register (반말) plus one polite scene line.
# Each line leans on what an English mouth gets wrong first.
LINES=(
  "opener|안녕, 몇 년 뒤의 너야. 오늘 이렇게 얘기하게 돼서 진짜 반가워. 요즘 어떻게 지내?"
  "linking|어제 친구랑 저녁을 먹었는데, 국물이 정말 맛있었어."
  "tense|아까 빵집에서 팥빵이랑 쌀과자를 샀는데, 진짜 싸고 달더라."
  "vowels|그건 의외로 어렵지 않아. 천천히 하면 금방 늘어."
  "long|솔직히 처음엔 좀 무서웠는데, 몇 번 해 보니까 생각보다 별거 아니더라고. 너도 분명히 할 수 있을 거야."
  "numbers|회의는 세 시 반이고, 삼십 분쯤 걸릴 거야. 끝나면 일곱 시쯤 집에 갈게."
  "polite|안녕하세요, 아이스 아메리카노 한 잔이랑 따뜻한 라떼 한 잔 주세요."
  "question|그래서 이번 주말엔 뭐 할 거야? 같이 한강 갈래?"
)

mkdir -p "$OUT"

tts() {  # voice_id text model lang outfile
  local body code
  body="$(python3 - "$2" "$3" "$SPEED" "$4" <<'PY'
import json, sys
text, model, speed, lang = sys.argv[1:5]
# Production voice settings — supabase/functions/elevenlabs-tts/index.ts.
settings = {"stability": 0.55, "similarity_boost": 0.90, "style": 0, "use_speaker_boost": True}
s = float(speed)
if 0.7 <= s <= 1.2:
    settings["speed"] = s
body = {"text": text, "model_id": model, "voice_settings": settings}
if lang:
    body["language_code"] = lang
print(json.dumps(body))
PY
)"
  code=$(curl -s -o "$5" -w '%{http_code}' "$API/text-to-speech/$1" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" -d "$body")
  if [ "$code" != "200" ]; then
    say "  ! HTTP $code for $(basename "$5")"; head -c 300 "$5" >&2; say ""; rm -f "$5"; return 1
  fi
}

# ── The proxy clone: Mark reads the app's own English clone script. ──
PROXY_ID=""
cleanup() {
  if [ -n "$PROXY_ID" ]; then
    curl -s -o /dev/null -X DELETE "$API/voices/$PROXY_ID" -H "xi-api-key: $KEY" \
      && say "deleted proxy clone $PROXY_ID"
  fi
}
trap cleanup EXIT

if [ -z "${NO_PROXY:-}" ]; then
  SCRIPT_TEXT="$(python3 - "$ROOT/FutureVoice/Services/CloneScriptStore.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
block = re.search(r'static let english = \[(.*?)\n    \]', src, re.S).group(1)
lines = [l.encode().decode("unicode_escape").encode("latin1").decode("utf-8")
         for l in re.findall(r'"((?:[^"\\]|\\.)*)"', block)]
print(" ".join(lines))
PY
)"
  mkdir -p "$OUT/_proxy"
  say "proxy: Mark reads the English clone script…"
  SPEED=1.0 tts "UgBBYS2sOqTuMpoF3BR0" "$SCRIPT_TEXT" "eleven_multilingual_v2" "" "$OUT/_proxy/clone-sample.mp3"
  resp="$(curl -s "$API/voices/add" -H "xi-api-key: $KEY" \
    -F "name=probe-proxy-mark (delete me)" \
    -F "description=tts-korean-probe stand-in, deleted at end of run" \
    -F "files=@$OUT/_proxy/clone-sample.mp3;type=audio/mpeg")"
  PROXY_ID="$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("voice_id",""))')"
  [ -n "$PROXY_ID" ] || { say "clone failed: $resp"; exit 1; }
  say "proxy clone $PROXY_ID"
  VOICES+=("proxy-mark|$PROXY_ID")
fi

MANIFEST="$OUT/manifest.tsv"
[ -n "${ONLY_CONTROL:-}" ] && [ -f "$MANIFEST" ] || printf 'voice\tline\tvariant\tfile\ttext\n' > "$MANIFEST"
[ -z "${ONLY_CONTROL:-}" ] || VOICES=()

# ── The judge's POSITIVE control: an English voice reading the same lines
# in romanization with language_code "en" — Korean as an English mouth
# would say it. A judge that can't flag THIS can't hear an accent at all.
ROMAN=(
  "annyeong, myeot nyeon dwiui neoya. oneul ireoke yaegihage dwaeseo jinjja ban-gawo. yojeum eotteoke jinae?"
  "eoje chin-gurang jeonyeogeul meogeonneunde, gungmuri jeongmal masisseosseo."
  "akka ppangjibeseo patppangirang ssalgwajareul saanneunde, jinjja ssago daldeora."
  "geugeon uioero eoryeopji ana. cheoncheonhi hamyeon geumbang neureo."
  "soljiki cheoeumen jom museowonneunde, myeot beon hae bonikka saenggakboda byeolgeo anideorago. neodo bunmyeonghi hal su isseul geoya."
  "hoeuineun se si banigo, samsip bunjjeum geollil geoya. kkeunnamyeon ilgop sijjeum jibe galge."
  "annyeonghaseyo, aiseu amerikano han janirang ttatteutan latte han jan juseyo."
  "geuraeseo ibeon jumaren mwo hal geoya? gachi hangang gallae?"
)
if [ -z "${NO_CONTROL:-}" ]; then
  say "accent-control"
  for i in "${!LINES[@]}"; do
    entry="${LINES[$i]}"; label="${entry%%|*}"; text="${entry#*|}"
    file="accent-control-$(printf '%02d' $((i + 1)))-$label-romanized.mp3"
    tts "UgBBYS2sOqTuMpoF3BR0" "${ROMAN[$i]}" "eleven_turbo_v2_5" "en" "$OUT/$file" || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "accent-control" "$label" "romanized" "$file" "$text" >> "$MANIFEST"
  done
fi

for v in ${VOICES[@]+"${VOICES[@]}"}; do
  vlabel="${v%%|*}"; vid="${v#*|}"
  say "$vlabel"
  n=0
  for entry in "${LINES[@]}"; do
    n=$((n + 1)); label="${entry%%|*}"; text="${entry#*|}"
    for variant in turbo turbo-ko multi; do
      case "$variant" in
        turbo)    model="eleven_turbo_v2_5";      lang="";;
        turbo-ko) model="eleven_turbo_v2_5";      lang="ko";;
        multi)    model="eleven_multilingual_v2"; lang="";;
      esac
      file="$vlabel-$(printf '%02d' "$n")-$label-$variant.mp3"
      tts "$vid" "$text" "$model" "$lang" "$OUT/$file" || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$vlabel" "$label" "$variant" "$file" "$text" >> "$MANIFEST"
    done
  done
done

say ""
say "done → $OUT"
say "next: scripts/korean-voice-judge.py \"$OUT\""

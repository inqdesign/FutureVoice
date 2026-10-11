#!/usr/bin/env bash
# Can a cheaper TTS vendor still sound like YOU? A/B by ear across vendors.
#
# A talk minute costs ~$0.049 and ~$0.030 of it is ElevenLabs (turbo, 0.5
# credit/char on Pro ≈ $82 per 1M chars). Cartesia and Fish Audio list at
# roughly 2–5x less. Price is the easy half; the product is speaker
# similarity — the learner must believe the voice is theirs — and above all
# CROSS-LINGUAL similarity (a clone recorded in one language speaking
# another), which no public benchmark measures. So this is settled by ear,
# same discipline as tts-model-probe.sh.
#
# What it does, from ONE original recording:
#   1. clones it fresh on every vendor whose key it finds (ElevenLabs too —
#      the live clone may be an accent remix, so it is not a fair baseline);
#   2. synthesizes the same lines on each, at the app's speed (0.9);
#   3. writes <n>-<label>-<vendor>.mp3 side by side + manifest.tsv with
#      chars, time-to-first-byte and an estimated cost per talk minute;
#   4. deletes every voice it created (KEEP_VOICES=1 to keep them).
#
#   scripts/tts-vendor-probe.sh <your-recording> [out_dir]
#   CLONE_LANG=en       language the recording is read in (default en)
#   CLIP_SECONDS=60     trim the recording before cloning (0 = whole file)
#   FISH_MODEL=s2.1-pro Fish Audio model header (s1, s2-pro, s2.1-pro)
#   CARTESIA_MODEL=sonic-3.6
#   SPEED=0.9
#   LINES_FILE=path     `label|lang|text` lines instead of the built-ins
#
# Keys (a vendor without one is skipped):
#   ElevenLabs  $ELEVENLABS_API_KEY, gateway/.dev.vars, or ~/keys/elevenlabs.txt
#   Cartesia    $CARTESIA_API_KEY or ~/keys/cartesia.txt
#   Fish Audio  $FISH_API_KEY or ~/keys/fish.txt
#
# Costs: one clone per vendor (ElevenLabs: one of the month's voice
# add/edits) + ~7 short lines each. Run it yourself — nothing here runs on
# its own.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-}"   # YOUR OWN recording — never a learner's (their consent covers ElevenLabs only)
STAMP="$(date +%Y%m%d-%H%M)"
OUT="${2:-$HOME/Desktop/beta audio/tts-vendor-probe-$STAMP}"
CLONE_LANG="${CLONE_LANG:-en}"
CLIP_SECONDS="${CLIP_SECONDS:-60}"
FISH_MODEL="${FISH_MODEL:-s2.1-pro}"
CARTESIA_MODEL="${CARTESIA_MODEL:-sonic-3.6}"
CARTESIA_VERSION="2026-08-14"
SPEED="${SPEED:-0.9}"

say() { printf '%s\n' "$*" >&2; }
[ -n "$SRC" ] && [ -f "$SRC" ] || { say "usage: $0 <your-own-recording.(wav|m4a|mp3)> [out_dir]"; exit 1; }

key_from() { # env-value, file
  if [ -n "$1" ]; then printf '%s' "$1"
  elif [ -f "$2" ]; then tr -d '[:space:]' < "$2"
  fi
}
EL_KEY="${ELEVENLABS_API_KEY:-}"
[ -n "$EL_KEY" ] || EL_KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" 2>/dev/null | tr -d '"')"
[ -n "$EL_KEY" ] || EL_KEY="$(key_from "" "$HOME/keys/elevenlabs.txt")"
CA_KEY="$(key_from "${CARTESIA_API_KEY:-}" "$HOME/keys/cartesia.txt")"
FI_KEY="$(key_from "${FISH_API_KEY:-}" "$HOME/keys/fish.txt")"

# label|lang|text — en is the same-language case for an English recording;
# de / ja / ko are the cross-lingual ones, which is what this app does.
LINES=(
  "en-call|en|Oh nice, so you finally tried that place? I keep hearing about it, but I never get around to going."
  "en-long|en|So the way it usually works is, you send over the brief on Monday, we come back with two directions by Thursday, and then we pick one together."
  "en-scene|en|I'm sorry, but this isn't what I ordered. I asked for the one without cheese. Could you check the ticket?"
  "de-call|de|Ach, echt? Das klingt richtig gut. Und, wie war das Essen da? Ich wollte schon lange mal hin."
  "ja-call|ja|へえ、そうなんだ。それで、結局どうしたの？　僕だったら、たぶん次の日にもう一回行っちゃうな。"
  "ko-call|ko|아 진짜? 그거 완전 좋은데. 그래서 결국 어떻게 했어? 나였으면 바로 다음 날 또 갔을 거야."
)
if [ -n "${LINES_FILE:-}" ]; then
  LINES=(); while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < "$LINES_FILE"
fi

mkdir -p "$OUT"
REF="$OUT/reference.wav"
if [ "$CLIP_SECONDS" != "0" ]; then
  ffmpeg -loglevel error -y -i "$SRC" -t "$CLIP_SECONDS" -ac 1 -ar 44100 "$REF"
else
  ffmpeg -loglevel error -y -i "$SRC" -ac 1 -ar 44100 "$REF"
fi
say "reference  $REF ($(afinfo "$REF" | sed -n 's/.*estimated duration: \([0-9.]*\).*/\1/p') s)"
say "out        $OUT"
say ""

MANIFEST="$OUT/manifest.tsv"
printf 'n\tlabel\tlang\tvendor\tchars\tbytes_utf8\tttfb_s\ttotal_s\tfile\ttext\n' > "$MANIFEST"
CREATED=()   # vendor:id, deleted at exit

cleanup() {
  [ "${KEEP_VOICES:-0}" = "1" ] && { say "keeping voices: ${CREATED[*]:-none}"; return; }
  for v in "${CREATED[@]:-}"; do
    [ -n "$v" ] || continue
    vendor="${v%%:*}"; id="${v#*:}"
    case "$vendor" in
      eleven)   curl -s -o /dev/null -X DELETE "https://api.elevenlabs.io/v1/voices/$id" -H "xi-api-key: $EL_KEY" ;;
      cartesia) curl -s -o /dev/null -X DELETE "https://api.cartesia.ai/voices/$id" -H "Authorization: Bearer $CA_KEY" -H "Cartesia-Version: $CARTESIA_VERSION" ;;
      fish)     curl -s -o /dev/null -X DELETE "https://api.fish.audio/model/$id" -H "Authorization: Bearer $FI_KEY" ;;
    esac
    say "deleted $vendor voice $id"
  done
}
trap cleanup EXIT

json_field() { python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for k in sys.argv[1:]:
    if isinstance(d,dict) and d.get(k): print(d[k]); break' "$@"; }

# ── clone on each vendor ────────────────────────────────────────────────
VENDORS=()
EL_VOICE=""; CA_VOICE=""; FI_VOICE=""

if [ -n "$EL_KEY" ]; then
  resp=$(curl -s -X POST "https://api.elevenlabs.io/v1/voices/add" -H "xi-api-key: $EL_KEY" \
    -F "name=vendor-probe-$STAMP" -F "files=@$REF;type=audio/wav" -F "remove_background_noise=false")
  EL_VOICE=$(printf '%s' "$resp" | json_field voice_id)
  if [ -n "$EL_VOICE" ]; then CREATED+=("eleven:$EL_VOICE"); VENDORS+=(eleven); say "cloned  eleven    $EL_VOICE"
  else say "! eleven clone failed: ${resp:0:300}"; fi
else say "- eleven   no key, skipped"; fi

if [ -n "$CA_KEY" ]; then
  resp=$(curl -s -X POST "https://api.cartesia.ai/voices/clone" \
    -H "Authorization: Bearer $CA_KEY" -H "Cartesia-Version: $CARTESIA_VERSION" \
    -F "clip=@$REF;type=audio/wav" -F "name=vendor-probe-$STAMP" -F "language=$CLONE_LANG")
  CA_VOICE=$(printf '%s' "$resp" | json_field id)
  if [ -n "$CA_VOICE" ]; then CREATED+=("cartesia:$CA_VOICE"); VENDORS+=(cartesia); say "cloned  cartesia  $CA_VOICE"
  else say "! cartesia clone failed: ${resp:0:300}"; fi
else say "- cartesia no key, skipped (~/keys/cartesia.txt)"; fi

if [ -n "$FI_KEY" ]; then
  resp=$(curl -s -X POST "https://api.fish.audio/model" -H "Authorization: Bearer $FI_KEY" \
    -F "type=tts" -F "title=vendor-probe-$STAMP" -F "train_mode=fast" -F "visibility=private" \
    -F "enhance_audio_quality=false" -F "voices=@$REF;type=audio/wav")
  FI_VOICE=$(printf '%s' "$resp" | json_field _id id)
  if [ -n "$FI_VOICE" ]; then CREATED+=("fish:$FI_VOICE"); VENDORS+=(fish); say "cloned  fish      $FI_VOICE"
  else say "! fish clone failed: ${resp:0:300}"; fi
else say "- fish     no key, skipped (~/keys/fish.txt)"; fi

[ ${#VENDORS[@]} -gt 0 ] || { say "no vendor cloned — nothing to compare"; exit 1; }
say ""

# ── synthesize ──────────────────────────────────────────────────────────
body() { # vendor lang text
  python3 - "$@" "$SPEED" "$EL_VOICE" "$CA_VOICE" "$FI_VOICE" "$CARTESIA_MODEL" <<'PY'
import json, sys
vendor, lang, text, speed, el, ca, fi, ca_model = sys.argv[1:9]
s = float(speed)
if vendor == "eleven":
    # Production settings (supabase/functions/elevenlabs-tts). style MUST stay 0.
    print(json.dumps({"text": text, "model_id": "eleven_turbo_v2_5",
        "voice_settings": {"stability": 0.55, "similarity_boost": 0.90,
                           "style": 0, "use_speaker_boost": True, "speed": s}}))
elif vendor == "cartesia":
    print(json.dumps({"model_id": ca_model, "transcript": text, "voice": {"id": ca},
        "language": lang,
        "output_format": {"container": "mp3", "sample_rate": 44100, "bit_rate": 128000},
        "generation_config": {"speed": s}}))
elif vendor == "fish":
    print(json.dumps({"text": text, "reference_id": fi, "format": "mp3",
        "prosody": {"speed": s}, "latency": "balanced"}))
PY
}

n=0
for entry in "${LINES[@]}"; do
  n=$((n + 1))
  label="${entry%%|*}"; rest="${entry#*|}"; lang="${rest%%|*}"; text="${rest#*|}"
  chars=$(printf '%s' "$text" | wc -m | tr -d ' ')
  bytes=$(printf '%s' "$text" | wc -c | tr -d ' ')
  for vendor in "${VENDORS[@]}"; do
    file="$OUT/$(printf '%02d' "$n")-$label-$vendor.mp3"
    b="$(body "$vendor" "$lang" "$text")"
    case "$vendor" in
      eleven)   url="https://api.elevenlabs.io/v1/text-to-speech/$EL_VOICE"; h=(-H "xi-api-key: $EL_KEY") ;;
      cartesia) url="https://api.cartesia.ai/tts/bytes"; h=(-H "Authorization: Bearer $CA_KEY" -H "Cartesia-Version: $CARTESIA_VERSION") ;;
      fish)     url="https://api.fish.audio/v1/tts"; h=(-H "Authorization: Bearer $FI_KEY" -H "model: $FISH_MODEL") ;;
    esac
    stats=$(curl -s -o "$file" -w '%{http_code} %{time_starttransfer} %{time_total}' "$url" \
      "${h[@]}" -H "Content-Type: application/json" -d "$b")
    read -r code ttfb total <<< "$stats"
    if [ "$code" != "200" ]; then
      say "  ! $label/$vendor → HTTP $code: $(head -c 200 "$file")"; rm -f "$file"; continue
    fi
    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$label" "$lang" "$vendor" "$chars" "$bytes" \
      "$ttfb" "$total" "$(basename "$file")" "$text" >> "$MANIFEST"
    say "  $(printf '%-9s %-8s' "$label" "$vendor") ttfb ${ttfb}s  total ${total}s"
  done
done

# ── summary: latency + list-price cost per talk minute (365 chars/min) ──
say ""
python3 - "$MANIFEST" <<'PY' >&2
import csv, sys, statistics as st
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
# List prices per 1M units, Oct 2026 — CHECK the vendor pages before deciding.
# eleven: turbo 0.5 cr/char at Pro ($99 / 600k cr). cartesia: ~$37–50 / 1M
# credits at 1 cr/char (clones may carry a multiplier). fish: $15 / 1M UTF-8 bytes.
price = {"eleven": ("char", 82.5), "cartesia": ("char", 45.0), "fish": ("byte", 15.0)}
print(f"{'vendor':9} {'ttfb median':>12} {'$/talk-min en':>14} {'$/talk-min ko/ja':>17}")
for v in sorted({r["vendor"] for r in rows}):
    rs = [r for r in rows if r["vendor"] == v]
    ttfb = st.median(float(r["ttfb_s"]) for r in rs)
    unit, p = price[v]
    en = 365 * p / 1e6
    cjk = 365 * (3 if unit == "byte" else 1) * p / 1e6
    print(f"{v:9} {ttfb:>11.2f}s {en:>13.4f}  {cjk:>16.4f}")
print("\nttfb here is a buffered HTTP request, not the streaming socket the call uses —")
print("compare vendors to each other, not to the live call.")
PY

say ""
say "Listen in groups (same number, -eleven / -cartesia / -fish)."
say "Ask: is that ME? — first on en (same language), then de / ja / ko."
say "  open \"$OUT\""

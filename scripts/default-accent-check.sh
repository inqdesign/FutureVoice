#!/usr/bin/env bash
# Did the server's default accent land on an account? (2026-10-08)
#
#   scripts/default-accent-check.sh <email | user_id> [--play]
#
# Prints the account's voices: which one the app uses, whether it came from an
# old build (accent_by_server), and the remix it speaks through (speak_as_*).
# With --play it synthesizes the same English line with the plain clone and
# with the remix, saves both to ~/Desktop/beta audio/default-accent-check/ and
# plays them one after the other, so the difference is heard, not inferred.
# See supabase/functions/_shared/default-accent.ts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHO="${1:?usage: $0 <email | user_id> [--play]}"
PLAY="${2:-}"

RAW="$(security find-generic-password -s "Supabase CLI" -w)"
TOKEN="$(printf '%s' "${RAW#go-keyring-base64:}" | base64 -d)"
q() {
  curl -s -X POST "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}

if [[ "$WHO" == *@* ]]; then
  WHERE="v.user_id = (select id from auth.users where lower(email) = lower('$WHO') limit 1)"
else
  WHERE="v.user_id = '$WHO'"
fi

ROWS="$(q "select v.elevenlabs_voice_id, v.is_active, v.accent_by_server, v.speak_as_voice_id, v.speak_as_language, v.speak_as_accent, v.speak_as_started_at, to_char(v.created_at, 'MM-DD HH24:MI:SS') as created from voice_clones v where $WHERE order by v.created_at")"
python3 - "$ROWS" <<'EOF'
import json, sys
rows = json.loads(sys.argv[1])
if not isinstance(rows, list) or not rows:
    print("no voices for that account (yet)"); sys.exit()
for r in rows:
    tag = "ACTIVE (the app's voice)" if r["is_active"] else "inactive"
    print(f'{r["created"]}  {r["elevenlabs_voice_id"]}  {tag}')
    if r["accent_by_server"]:
        if r["speak_as_voice_id"]:
            print(f'    old-build clone → speaks {r["speak_as_language"]} as {r["speak_as_voice_id"]} ({r["speak_as_accent"]})')
        elif r["speak_as_started_at"]:
            print(f'    old-build clone → remix IN PROGRESS since {r["speak_as_started_at"]} (~25 s)')
        else:
            print('    old-build clone → no remix yet (made on its first English/German line)')
EOF

[ "$PLAY" = "--play" ] || exit 0
PAIR="$(python3 - "$ROWS" <<'EOF'
import json, sys
for r in json.loads(sys.argv[1]):
    if r["is_active"] and r["speak_as_voice_id"]:
        print(r["elevenlabs_voice_id"], r["speak_as_voice_id"], r["speak_as_language"]); break
EOF
)"
[ -n "$PAIR" ] || { echo "nothing to play: the active voice has no remix"; exit 0; }
read -r PLAIN REMIX LANG <<<"$PAIR"
KEY="$(sed -n 's/^ELEVENLABS_API_KEY *= *//p' "$ROOT/gateway/.dev.vars" | tr -d '"')"
OUT="$HOME/Desktop/beta audio/default-accent-check"; mkdir -p "$OUT"
if [ "$LANG" = "de" ]; then
  TEXT="Also, morgen früh gehe ich zuerst zum Bäcker. Danach fahre ich mit dem Zug nach München. Später rufe ich dich an, ist das okay?"
else
  TEXT="Right, let me think about tomorrow. I'll grab a bottle of water on the way, probably around half past eight. I'll call you when I get there, okay?"
fi
say_it() {
  curl -s -o "$OUT/$2.mp3" -w "$2 %{http_code}\n" \
    "https://api.elevenlabs.io/v1/text-to-speech/$1?model_id=eleven_turbo_v2_5" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1], "model_id": "eleven_turbo_v2_5", "voice_settings": {"style": 0, "speed": 0.9}}))' "$TEXT")"
}
say_it "$PLAIN" "1-plain"
say_it "$REMIX" "2-remix"
say -v Yuna "원래 클론"; afplay "$OUT/1-plain.mp3"; sleep 1
say -v Yuna "리믹스"; afplay "$OUT/2-remix.mp3"
echo "saved in $OUT"

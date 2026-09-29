#!/usr/bin/env bash
# Say something to everyone, or to named accounts.
#
# The text is YOURS — this script never composes a sentence. Pass one
# language and everybody gets those words; pass several and each learner
# gets the one they chose in the app (`device_tokens.app_language`, which is
# the only language rule this app has: chrome follows the learner's pick,
# never the device's).
#
#   ./scripts/push-broadcast.sh --ko "제목" "본문"
#   ./scripts/push-broadcast.sh --ko "제목" "본문" --en "Title" "Body"
#   ./scripts/push-broadcast.sh --ko "제목" "본문" --users <uuid>,<uuid>
#
# DRY RUN BY DEFAULT. It prints what it would send and stops; add --send to
# actually deliver. A push cannot be recalled, so the confirmation is the
# whole point of the flag.
#
# Every send carries an id, and `push_sends` refuses the same (user, kind,
# dedupe_key) twice — so re-running the same announcement is a no-op rather
# than a second buzz. A NEW announcement needs a new --id (the default is a
# timestamp, so two runs are two announcements unless you say otherwise).
set -euo pipefail

URL="${SUPABASE_URL:-}"
SECRET="${PUSH_SECRET:-}"
ID="broadcast-$(date -u +%Y%m%d%H%M%S)"
USERS=""
SEND=0
TEXTS="{}"

add_text() {  # lang title body
  TEXTS=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1]); d[sys.argv[2]] = {"title": sys.argv[3], "body": sys.argv[4]}
print(json.dumps(d, ensure_ascii=False))' "$TEXTS" "$1" "$2" "$3")
}

while [ $# -gt 0 ]; do
  case "$1" in
    --send)  SEND=1; shift ;;
    --id)    ID="$2"; shift 2 ;;
    --users) USERS="$2"; shift 2 ;;
    --*)     add_text "${1#--}" "$2" "$3"; shift 3 ;;
    *)       echo "unexpected argument: $1"; exit 1 ;;
  esac
done

[ "$TEXTS" != "{}" ] || { echo "nothing to say — pass at least --<lang> <title> <body>"; exit 1; }
[ -n "$URL" ] && [ -n "$SECRET" ] || {
  echo "set SUPABASE_URL and PUSH_SECRET (the same value as the function's env)"; exit 1; }

body=$(python3 -c '
import json, sys
users = [u for u in sys.argv[3].split(",") if u]
out = {"kind": "broadcast", "dedupe_key": sys.argv[1], "texts": json.loads(sys.argv[2]),
       "url": "futurevoice://practice", "collapse_id": sys.argv[1]}
if users: out["user_ids"] = users
print(json.dumps(out, ensure_ascii=False))' "$ID" "$TEXTS" "$USERS")

echo "announcement  $ID"
python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]), indent=2, ensure_ascii=False))' "$body"
echo

if [ "$SEND" -ne 1 ]; then
  echo "DRY RUN — nothing was sent. Add --send to deliver it."
  exit 0
fi

curl -sS -X POST "$URL/functions/v1/push-send" \
  -H "X-Push-Secret: $SECRET" -H "Content-Type: application/json" \
  -d "$body"
echo

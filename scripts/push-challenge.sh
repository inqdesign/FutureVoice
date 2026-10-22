#!/usr/bin/env bash
# Tell a language's learners that a new speech challenge is up.
#
#   ./scripts/push-challenge.sh <challenge-id>           # dry run: who, how many, the words
#   ./scripts/push-challenge.sh <challenge-id> --send    # deliver
#   ./scripts/push-challenge.sh <id> --ko "제목" "본문 {title}"   # your own words for one language
#
# Who: everyone who learns the challenge's language — they talked in it
# (`talk_seconds_by_language`), spent something on it (`usage_ledger`
# metadata.language) or published an intro in it (`public_personas`) — with
# a production push token, a build that has challenges (87, 1.1.7, the first
# with the Speech tab's boards), and no entry on this board yet. A learner
# of two languages gets the push for either; if the app is on the other one
# when they tap, they land on the Speech tab and nothing more.
#
# What: the chrome line in the language each learner picked for the app
# (`device_tokens.app_language`, falling back to en), with the challenge's
# own title — MATERIAL, so in the target language — inside it. `{title}` in
# an override is replaced the same way. The tap opens
# `futurevoice://speech?id=<challenge>`, which opens that challenge from
# LINK_BUILD on; an older build just opens the app.
#
# Each learner gets it ONCE per challenge: the dedupe key is the challenge
# id, and `push_sends` refuses the same (user, kind, dedupe_key) twice, so a
# second run only reaches people who joined the language since. An install
# that never allowed notifications accepts the push and iOS drops it
# silently; nothing here can tell. Android has no server push yet.
#
# Needs: the Supabase CLI login in the keychain (to read the challenge and
# the audience) and SUPABASE_URL + PUSH_SECRET (to send, as push-broadcast.sh).
set -euo pipefail

ID="${1:-}"
[[ "$ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "usage: $0 <challenge-id> [--send] [--<lang> <title> <body>]"; exit 1; }
shift
SEND=0
OVERRIDES="{}"
while [ $# -gt 0 ]; do
  case "$1" in
    --send) SEND=1; shift ;;
    --*)    OVERRIDES=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1]); d[sys.argv[2]] = {"title": sys.argv[3], "body": sys.argv[4]}
print(json.dumps(d, ensure_ascii=False))' "$OVERRIDES" "${1#--}" "$2" "$3"); shift 3 ;;
    *)      echo "unexpected argument: $1"; exit 1 ;;
  esac
done

REF="chhzjtigzdotacutwcyo"
RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)

query() {
  curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}

challenge=$(query "select language, title, retired_at from public.speech_challenges where id = '$ID'")

read -r -d '' SQL <<EOF || true
with c as (select language from public.speech_challenges where id = '$ID'),
learners as (
  select t.user_id from public.talk_seconds_by_language t, c where t.language = c.language
  union
  select l.user_id from public.usage_ledger l, c where l.metadata->>'language' = c.language
  union
  select p.owner_user_id from public.public_personas p, c
  where p.language = c.language and p.owner_user_id is not null
)
select u.user_id::text as user_id,
       coalesce((select d.app_language from public.device_tokens d
                 where d.user_id = u.user_id and d.environment = 'production'
                 order by d.updated_at desc limit 1), 'en') as lang,
       coalesce((select (e.properties->>'build')::int from public.client_events e
                 where e.user_id = u.user_id and e.properties->>'build' ~ '^[0-9]+\$'
                 order by e.created_at desc limit 1), 0) as build
from learners u
where u.user_id is not null
  and exists (select 1 from public.device_tokens d
              where d.user_id = u.user_id and d.environment = 'production')
  and not exists (select 1 from public.speech_challenge_entries s
                  where s.challenge_id = '$ID' and s.user_id = u.user_id)
order by 1
EOF

audience=$(query "$SQL")

body=$(python3 - "$ID" "$challenge" "$audience" "$OVERRIDES" <<'PY'
import json, sys
cid, challenge, rows, overrides = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3]), json.loads(sys.argv[4])
if isinstance(challenge, dict) or not challenge:
    sys.exit(f"no such challenge: {challenge}")
if isinstance(rows, dict):
    sys.exit(f"audience query failed: {rows}")
c = challenge[0]
if c["retired_at"]:
    sys.exit(f"challenge is retired ({c['retired_at']}); nobody can enter it")

FIRST_CHALLENGE_BUILD = 87   # 1.1.7, the first build with challenge boards
LINK_BUILD = 118             # the first build that opens futurevoice://speech?id=

nb = " "
texts = {
    "ko": {"title": "새 스피치 챌린지가 나왔어요",
           "body": "‘{title}’, 소리 내어 읽고 리더보드에 이름을 올려 보세요."},
    "ja": {"title": "新しいスピーチチャレンジ",
           "body": "「{title}」を声に出して読んで、ランキングに挑戦しましょう。"},
    "en": {"title": "A new speech challenge is up",
           "body": "Read “{title}” out loud and get on the leaderboard."},
    "de": {"title": "Neue Challenge zum Vorlesen",
           "body": "„{title}“ ist da. Lies es laut vor und komm auf die Rangliste."},
    "es": {"title": "Hay un reto nuevo",
           "body": "Ya está «{title}». Léelo en voz alta y entra en la clasificación."},
    "fr": {"title": "Un nouveau défi",
           "body": f"«{nb}{{title}}{nb}» est en ligne. Lis-le à voix haute et entre au classement."},
    "zh-Hant": {"title": "新的演講挑戰",
                "body": "「{title}」上線了。大聲唸出來，登上排行榜。"},
    "zh-Hans": {"title": "新的演讲挑战",
                "body": "“{title}”上线了。大声读出来，登上排行榜。"},
}
texts.update(overrides)
for t in texts.values():
    t["title"] = t["title"].replace("{title}", c["title"])
    t["body"] = t["body"].replace("{title}", c["title"])

sent = [r for r in rows if r["build"] >= FIRST_CHALLENGE_BUILD]
skipped = [r for r in rows if r["build"] < FIRST_CHALLENGE_BUILD]
langs = {}
for r in sent:
    langs[r["lang"]] = langs.get(r["lang"], 0) + 1
print(json.dumps({
    "summary": {
        "challenge": f"{c['language']} · {c['title']}",
        "to": len(sent), "app_languages": langs,
        "opens_the_challenge": sum(r["build"] >= LINK_BUILD for r in sent),
        "opens_the_app_only": sum(r["build"] < LINK_BUILD for r in sent),
        "skipped_no_challenges_build": len(skipped),
    },
    "payload": {"kind": "speech_challenge", "dedupe_key": f"challenge-{cid}",
                "environment": "production",
                "user_ids": [r["user_id"] for r in sent], "texts": texts,
                "url": f"futurevoice://speech?id={cid}", "collapse_id": f"challenge-{cid}"},
}, ensure_ascii=False))
PY
)

python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print(json.dumps(d["summary"], indent=2, ensure_ascii=False))
print()
for lang, t in d["payload"]["texts"].items():
    print("  %-8s %s\n           %s" % (lang, t["title"], t["body"]))
print()' "$body"

if [ "$SEND" -ne 1 ]; then
  echo "DRY RUN — nothing was sent. Add --send to deliver it."
  exit 0
fi

URL="${SUPABASE_URL:-}"
SECRET="${PUSH_SECRET:-}"
[ -n "$URL" ] && [ -n "$SECRET" ] || {
  echo "set SUPABASE_URL and PUSH_SECRET (the same value as the function's env)"; exit 1; }

count=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["payload"]["user_ids"]))' "$body")
[ "$count" -gt 0 ] || { echo "nobody to tell"; exit 0; }

curl -sS -X POST "$URL/functions/v1/push-send" \
  -H "X-Push-Secret: $SECRET" -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["payload"], ensure_ascii=False))' "$body")"
echo

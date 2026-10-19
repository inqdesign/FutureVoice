#!/usr/bin/env bash
# Push the free-minutes report (TrialReport, 2026-10-19) to learners who
# spent their free minutes and left without subscribing.
#
# Who: an account with NO subscription row ever (a lapsed subscriber's empty
# pool is not a trial ending), not unlimited, under a minute left
# (`AccountStatus.needsSubscription`), who actually talked, whose last talk
# was more than a day ago (someone who just met the wall still has the report
# on screen), and who has a production push token. The tap opens
# `futurevoice://trialreport`, which raises the report on the phone — the
# report is built on the device from its own talks; nothing is sent but the
# notice.
#
# Each learner gets it ONCE, ever: the id is fixed, and `push_sends` refuses
# the same (user, kind, dedupe_key) twice. So running this again — daily, by
# hand or on a schedule — only reaches people who are new to the list.
#
# Builds before the one that carries the report open the app at Talk and
# nothing else, so send after that build is live (and give App Store
# auto-update a few days). An install that never allowed notifications
# accepts the push and iOS drops it silently; nothing here can tell.
#
#   ./scripts/push-trial-report.sh          # dry run: who, how many, the words
#   ./scripts/push-trial-report.sh --send   # deliver
#
# push-send must be the version that reads `environment` (2026-10-20) or the
# notice can be claimed on a sandbox or dead token and never reach the phone.
#
# Needs: the Supabase CLI login in the keychain (to read the audience) and
# SUPABASE_URL + PUSH_SECRET (to send, as push-broadcast.sh).
set -euo pipefail

SEND=0
[ "${1:-}" = "--send" ] && SEND=1

REF="chhzjtigzdotacutwcyo"
RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)

read -r -d '' SQL <<'EOF' || true
select c.user_id::text as user_id,
       coalesce((select d.app_language from device_tokens d
                 where d.user_id = c.user_id and d.environment = 'production'
                 order by d.updated_at desc limit 1), '?') as lang
from user_credits c
where c.balance < 60
  and coalesce(c.unlimited, false) = false
  and not exists (select 1 from user_subscriptions s where s.user_id = c.user_id)
  and exists (select 1 from device_tokens d where d.user_id = c.user_id and d.environment = 'production')
  and (select max(l.created_at) from usage_ledger l
       where l.user_id = c.user_id and l.action = 'talk_time') < now() - interval '1 day'
order by c.user_id
EOF

audience=$(curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$SQL")")

body=$(python3 - "$audience" <<'PY'
import json, sys
rows = json.loads(sys.argv[1])
if isinstance(rows, dict):
    sys.exit(f"audience query failed: {rows}")
texts = {
    "ko": {"title": "무료 20분 리포트가 준비됐어요",
           "body": "그동안 한 대화로 내 레벨을 확인하고, 첫 테스트를 풀고, 앞으로의 루틴까지 받아 보세요."},
    "ja": {"title": "無料20分のレポートができました",
           "body": "これまでの会話から、今のレベル、はじめてのテスト、これからのルーティンをまとめました。"},
    "en": {"title": "Your free 20 minutes, in a report",
           "body": "Your level, a first test made from what you said, and a routine to keep going."},
    "de": {"title": "Deine 20 Gratisminuten als Bericht",
           "body": "Dein Niveau, ein erster Test aus deinen eigenen Sätzen und eine Routine zum Weitermachen."},
    "es": {"title": "Tus 20 minutos gratis, en un informe",
           "body": "Tu nivel, un primer test hecho con lo que dijiste y una rutina para seguir."},
    "fr": {"title": "Tes 20 minutes gratuites, en un bilan",
           "body": "Ton niveau, un premier test tiré de ce que tu as dit et une routine pour continuer."},
    "zh-Hant": {"title": "你的免費 20 分鐘報告",
                "body": "看看你的等級，做一份用你說過的話出的測驗，再拿一份接下來的作息。"},
    "zh-Hans": {"title": "你的免费 20 分钟报告",
                "body": "看看你的等级，做一份用你说过的话出的测验，再拿一份接下来的作息。"},
}
langs = {}
for r in rows:
    langs[r["lang"]] = langs.get(r["lang"], 0) + 1
print(json.dumps({
    "count": len(rows), "langs": langs,
    "payload": {"kind": "trial_report", "dedupe_key": "trial-report", "environment": "production",
                "user_ids": [r["user_id"] for r in rows], "texts": texts,
                "url": "futurevoice://trialreport", "collapse_id": "trial-report"},
}, ensure_ascii=False))
PY
)

python3 - "$body" <<'PY'
import json, sys
b = json.loads(sys.argv[1])
print(f"audience  {b['count']} learners  {b['langs']}")
for lang in sorted(set(b["langs"]) | {"en"}):
    t = b["payload"]["texts"].get(lang) or b["payload"]["texts"]["en"]
    print(f"  [{lang}] {t['title']}\n        {t['body']}")
print("(already-sent learners are skipped by push_sends, so the delivered count can be lower)")
PY

if [ "$SEND" -ne 1 ]; then
  echo "DRY RUN, nothing was sent. Add --send to deliver it."
  exit 0
fi

: "${SUPABASE_URL:?set SUPABASE_URL}"; : "${PUSH_SECRET:?set PUSH_SECRET}"
payload=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["payload"], ensure_ascii=False))' "$body")
[ "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["user_ids"]))' "$payload")" -gt 0 ] \
  || { echo "nobody to send to"; exit 0; }
curl -sS -X POST "$SUPABASE_URL/functions/v1/push-send" \
  -H "X-Push-Secret: $PUSH_SECRET" -H "Content-Type: application/json" -d "$payload"
echo

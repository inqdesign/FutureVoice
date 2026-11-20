#!/usr/bin/env bash
# Monthly community recap — the Supabase half of the numbers. READ-ONLY.
#
#   marketing/recaps/supabase.sh [SINCE] [UNTIL]
#     SINCE  default 2026-09-12 (launch; the recap is cumulative)
#     UNTIL  default now
#
# Prints totals (real numbers may go on a card) and shares (percent only).
# Never put a count of PEOPLE on a card: the `callers` line is the denominator,
# for the lead's eyes only. The PostHog half is posthog.md.
#
# Test accounts: read from admin/src/assemble.ts (TEST_IDS, TEST_EMAILS, OWNER_ID)
# plus the synthetic/old ids by prefix, so this list never drifts from the console's.
set -euo pipefail
cd "$(dirname "$0")/../.."

SINCE="${1:-2026-09-12}"
UNTIL="${2:-$(date -u +%Y-%m-%dT%H:%M:%S)}"

RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
q() {
  curl -s -X POST "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"query":sys.argv[1]}))' "$1")"
  echo
}

IDS=$(sed -n '/const OWNER_ID/,/^]);/p' admin/src/assemble.ts | grep -o '"[0-9a-f-]\{36\}"' | tr '"' "'" | paste -sd, -)
EMAILS=$(sed -n '/const TEST_EMAILS/,/^]);/p' admin/src/assemble.ts | grep -o '"[^"]*@[^"]*"' | tr '"' "'" | paste -sd, -)
EX="(select user_id from user_directory where user_id in ($IDS) or lower(email) in ($EMAILS)
     or user_id::text like '3cad242a%' or user_id::text like 'c283db85%'
     or user_id::text like 'a52338b4%' or user_id::text like 'c7565d27%')"
W="created_at >= '$SINCE' and created_at < '$UNTIL'"
T="with t as (select user_id, created_at,
       coalesce((metadata->>'call_seconds')::numeric,(metadata->>'seconds')::numeric,0) s,
       metadata->>'session_id' sid, metadata->>'language' lang, metadata->>'mode' mode
     from usage_ledger where action='talk_time' and $W and user_id not in $EX)"
C="(select distinct user_id from usage_ledger where action='talk_time' and $W and user_id not in $EX)"

echo "== window $SINCE .. $UNTIL"
echo "== TOTALS (real numbers OK): call hours, calls"
q "$T select round(sum(s)/3600,1) call_hours, count(distinct sid) calls, count(distinct user_id) callers_DO_NOT_PRINT from t"
echo "== by month (call hours) — for a 'this month' line"
q "$T select to_char(date_trunc('month',created_at),'YYYY-MM') m, round(sum(s)/3600,1) h from t group by 1 order by 1"
echo "== turns spoken (a FLOOR: only calls that sent a session record) — say 'more than N'"
q "select sum((properties->>'turns')::int) turns from client_events where event='talk_rt_session' and $W and user_id not in $EX"
echo "== languages by call time (percent)"
q "$T select coalesce(lang,'?') lang, round(100*sum(s)/sum(sum(s)) over(),1) pct from t group by 1 order by 2 desc"
echo "== call modes by time (pron = pronunciation call)"
q "$T select coalesce(mode,'call') mode, round(100*sum(s)/sum(sum(s)) over(),1) pct from t group by 1 order by 2 desc"
echo "== came back on another day (percent of callers)"
q "$T, d as (select user_id, count(distinct created_at::date) days from t group by 1)
   select round(100.0*count(*) filter (where days>=2)/count(*)) pct_2days, round(100.0*count(*) filter (where days>=7)/count(*)) pct_7days from d"
echo "== beyond the call, percent of callers who tried each (server side)"
echo "   shadowing = client_events (from 2026-09-16) UNION ledger purpose 'shadow' (earlier takes)"
q "select
   round(100.0*(select count(distinct user_id) from (
       select user_id from client_events where event like 'shadow_attempt%' and $W
       union select user_id from usage_ledger where metadata->>'purpose'='shadow' and $W) s
     where user_id in $C) / (select count(*) from $C x)) shadowing,
   round(100.0*(select count(distinct user_id) from usage_ledger where action in ('tts_scene','scene_play') and $W and user_id in $C) / (select count(*) from $C x)) scenes,
   round(100.0*(select count(distinct user_id) from client_events where event='tutor_lesson_started' and $W and user_id in $C) / (select count(*) from $C x)) tutor_lesson,
   round(100.0*(select count(distinct user_id) from client_events where event like 'say_again%' and $W and user_id in $C) / (select count(*) from $C x)) say_again,
   round(100.0*(select count(distinct user_id) from usage_ledger where action='talk_time' and metadata->>'mode'='pron' and $W and user_id in $C) / (select count(*) from $C x)) pron_call,
   round(100.0*(select count(distinct user_id) from speech_challenge_entries where updated_at >= '$SINCE' and user_id in $C) / (select count(*) from $C x)) speech_challenge"

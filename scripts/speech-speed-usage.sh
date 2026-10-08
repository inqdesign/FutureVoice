#!/usr/bin/env bash
# Who is on which speaking speed right now? (2026-10-08)
#
#   scripts/speech-speed-usage.sh
#
# Every event the app writes carries the learner's speed (`speed`, the
# multiplier), whether they ever picked it (`speed_picked`) and, from 1.1.5,
# the rung (`speed_rung`: normal · slow (Relaxed) · slower (Slow)) — see
# `Telemetry.callSettings`. This takes each learner's MOST RECENT event and
# counts them, all-time and among those active in the last 7 days. Builds
# before the rung was sent show "?" there; read them by the number.
set -euo pipefail
RAW="$(security find-generic-password -s "Supabase CLI" -w)"
TOKEN="$(printf '%s' "${RAW#go-keyring-base64:}" | base64 -d)"
Q="with last as (
  select distinct on (user_id) user_id, created_at,
         properties->>'speed' as speed,
         coalesce(properties->>'speed_rung', '?') as rung,
         properties->>'speed_picked' as picked
  from client_events where properties ? 'speed'
  order by user_id, created_at desc)
select rung, speed, picked, count(*) as users,
       count(*) filter (where created_at > now() - interval '7 days') as active_7d
from last group by 1, 2, 3 order by 2, 1, 3"
curl -s -X POST "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$Q")" |
python3 -c '
import json, sys
rows = json.load(sys.stdin)
if not isinstance(rows, list):
    print(rows); sys.exit(1)
print("%-8s %-6s %-7s %5s %5s" % ("rung", "speed", "picked", "users", "7d"))
for r in rows:
    print("%-8s %-6s %-7s %5s %5s" % (r["rung"], r["speed"], "yes" if r["picked"] == "1" else "no", r["users"], r["active_7d"]))
'

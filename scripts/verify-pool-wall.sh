#!/bin/bash
# Prove the talk pool empties correctly — without talking for 90 seconds.
#
# Replays what a call does to billing: the opening tick (1 s, carrying
# `preflight`), then 15 s flushes (`TalkBilling.flushEveryMs`) until the pool
# is gone, each through the real `charge_talk_seconds`. Same code path as a
# call; only the microphone is missing.
#
# What it must show:
#   * every tick charges while seconds remain — no tick refused for asking
#     more than is left,
#   * the LAST tick takes the remainder, so the balance lands on 0 and no
#     tail is left behind,
#   * the wall rides on that same tick, never earlier,
#   * afterwards the opening tick is refused, which is the paywall.
#
# Usage: scripts/verify-pool-wall.sh <email> [seconds]
#   scripts/verify-pool-wall.sh inqde.lee@googlemail.com 90
#
# It grants those seconds and then SPENDS them: dev accounts only.
set -euo pipefail

EMAIL="${1:?usage: verify-pool-wall.sh <email> [seconds]}"
GRANT="${2:-90}"
PROJECT_REF="${PROJECT_REF:-chhzjtigzdotacutwcyo}"
RUN="verify-$(date +%s)"

RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)

sql() {  # SQL on stdin → JSON rows on stdout
  python3 -c 'import json,sys;print(json.dumps({"query":sys.stdin.read()}))' \
    | curl -s -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d @-
}

field() {  # field <json> <key> — first row's value, or empty
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
if isinstance(d,dict): print(d.get("message","")[:200]); sys.exit()
print("" if not d else (d[0].get(sys.argv[2]) if d[0].get(sys.argv[2]) is not None else ""))
' "$1" "$2"
}

USER_ID=$(field "$(echo "select id from auth.users where email = '$EMAIL'" | sql)" id)
[ -n "$USER_ID" ] || { echo "no account for $EMAIL"; exit 1; }

echo "granting ${GRANT}s to $EMAIL"
echo "select public.grant_credits('$USER_ID'::uuid, $GRANT, 'grant'::public.ledger_kind,
        'test_grant', 'verify-pool-wall', 'test_grant:$RUN',
        jsonb_build_object('reason', 'pool wall verification')) as balance" | sql >/dev/null

balance() { field "$(echo "select balance from user_credits where user_id = '$USER_ID'::uuid" | sql)" balance; }

echo
printf 'tick  asked  before  charged  after  note\n'
n=0
while :; do
  n=$((n + 1))
  if [ "$n" = 1 ]; then asked=1; pre=true; else asked=15; pre=false; fi
  before=$(balance)
  out=$(cat <<SQL | sql
select public.charge_talk_seconds(
         '$USER_ID'::uuid, $asked, 'verify-pool-wall', '$RUN:$n',
         jsonb_build_object('session_id', '$RUN', 'seconds', $asked,
                            'preflight', $pre), 'en') as r
SQL
)
  after=$(balance)
  note=$(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
if isinstance(d,dict):
    m=d.get("message","")
    print("REFUSED (the paywall)" if "INSUFFICIENT_CREDITS" in m else "error: "+m[:120]); sys.exit()
r=d[0].get("r") or {}
if isinstance(r,str): r=json.loads(r)
print(("WALL" if r.get("wall") else "") + (" · pool closed" if r.get("pool_closed") else ""))
' "$out")
  charged=$(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
if isinstance(d,dict): print(0); sys.exit()
r=d[0].get("r") or {}
if isinstance(r,str): r=json.loads(r)
print(r.get("charged",0))
' "$out")
  printf '%4s  %5s  %6s  %7s  %5s  %s\n' "$n" "$asked" "$before" "$charged" "$after" "$note"
  case "$note" in *WALL*|*REFUSED*|*error*) break ;; esac
  [ "$n" -lt 40 ] || { echo "gave up after 40 ticks"; break; }
done

echo
echo "opening another call:"
out=$(cat <<SQL | sql
select public.charge_talk_seconds(
         '$USER_ID'::uuid, 1, 'verify-pool-wall', '$RUN:reopen',
         jsonb_build_object('session_id', '$RUN-2', 'seconds', 1,
                            'preflight', true), 'en') as r
SQL
)
python3 -c '
import json,sys
d=json.loads(sys.argv[1])
if isinstance(d,dict) and "INSUFFICIENT_CREDITS" in d.get("message",""):
    print("  refused — the learner gets the paywall, not a call. correct.")
elif isinstance(d,dict):
    print("  error:", d.get("message","")[:160])
else:
    r=d[0].get("r") or {}
    if isinstance(r,str): r=json.loads(r)
    print("  ALLOWED — balance", r.get("balance"), "· this is the bug: a call would open")
' "$out"

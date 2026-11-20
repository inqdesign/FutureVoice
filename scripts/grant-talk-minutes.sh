#!/bin/bash
# Add free talk minutes to one account (a goodwill grant).
#
#   ./scripts/grant-talk-minutes.sh <email> [minutes]            # shows the account, changes nothing
#   ./scripts/grant-talk-minutes.sh <email> [minutes] --send     # asks y/N, then grants
#
# Minutes default to 20. The grant goes through grant_credits() as
# `goodwill_grant`, keyed per account per UTC day, so running it twice on the
# same day adds the minutes once.
set -euo pipefail

REF=chhzjtigzdotacutwcyo
EMAIL=""; MINUTES=20; SEND=0
for a in "$@"; do
  case "$a" in
    --send) SEND=1 ;;
    *@*) EMAIL="$a" ;;
    *[!0-9]*) echo "Unknown argument: $a" >&2; exit 2 ;;
    *) MINUTES="$a" ;;
  esac
done
[ -n "$EMAIL" ] || { echo "usage: $0 <email> [minutes] [--send]" >&2; exit 2; }
case "$EMAIL" in *"'"*) echo "Bad email." >&2; exit 2 ;; esac
[ "$MINUTES" -ge 1 ] && [ "$MINUTES" -le 120 ] || { echo "Minutes must be 1-120." >&2; exit 2; }
SECONDS_TO_ADD=$((MINUTES * 60))

RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
q() {
  curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$1" '{query:$q}')"
}

ROW=$(q "select u.id, u.email, coalesce((select balance from user_credits c where c.user_id = u.id), 0) as balance,
                (select count(*) from usage_ledger l where l.user_id = u.id and l.action = 'goodwill_grant') as earlier
         from auth.users u where lower(u.email) = lower('$EMAIL')")
COUNT=$(echo "$ROW" | jq 'if type == "array" then length else -1 end')
if [ "$COUNT" != "1" ]; then
  echo "Expected one account for $EMAIL, got: $ROW" >&2; exit 1
fi
USER_ID=$(echo "$ROW" | jq -r '.[0].id')
BALANCE=$(echo "$ROW" | jq -r '.[0].balance')
EARLIER=$(echo "$ROW" | jq -r '.[0].earlier')
KEY="goodwill:$USER_ID:$(date -u +%Y-%m-%d)"

echo "Account : $EMAIL ($USER_ID)"
echo "Balance : ${BALANCE}s ($((BALANCE / 60)) min)"
echo "Earlier goodwill grants: $EARLIER"
echo "Add     : ${SECONDS_TO_ADD}s ($MINUTES min)  ->  $((BALANCE + SECONDS_TO_ADD))s"
echo "Key     : $KEY"

if [ "$SEND" != "1" ]; then
  echo; echo "Dry run. Nothing changed. Add --send to grant."; exit 0
fi

read -r -p "Grant $MINUTES min to $EMAIL? [y/N] " ANSWER
[ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ] || { echo "Cancelled."; exit 0; }

RESULT=$(q "select public.grant_credits('$USER_ID'::uuid, $SECONDS_TO_ADD, 'grant'::ledger_kind, 'goodwill_grant', 'grant-talk-minutes.sh', '$KEY', jsonb_build_object('minutes', $MINUTES)) as balance")
NEW=$(echo "$RESULT" | jq -r 'if type == "array" then .[0].balance else empty end')
if [ -z "$NEW" ]; then
  echo "Grant failed: $RESULT" >&2; exit 1
fi
echo "Done. Balance is now ${NEW}s ($((NEW / 60)) min)."

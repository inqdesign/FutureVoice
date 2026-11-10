#!/usr/bin/env bash
# Rehearses the half of web billing no checkout test reaches: Stripe → stripe-webhook
# → user_subscriptions → the app's allowance, and cancel → expired. No money moves.
#
# A throwaway anonymous user gets a real (live) Stripe subscription with a 1-day
# trial and no payment method, so its first invoice is 0 and is paid at once:
# Stripe sends invoice.paid, the webhook writes the row. Then the subscription is
# cancelled (customer.subscription.deleted → expired) and the customer deleted.
# The anonymous user is collected by the anonymous-user sweep.
#
# Run:  bash scripts/stripe-webhook-rehearsal.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SK="${STRIPE_SECRET_KEY:-$(grep '^STRIPE_SECRET_KEY=' ~/humhumhum/.env.local | cut -d= -f2- | tr -d '"')}"
[[ "$SK" == sk_* ]] || { echo "no STRIPE_SECRET_KEY" >&2; exit 1; }
ANON=$(grep -o 'supabaseAnonKey: "[^"]*"' web/index.html | head -1 | cut -d'"' -f2)
U=https://chhzjtigzdotacutwcyo.supabase.co
PLAN=light_monthly
jq_() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }
fail=0
check() { if [[ "$2" == *"$3"* ]]; then echo "  PASS  $1"; else echo "  FAIL  $1  (got: $2)"; fail=1; fi; }

R=$(curl -s -m 20 -X POST "$U/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"data":{}}')
AT=$(echo "$R" | jq_ 'd["access_token"]'); USER_ID=$(echo "$R" | jq_ 'd["user"]["id"]')
PRICE=$(curl -s "$U/rest/v1/subscription_plans?id=eq.$PLAN&select=stripe_price_id" -H "apikey: $ANON" | jq_ 'd[0]["stripe_price_id"]')
CUS=$(curl -s -u "$SK:" https://api.stripe.com/v1/customers -d "name=nawana webhook rehearsal" \
  -d "metadata[project]=futurevoice" -d "metadata[rehearsal]=1" | jq_ 'd["id"]')
cleanup() { curl -s -o /dev/null -u "$SK:" -X DELETE "https://api.stripe.com/v1/customers/$CUS" || true; }
trap cleanup EXIT
SUB=$(curl -s -u "$SK:" https://api.stripe.com/v1/subscriptions -d customer="$CUS" \
  -d "items[0][price]=$PRICE" -d trial_period_days=1 -d currency=eur \
  -d "metadata[project]=futurevoice" -d "metadata[user_id]=$USER_ID" -d "metadata[plan_id]=$PLAN" | jq_ 'd.get("id") or d')
echo "user $USER_ID · customer $CUS · subscription $SUB"

# The owner can read their own row (RLS), so no admin token is needed.
row() { curl -s "$U/rest/v1/user_subscriptions?select=plan_id,source,status,stripe_subscription_id" \
  -H "apikey: $ANON" -H "Authorization: Bearer $AT"; }
wait_for() { local out; for _ in $(seq 1 12); do out=$(row); [[ "$out" == *"$1"* ]] && break; sleep 5; done; echo "$out"; }
fn() { curl -s -m 30 -w " %{http_code}" -X POST "$U/functions/v1/$1" -H "apikey: $ANON" \
  -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d "$2"; }

echo "1. Stripe → webhook → subscription row"
ROW=$(wait_for '"trialing"')
check "row written for this user" "$ROW" "\"stripe_subscription_id\":\"$SUB\""
check "plan resolved from the price" "$ROW" "\"plan_id\":\"$PLAN\""
check "source is stripe, status entitled" "$ROW" '"source":"stripe","status":"trialing"'

echo "2. the account is entitled"
ALLOW=$(curl -s -m 20 -X POST "$U/rest/v1/rpc/talk_allowance" -H "apikey: $ANON" \
  -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d '{}')
echo "  talk_allowance: ${ALLOW:0:300}"
check "a second checkout is refused" "$(fn stripe-checkout "{\"plan_id\":\"$PLAN\",\"return_url\":\"https://nawana.app/\"}")" "already_subscribed"
check "the portal opens" "$(fn stripe-portal '{"return_url":"https://nawana.app/"}')" "billing.stripe.com"

echo "3. cancel → expired"
curl -s -o /dev/null -u "$SK:" -X DELETE "https://api.stripe.com/v1/subscriptions/$SUB"
check "row is expired" "$(wait_for '"expired"')" '"status":"expired"'

[[ $fail == 0 ]] && echo "ALL PASS" || { echo "SOMETHING FAILED"; exit 1; }

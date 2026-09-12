#!/bin/bash
# Launch-day switch for nawana.app: promote the .next marketing pages to the
# root (replacing the "Coming soon" beta page) and deploy to Vercel — which
# also turns web Stripe billing ON, since the .next pages ship with
# BILLING.enabled=true and every server piece has been live since 2026-09-03.
#
#   bash scripts/launch-web.sh          # preflight + swap + deploy + smoke
#
# The old root stays reachable as beta.html (same content, never touched).
# Safe to re-run — every step is a copy or an idempotent check.
set -euo pipefail
cd "$(dirname "$0")/.."

FN_BASE="https://chhzjtigzdotacutwcyo.supabase.co/functions/v1"

echo "── preflight ──────────────────────────────────────"

# The pages must actually sell: billing flag on, in both.
for f in web/index.next.html web/ko.next.html; do
  grep -q "enabled: true," "$f" || { echo "✗ $f has BILLING.enabled false"; exit 1; }
  echo "✓ $f: BILLING.enabled true"
done

# The webhook must be up and checking signatures (405 GET / 400 unsigned POST).
code=$(curl -s -o /dev/null -w "%{http_code}" "$FN_BASE/stripe-webhook")
[ "$code" = "405" ] || { echo "✗ stripe-webhook GET returned $code (expected 405)"; exit 1; }
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$FN_BASE/stripe-webhook" -d '{}')
[ "$code" = "400" ] || { echo "✗ stripe-webhook unsigned POST returned $code (expected 400 — secrets missing?)"; exit 1; }
echo "✓ stripe-webhook: deployed, secrets loaded"

# Every plan must carry its Stripe price id.
RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
missing=$(curl -s -X POST "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"select count(*) as n from subscription_plans where is_active and stripe_price_id is null"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['n'])")
[ "$missing" = "0" ] || { echo "✗ $missing active plan(s) missing stripe_price_id"; exit 1; }
echo "✓ subscription_plans: all active plans have a Stripe price"

# The pages offer BOTH Apple and Google sign-in. Google being unconfigured is
# not a blocker (Apple alone sells), but its button would dead-end — warn.
google=$(curl -s "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/config/auth" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['external_google_enabled'])")
if [ "$google" = "True" ]; then
  echo "✓ google sign-in: enabled"
else
  echo "⚠ google sign-in NOT configured — the pages' 'Continue with Google' link will fail."
  echo "  Either run scripts/google-web-signin.py first, or accept Apple-only for now."
fi

echo "── swap ───────────────────────────────────────────"
cp web/index.next.html web/index.html
cp web/ko.next.html web/ko.html
echo "✓ .next pages promoted to index.html / ko.html (beta stays at beta.html)"

echo "── deploy ─────────────────────────────────────────"
VERCEL=$(command -v vercel || echo "npx vercel")
$VERCEL --cwd web --prod --yes

echo "── post-deploy smoke ──────────────────────────────"
sleep 5
title=$(curl -s https://nawana.app | grep -o "<title>[^<]*" | head -1)
echo "  live title: $title"
case "$title" in *"Coming soon"*) echo "✗ root still serves the beta page"; exit 1;; esac
curl -s https://nawana.app | grep -q "enabled: true," \
  && echo "✓ live page has billing enabled" \
  || { echo "✗ live page does not carry BILLING.enabled=true"; exit 1; }

cat <<'EOF'
── done — now verify with real money (all free) ────
 1. trial     : fresh Apple ID → subscribe on the site → card saved, ₩0
                charged, then check user_subscriptions shows 'trialing'
 2. dup guard : an Apple-subscribed account → subscribe → must see the
                "manage it in the store" message, never Stripe checkout
 3. cancel    : 구독 관리 → cancel → row gets cancel_at_period_end=true
 4. plan move : portal switch Light↔Plus → row's plan_id follows
EOF

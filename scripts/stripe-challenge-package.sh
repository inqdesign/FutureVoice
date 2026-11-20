#!/usr/bin/env bash
# The 100-day challenge package (2026-11-12, founder): paid once, on the web.
#
# Its own Stripe product, so the checkout and the receipt say what was bought
# and the dashboard shows challenge sales apart from subscriptions. Three
# one-time Prices (usd base + krw/eur options, tax-inclusive), one per size:
# the web's monthly price times three. Prints the ids the migration
# 20261112100000_challenge_package.sql carries.
#
# Run once:  bash scripts/stripe-challenge-package.sh
set -euo pipefail
SK="${STRIPE_SECRET_KEY:-$(grep '^STRIPE_SECRET_KEY=' ~/humhumhum/.env.local | cut -d= -f2- | tr -d '"')}"
[[ "$SK" == sk_* ]] || { echo "no STRIPE_SECRET_KEY" >&2; exit 1; }

curl -sS -u "$SK:" https://api.stripe.com/v1/products \
  -d id=nawana_challenge -d name="nawana 100-day challenge" -d statement_descriptor="NAWANA.APP" \
  -d "metadata[project]=futurevoice" >/dev/null

# plan usd krw eur  (minor units; krw is zero-decimal)
for row in "light_challenge 2697 40500 2697" "plus_challenge 6747 78000 6207" "max_challenge 9447 121500 10797"; do
  read -r plan usd krw eur <<<"$row"
  curl -sS -u "$SK:" https://api.stripe.com/v1/prices \
    -d product=nawana_challenge -d currency=usd -d unit_amount="$usd" -d tax_behavior=inclusive \
    -d lookup_key="$plan" -d transfer_lookup_key=true -d nickname="$plan 100 days" \
    -d "metadata[project]=futurevoice" -d "metadata[plan_id]=$plan" \
    -d "currency_options[krw][unit_amount]=$krw" -d "currency_options[krw][tax_behavior]=inclusive" \
    -d "currency_options[eur][unit_amount]=$eur" -d "currency_options[eur][tax_behavior]=inclusive" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sys.argv[1], d["id"]) if "id" in d else sys.exit(str(d.get("error")))' "$plan"
done

#!/usr/bin/env bash
# Web prices are the App Store's minus 10% (2026-10-21, founder decision).
#
# Why 10: Apple keeps 15% of the VAT-free price; Stripe on the shared Dear RoRo
# account (Germany, EUR payout) costs ~3.25% + €0.25 on a non-EEA card plus ~2%
# conversion. A web sale at -10% nets about what an App Store sale does; past that
# the discount is paid out of revenue.
#
# Creates five live Prices on the existing products (tax-inclusive, usd base +
# krw/eur options), moves each plan's lookup_key onto the new Price, then writes the
# migration that points subscription_plans.stripe_price_id at them. The old Prices
# are left active (none has a subscription) so going back is one migration.
#
# Run:  bash scripts/stripe-web-discount.sh
# Then: bash scripts/apply-migration.sh supabase/migrations/20261021120000_web_prices_ten_percent_off.sql
set -euo pipefail
cd "$(dirname "$0")/.."

SK="${STRIPE_SECRET_KEY:-$(grep '^STRIPE_SECRET_KEY=' ~/humhumhum/.env.local | cut -d= -f2- | tr -d '"')}"
[[ "$SK" == sk_* ]] || { echo "no STRIPE_SECRET_KEY" >&2; exit 1; }

OUT=supabase/migrations/20261021120000_web_prices_ten_percent_off.sql
[[ -e "$OUT" ]] && { echo "$OUT already exists — prices were made; apply it instead" >&2; exit 1; }

# plan product interval usd krw eur   (minor units; krw is zero-decimal)
PLANS=(
  "light_monthly nawana_light month   899  13500   899"
  "light_annual  nawana_light year   8999 134000  8999"
  "plus_monthly  nawana_plus  month  2249  26000  2069"
  "plus_annual   nawana_plus  year  22499 261000 20699"
  "max_monthly   nawana_max   month  4499  52000  4049"
)

SQL=""
for row in "${PLANS[@]}"; do
  read -r plan product interval usd krw eur <<<"$row"
  id=$(curl -sS -u "$SK:" https://api.stripe.com/v1/prices \
    -d product="$product" -d "recurring[interval]=$interval" \
    -d currency=usd -d unit_amount="$usd" -d tax_behavior=inclusive \
    -d lookup_key="$plan" -d transfer_lookup_key=true \
    -d nickname="$plan web 10 off" \
    -d "metadata[project]=futurevoice" -d "metadata[web_discount]=10" \
    -d "currency_options[krw][unit_amount]=$krw" -d "currency_options[krw][tax_behavior]=inclusive" \
    -d "currency_options[eur][unit_amount]=$eur" -d "currency_options[eur][tax_behavior]=inclusive" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["id"]) if "id" in d else sys.exit(d.get("error"))')
  echo "$plan → $id  (usd $usd · krw $krw · eur $eur)"
  SQL+="update subscription_plans set stripe_price_id = '$id' where id = '$plan';"$'\n'
done

cat >"$OUT" <<EOF
-- Web prices are the App Store's minus 10% (2026-10-21, founder decision).
--
-- Apple keeps 15% of the VAT-free price; Stripe from the German account costs ~5–6%
-- on a Korean or US card (fee + EUR conversion), so -10% on the web nets about what
-- the App Store does. New live Prices on the same products, made by
-- scripts/stripe-web-discount.sh (lookup_key moved onto them):
--   light_monthly  \$8.99    ₩13,500   €8.99
--   light_annual   \$89.99   ₩134,000  €89.99
--   plus_monthly   \$22.49   ₩26,000   €20.69
--   plus_annual    \$224.99  ₩261,000  €206.99
--   max_monthly    \$44.99   ₩52,000   €40.49
-- The 2026-10-11 Prices stay active and unused (no web subscription existed), so
-- 20261011100000's ids are the way back.

$SQL
EOF
echo "wrote $OUT"

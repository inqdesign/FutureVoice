#!/usr/bin/env bash
# What Apple says about a subscription — the truth our own tables can only
# approximate.
#
#   bash scripts/apple-subscription.sh 270003123752849
#   bash scripts/apple-subscription.sh 270003123752849 --json
#
# Why this exists (2026-09-18). A learner wrote in asking whether their launch
# code had worked: the app showed the regular price, and every row we had
# agreed with the app. Apple did not. An offer code prices the first RENEWAL,
# not the period it is redeemed in, and that lives in `signedRenewalInfo` —
# which arrives on notifications we did not store and cannot be re-read from
# `subscription_transactions`. One call answers it, and the same call settles
# the other questions support actually gets: is it cancelled, which storefront,
# which Apple ID, is there a second subscription on this account.
#
# Takes ONE original transaction id and prints every subscription that Apple
# ID holds in this app. Read-only.
#
# Credentials (the path scripts/beta.sh already documents):
#   ~/.appstoreconnect/issuer_id                    — Issuer ID, one line
#   ~/.appstoreconnect/private_keys/AuthKey_*.p8    — an IN-APP PURCHASE key
# The App Store Connect key beta.sh uploads with is a DIFFERENT key type and
# is refused here; generate the other one under Users and Access →
# Integrations → In-App Purchase.
#
# Sandbox: ASAPI_HOST=https://api.storekit-sandbox.itunes.apple.com
set -euo pipefail

ORIG="${1:?usage: apple-subscription.sh <originalTransactionId> [--json]}"
RAW_JSON="${2:-}"
BUNDLE_ID="${APPLE_BUNDLE_ID:-com.roro.futurevoice}"
HOST="${ASAPI_HOST:-https://api.storekit.itunes.apple.com}"
KEY_DIR="$HOME/.appstoreconnect/private_keys"

KEY=$(ls "$KEY_DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)
[[ -n "$KEY" ]] || { echo "no In-App Purchase key in $KEY_DIR" >&2; exit 1; }
[[ -f "$HOME/.appstoreconnect/issuer_id" ]] || { echo "no ~/.appstoreconnect/issuer_id" >&2; exit 1; }
KID=$(basename "$KEY" .p8); KID=${KID#AuthKey_}
ISS=$(tr -d '[:space:]' < "$HOME/.appstoreconnect/issuer_id")

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=$(date +%s)
header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KID" | b64url)
# `bid` is required for the App Store Server API and is what scopes the token
# to this app; `aud` stays appstoreconnect-v1.
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1","bid":"%s"}' \
  "$ISS" "$now" $((now + 1200)) "$BUNDLE_ID" | b64url)
# openssl signs to DER; JOSE wants the raw r||s pair, each left-padded to 32
# bytes. Without the padding a short r or s produces a signature Apple rejects
# roughly one call in 256 — the kind of flake that gets blamed on the key.
sig=$(printf '%s.%s' "$header" "$payload" \
  | openssl dgst -sha256 -sign "$KEY" \
  | openssl asn1parse -inform DER \
  | awk -F: '/INTEGER/{print $4}' \
  | while read -r int; do printf '%064s' "$int" | tr ' ' 0; done \
  | xxd -r -p | b64url)

resp=$(curl -s -H "Authorization: Bearer $header.$payload.$sig" \
  "$HOST/inApps/v1/subscriptions/$ORIG")

if [[ "$RAW_JSON" == "--json" ]]; then echo "$resp"; exit 0; fi

echo "$resp" | python3 "$(dirname "$0")/apple_subscription_print.py"

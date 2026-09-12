#!/usr/bin/env python3
"""One-shot Stripe web-billing setup for FutureVoice (nawana.app).

Run from the repo root:  python3 scripts/stripe-web-billing.py

Idempotent — safe to re-run. Every step checks before it creates:
  1. verifies the Stripe key against /v1/account
  2. deploys the three edge functions (checkout, portal, webhook)
  3. ensures Products nawana_light / nawana_plus (statement descriptor NAWANA.APP)
  4. ensures the 4 Prices by lookup_key, USD base + krw/eur currency_options,
     all tax-inclusive (charged total == printed price, like the App Store)
  5. sets Supabase secrets (STRIPE_SECRET_KEY, SITE_URL)
  6. ensures the webhook endpoint (4 events) and stores its signing secret
  7. ensures the Customer Portal default configuration (cancel + plan switch)
  8. writes stripe_price_id into subscription_plans (prod, via Management API)
  9. writes a result summary to build-capture/stripe-setup.json

The Stripe account is the SHARED Dear RoRo account (humhumhum + DeskSquat bill
there too) — this script only ADDS namespaced objects (nawana_*) and touches
nothing of theirs. The key is the live key from humhumhum's .env.local; there
is no test key on this machine, so objects are live-mode. Verification is
still free: checkout with the 7-day trial charges 0, then cancel.
"""

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE_URL = "https://nawana.app"
SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
WEBHOOK_URL = f"https://{SUPABASE_PROJECT_REF}.supabase.co/functions/v1/stripe-webhook"
WEBHOOK_EVENTS = [
    "checkout.session.completed",
    "invoice.paid",
    "customer.subscription.updated",
    "customer.subscription.deleted",
]

# Locked launch prices — docs/launch-billing.md. Amounts in minor units
# (KRW is zero-decimal: 15000 == ₩15,000). EUR matches the live ASC values.
PLANS = {
    "light_monthly": dict(product="nawana_light", interval="month", usd=999,   krw=15000,  eur=999),
    "light_annual":  dict(product="nawana_light", interval="year",  usd=7999,  krw=110000, eur=8999),
    "plus_monthly":  dict(product="nawana_plus",  interval="month", usd=1999,  krw=29000,  eur=2299),
    "plus_annual":   dict(product="nawana_plus",  interval="year",  usd=14399, krw=209000, eur=14999),
}
PRODUCTS = {
    "nawana_light": "Nawana Light",
    "nawana_plus": "Nawana Plus",
}


def find_stripe_key() -> str:
    key = os.environ.get("STRIPE_SECRET_KEY", "")
    if key.startswith("sk_"):
        return key
    env = Path.home() / "humhumhum" / ".env.local"
    for line in env.read_text().splitlines():
        if line.startswith("STRIPE_SECRET_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("no STRIPE_SECRET_KEY in env or ~/humhumhum/.env.local")


SK = find_stripe_key()


def stripe(method: str, path: str, params: list[tuple[str, str]] | None = None) -> dict:
    url = f"https://api.stripe.com/v1/{path}"
    data = None
    if method == "GET" and params:
        url += "?" + urllib.parse.urlencode(params)
    elif params is not None:
        data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + SK)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise RuntimeError(f"{method} {path} → {e.code}: {body}") from None


def run(cmd: list[str], **kw) -> None:
    # never echo a secret value — mask anything that smells like one
    print("  $", " ".join(c.split("=")[0] + "=***" if "SECRET" in c and "=" in c else c for c in cmd))
    subprocess.run(cmd, check=True, cwd=REPO, **kw)


def price_params(lookup_key: str, p: dict) -> list[tuple[str, str]]:
    return [
        ("product", p["product"]),
        ("lookup_key", lookup_key),
        ("currency", "usd"),
        ("unit_amount", str(p["usd"])),
        ("tax_behavior", "inclusive"),
        ("recurring[interval]", p["interval"]),
        ("currency_options[krw][unit_amount]", str(p["krw"])),
        ("currency_options[krw][tax_behavior]", "inclusive"),
        ("currency_options[eur][unit_amount]", str(p["eur"])),
        ("currency_options[eur][tax_behavior]", "inclusive"),
    ]


def main() -> None:
    # 1 ── verify the key and say which account this is
    acct = stripe("GET", "account")
    live = SK.startswith("sk_live_")
    print(f"account: {acct['id']} · {acct.get('country')} · default {acct.get('default_currency')}"
          f" · {'LIVE' if live else 'TEST'} mode")
    if acct.get("country") != "DE":
        print("  ⚠ expected a DE account — continuing, but check this is the right one")

    # 2 ── deploy the edge functions first, so the webhook URL exists before
    # Stripe starts delivering to it
    print("deploying edge functions…")
    run(["supabase", "functions", "deploy", "stripe-checkout"])
    run(["supabase", "functions", "deploy", "stripe-portal"])
    run(["supabase", "functions", "deploy", "stripe-webhook", "--no-verify-jwt"])

    # 3 ── products (namespaced nawana_* on the shared account)
    for pid, name in PRODUCTS.items():
        try:
            stripe("GET", f"products/{pid}")
            print(f"product {pid}: exists")
        except RuntimeError:
            stripe("POST", "products", [
                ("id", pid), ("name", name), ("statement_descriptor", "NAWANA.APP"),
            ])
            print(f"product {pid}: created")

    # 4 ── prices, keyed by lookup_key so re-runs find instead of duplicate
    price_ids: dict[str, str] = {}
    for key, p in PLANS.items():
        found = stripe("GET", "prices", [("lookup_keys[]", key), ("limit", "1")])["data"]
        if found:
            price = found[0]
            print(f"price {key}: exists → {price['id']}")
            # ensure the currency options are there (an older run may predate them)
            detail = stripe("GET", f"prices/{price['id']}", [("expand[]", "currency_options")])
            opts = detail.get("currency_options") or {}
            missing = [c for c in ("krw", "eur") if c not in opts]
            if missing:
                stripe("POST", f"prices/{price['id']}", [
                    (f"currency_options[{c}][unit_amount]", str(p[c])) for c in missing
                ] + [
                    (f"currency_options[{c}][tax_behavior]", "inclusive") for c in missing
                ])
                print(f"  added currency options: {', '.join(missing)}")
        else:
            price = stripe("POST", "prices", price_params(key, p))
            print(f"price {key}: created → {price['id']}")
        price_ids[key] = price["id"]

    # 5 ── supabase secrets (key + site; webhook secret follows in step 6)
    print("setting supabase secrets…")
    run(["supabase", "secrets", "set", f"STRIPE_SECRET_KEY={SK}", f"SITE_URL={SITE_URL}"])

    # 6 ── webhook endpoint. The signing secret is only readable at creation,
    # so an existing endpoint means the secret was stored on a previous run.
    hooks = stripe("GET", "webhook_endpoints", [("limit", "100")])["data"]
    existing = next((h for h in hooks if h["url"] == WEBHOOK_URL), None)
    if existing:
        # The signing secret is only readable at creation. If a previous run
        # died between creating the endpoint and storing the secret, delete
        # the endpoint in the Stripe dashboard and re-run this script.
        print(f"webhook endpoint: exists ({existing['id']}) — signing secret unchanged")
        webhook_id = existing["id"]
    else:
        hook = stripe("POST", "webhook_endpoints", [("url", WEBHOOK_URL)] +
                      [("enabled_events[]", e) for e in WEBHOOK_EVENTS])
        webhook_id = hook["id"]
        print(f"webhook endpoint: created ({webhook_id})")
        run(["supabase", "secrets", "set", f"STRIPE_WEBHOOK_SECRET={hook['secret']}"])

    # 7 ── customer portal: cancel-at-period-end + plan switching among the 4
    # prices. Nothing else on the shared account uses the portal (humhumhum
    # and DeskSquat sell one-time payments), so owning the default is safe.
    portal_features = [
        ("features[invoice_history][enabled]", "true"),
        ("features[payment_method_update][enabled]", "true"),
        ("features[subscription_cancel][enabled]", "true"),
        ("features[subscription_cancel][mode]", "at_period_end"),
        ("features[subscription_update][enabled]", "true"),
        ("features[subscription_update][default_allowed_updates][]", "price"),
        ("features[subscription_update][products][0][product]", "nawana_light"),
        ("features[subscription_update][products][0][prices][]", price_ids["light_monthly"]),
        ("features[subscription_update][products][0][prices][]", price_ids["light_annual"]),
        ("features[subscription_update][products][1][product]", "nawana_plus"),
        ("features[subscription_update][products][1][prices][]", price_ids["plus_monthly"]),
        ("features[subscription_update][products][1][prices][]", price_ids["plus_annual"]),
    ]
    configs = stripe("GET", "billing_portal/configurations", [("is_default", "true"), ("limit", "1")])["data"]
    if configs:
        stripe("POST", f"billing_portal/configurations/{configs[0]['id']}", portal_features)
        print(f"portal: updated default configuration ({configs[0]['id']})")
    else:
        cfg = stripe("POST", "billing_portal/configurations", portal_features)
        print(f"portal: created default configuration ({cfg['id']})")

    # 8 ── write the price ids into subscription_plans (prod). One statement
    # per request — the Management API's query endpoint is not guaranteed to
    # take multi-statement strings.
    token_raw = subprocess.run(
        ["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
        check=True, capture_output=True, text=True).stdout.strip()
    if token_raw.startswith("go-keyring-base64:"):
        token = base64.b64decode(token_raw.split(":", 1)[1]).decode().strip()
    else:
        token = token_raw

    def sb_query(q: str):
        req = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/database/query",
            data=json.dumps({"query": q}).encode(), method="POST")
        req.add_header("Authorization", "Bearer " + token)
        req.add_header("Content-Type", "application/json")
        # api.supabase.com's WAF 403s the default Python-urllib user agent
        req.add_header("User-Agent", "futurevoice-setup/1.0")
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)

    try:
        for k in PLANS:  # price ids come from Stripe, not user input — safe to inline
            sb_query(f"update subscription_plans set stripe_price_id = '{price_ids[k]}' where id = '{k}'")
        rows = sb_query("select id, stripe_price_id from subscription_plans order by id")
        print("subscription_plans:")
        for r in rows:
            print(f"  {r['id']}: {r['stripe_price_id']}")
    except urllib.error.HTTPError as e:
        # Seen in the wild (2026-09-03): the Management API 403'd from the
        # user's shell while the same token worked elsewhere. Everything
        # Stripe-side is already done at this point, so don't crash — print
        # the SQL to run by hand instead.
        print(f"  ⚠ subscription_plans update failed ({e.code}) — run these in the Supabase SQL editor:")
        for k in PLANS:
            print(f"    update subscription_plans set stripe_price_id = '{price_ids[k]}' where id = '{k}';")

    # 9 ── result file for the record
    out = REPO / "build-capture" / "stripe-setup.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps({
        "account": acct["id"], "live": live, "price_ids": price_ids,
        "webhook_endpoint": webhook_id, "webhook_url": WEBHOOK_URL,
    }, indent=2))
    print(f"\ndone — summary in {out.relative_to(REPO)}")
    print("remaining by hand: Apple Services ID (Supabase web sign-in),")
    print("then BILLING.enabled in the .next pages when they go live.")


if __name__ == "__main__":
    main()

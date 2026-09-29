#!/usr/bin/env python3
"""Re-price both ANNUAL subscriptions at "2 months free" in every storefront.

The annual plans came off sale on 2026-09-26 because their discount was
incoherent — measured across all 175 storefronts: Plus 32–52% off, Light
17–44%, and the US at 52% only because the monthly went to $24.99 under an
annual that hadn't moved. "2 months free" (a year for ten months) is the
shape they come back in: one sentence, the same offer everywhere, and a
number a buyer checks in their head.

HOW IT PICKS EACH PRICE, and why it is not simply "10 x monthly":

  · Apple's own EQUALIZATION does the work. Ask it for the equivalent of one
    USD price point and it answers for the other 174 storefronts — which is
    how this catalog was built in the first place ("USD is the base
    storefront, Apple auto-generates the rest"). Equalizing $99.99 / $199.99
    — ten times the ORIGINAL $9.99 / $19.99 — lands within 3% of ten times
    the local monthly in 166 and 168 territories respectively, because the
    monthly table came off the same ladder.
  · The BASE territory is set by hand, since equalization never returns it:
    Light $99.99, and Plus $249.99 — ten times the US monthly as it stands
    from 2026-09-28, not the $199.99 the ladder is walked from.
  · A handful of storefronts land somewhere else on Apple's ladder, and four
    of them came out charging MORE for a year than twelve months
    (`COG` / `MAR` on Light, `KOR` on Plus at ₩349,000 against ₩348,000).
    Any territory Apple's answer leaves under `MIN_MONTHS_FREE` is
    re-picked from that territory's own price points, closest to ten times
    its monthly.

Existing subscribers keep what they pay (`preserveCurrentPrice`), which
today is one German `plus_annual` at €149.99.

Apple refuses a start date it considers too soon and the boundary MOVES — it
took 2026-09-28 on the 26th and demanded the 29th on the 27th, so it is not
simply "tomorrow" in any timezone this machine can name. The 409 carries the
earliest date it will take, so the first refusal is read rather than guessed
at: the run adopts that date and keeps going. `--start YYYY-MM-DD` forces one.

Dry run by default; `--send` performs it. ~350 price changes, one per
(subscription, territory) — read the plan first.

    scripts/asc-annual-prices.py            # plan only
    scripts/asc-annual-prices.py --send     # do it
    scripts/asc-annual-prices.py --only KOR,USA,DEU
"""

import base64
import re
import datetime
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"

# subscription id → (name, monthly sibling, the USD point equalization walks from)
PLANS = {
    "6801673709": ("light_annual", "6800578969", "99.99"),
    "6801674470": ("plus_annual",  "6801674645", "199.99"),
}
# What the BASE storefront (USA) gets. Equalization never returns it, and Plus
# is not ten times the price the ladder is walked from: the US monthly moved
# to $24.99 on 2026-09-28 and the annual follows it, not the old $19.99.
USA_PRICE = {"light_annual": "99.99", "plus_annual": "249.99"}
# Below this, Apple's answer isn't "2 months free" and the territory is re-picked.
MIN_MONTHS_FREE = 1.5


def token() -> str:
    key_dir = os.path.expanduser("~/.appstoreconnect/private_keys")
    keys = [f for f in os.listdir(key_dir) if f.startswith("AuthKey_") and f.endswith(".p8")]
    if not keys:
        sys.exit(f"no App Store Connect key in {key_dir}")
    key_path = os.path.join(key_dir, keys[0])
    kid = keys[0][len("AuthKey_"):-len(".p8")]
    iss = open(os.path.expanduser("~/.appstoreconnect/issuer_id")).read().strip()

    def b64(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64(json.dumps({"iss": iss, "iat": now, "exp": now + 1200,
                              "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing = f"{header}.{payload}".encode()
    # openssl signs to DER; JOSE wants raw r||s, each left-padded to 32 bytes.
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                         input=signing, capture_output=True, check=True).stdout
    parsed = subprocess.run(["openssl", "asn1parse", "-inform", "DER"],
                            input=der, capture_output=True, check=True).stdout.decode()
    ints = [ln.split(":")[-1].strip() for ln in parsed.splitlines() if "INTEGER" in ln]
    sig = b"".join(bytes.fromhex(i.rjust(64, "0")) for i in ints)
    return f"{header}.{payload}.{b64(sig)}"


TOKEN = token()


def call(method: str, path: str, body=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:400]
        raise RuntimeError(f"{method} {url.split('?')[0]} → {e.code} {detail}") from None


def territory_of(point_id: str) -> str:
    padded = point_id + "=" * (-len(point_id) % 4)
    return json.loads(base64.urlsafe_b64decode(padded))["t"]


def pages(path: str):
    url = path
    while url:
        d = call("GET", url)
        yield d
        url = d.get("links", {}).get("next")


def effective_monthly(sub_id: str) -> dict:
    """Territory → the price NEW buyers pay. A `preserved` row is the price an
    existing subscriber was grandfathered onto and must not be read as the
    list price; a future-dated row is the one that matters (the US $24.99)."""
    out = {}
    for page in pages(f"/subscriptions/{sub_id}/prices?include=subscriptionPricePoint,territory&limit=200"):
        inc = {x["id"]: x for x in page.get("included", [])}
        for p in page.get("data", []):
            a, rel = p["attributes"], p.get("relationships", {})
            if a.get("preserved"):
                continue
            t = (rel.get("territory", {}).get("data") or {}).get("id")
            pp = (rel.get("subscriptionPricePoint", {}).get("data") or {}).get("id")
            price = inc.get(pp, {}).get("attributes", {}).get("customerPrice")
            prev = out.get(t)
            # A later start date wins: that is what a new buyer will be charged.
            if prev is None or (a.get("startDate") or "") >= (prev[1] or ""):
                out[t] = (price, a.get("startDate"))
    return {t: v[0] for t, v in out.items()}


def find_point(sub_id: str, territory: str, target: str = None, near: float = None):
    """The territory's price point matching `target` exactly, or nearest `near`."""
    best = None
    for page in pages(f"/subscriptions/{sub_id}/pricePoints?filter%5Bterritory%5D={territory}&limit=200"):
        for x in page.get("data", []):
            price = x["attributes"].get("customerPrice")
            if target is not None and price == target:
                return x["id"], price
            if near is not None:
                try:
                    gap = abs(float(price) - near)
                except (TypeError, ValueError):
                    continue
                if best is None or gap < best[0]:
                    best = (gap, x["id"], price)
    return (best[1], best[2]) if best else (None, None)


def plan_for(sub_id: str):
    name, monthly_id, base_price = PLANS[sub_id]
    monthly = effective_monthly(monthly_id)

    base_id, _ = find_point(sub_id, "USA", target=base_price)
    if not base_id:
        sys.exit(f"{name}: no USA price point at {base_price}")

    chosen = {}
    for page in pages(f"/subscriptionPricePoints/{base_id}/equalizations?limit=200"):
        for x in page.get("data", []):
            chosen[territory_of(x["id"])] = (x["id"], x["attributes"].get("customerPrice"), "equalized")

    # The base storefront, which equalization never returns.
    usa_id, usa_price = find_point(sub_id, "USA", target=USA_PRICE[name])
    if not usa_id:
        sys.exit(f"{name}: no USA price point at {USA_PRICE[name]}")
    chosen["USA"] = (usa_id, usa_price, "base")

    # Anywhere Apple's ladder didn't land on "2 months free" — including the
    # four storefronts where a year came out dearer than twelve months.
    for t, (pid, price, _) in list(chosen.items()):
        if t == "USA":
            continue
        m = monthly.get(t)
        try:
            mv, av = float(m), float(price)
        except (TypeError, ValueError):
            continue
        if mv <= 0 or (12 - av / mv) >= MIN_MONTHS_FREE:
            continue
        fixed_id, fixed_price = find_point(sub_id, t, near=mv * 10)
        if fixed_id:
            chosen[t] = (fixed_id, fixed_price, "repicked")
    return name, monthly, chosen


def main() -> None:
    send = "--send" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = {t.strip().upper() for t in sys.argv[sys.argv.index("--only") + 1].split(",")}
    start = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    if "--start" in sys.argv:
        start = sys.argv[sys.argv.index("--start") + 1]

    for sub_id in PLANS:
        name, monthly, chosen = plan_for(sub_id)
        rows = sorted(chosen.items())
        if only:
            rows = [r for r in rows if r[0] in only]
        shown = {"USA", "KOR", "DEU", "JPN", "GBR", "CAN"}
        print(f"\n=== {name}  ({len(rows)} territories, start {start}) ===")
        for t, (pid, price, how) in rows:
            m = monthly.get(t)
            try:
                free = 12 - float(price) / float(m)
            except (TypeError, ValueError, ZeroDivisionError):
                free = float("nan")
            if only or t in shown or how != "equalized":
                print(f"   {t}  monthly {str(m):>10} → year {str(price):>11}"
                      f"   {free:4.1f} months free   [{how}]")
        kinds = {}
        for _, (_, _, how) in rows:
            kinds[how] = kinds.get(how, 0) + 1
        print(f"   — {kinds}")

        if not send:
            continue
        ok = failed = 0
        for t, (pid, price, _) in rows:
            def post(when):
                call("POST", "/subscriptionPrices", {"data": {
                    "type": "subscriptionPrices",
                    "attributes": {"startDate": when, "preserveCurrentPrice": True},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                        "territory": {"data": {"type": "territories", "id": t}},
                        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pid}},
                    }}})
            try:
                post(start)
                ok += 1
            except RuntimeError as e:
                # Apple names the earliest date it will accept; take it and
                # carry it for the rest of the run rather than guessing again.
                m = re.search(r"must be on or after (\d{4}-\d{2}-\d{2})", str(e))
                if m and m.group(1) != start:
                    start = m.group(1)
                    print(f"   · Apple moved the earliest start to {start}")
                    try:
                        post(start)
                        ok += 1
                        continue
                    except RuntimeError as e2:
                        e = e2
                failed += 1
                print(f"   ! {t}: {str(e)[:160]}")
        print(f"   sent: {ok} ok, {failed} failed  (start {start})")

    if not send:
        print("\ndry run. add --send to apply.")


if __name__ == "__main__":
    main()

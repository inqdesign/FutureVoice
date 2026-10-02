#!/usr/bin/env python3
"""Price Max monthly at TWICE Plus monthly in every storefront (2026-10-02).

Max is 1,200 minutes against Plus's 600, and the rule is that the bigger plan
is never the dearer minute — so each territory gets the price point nearest
2 x what a NEW buyer pays for Plus monthly there (`effective_monthly`, which
skips grandfathered rows and reads a future-dated change as the price).

HOW: Plus's local prices mostly came off Apple's equalization of the old
$19.99, so equalizing $39.99 lands close to 2 x Plus nearly everywhere in one
call. Anywhere it lands more than `TOLERANCE` away — Korea, where Plus was set
by hand to ₩29,000, and the US, where Plus moved to $24.99 — is re-picked
from that territory's own price points, nearest to 2 x Plus, the lower one on
a tie.

Max has never been sold, so nobody is grandfathered and every price is an
initial price (no start date).

    scripts/asc-max-prices.py            # plan only — changes nothing
    scripts/asc-max-prices.py --send     # set the prices
    scripts/asc-max-prices.py --only KOR,USA,JPN
"""

import importlib.util
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("asc", os.path.join(_here, "asc-annual-prices.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

PLUS_MONTHLY = "6801674645"
MAX_MONTHLY = "6818453370"
EQUALIZE_FROM = "39.99"
TOLERANCE = 0.03


def nearest_point(territory: str, near: float):
    best = None
    for page in A.pages(f"/subscriptions/{MAX_MONTHLY}/pricePoints?filter%5Bterritory%5D={territory}&limit=200"):
        for x in page.get("data", []):
            try:
                price = float(x["attributes"]["customerPrice"])
            except (TypeError, ValueError, KeyError):
                continue
            gap = abs(price - near)
            # Nearest wins; on a tie, the cheaper one.
            if best is None or gap < best[0] - 1e-9 or (abs(gap - best[0]) < 1e-9 and price < best[2]):
                best = (gap, x["id"], price)
    return (best[1], best[2]) if best else (None, None)


def main() -> None:
    send = "--send" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = {t.strip().upper() for t in sys.argv[sys.argv.index("--only") + 1].split(",")}

    plus = A.effective_monthly(PLUS_MONTHLY)
    base_id, _ = A.find_point(MAX_MONTHLY, "USA", target=EQUALIZE_FROM)
    if not base_id:
        sys.exit(f"no USA price point at {EQUALIZE_FROM}")
    chosen = {"USA": (base_id, float(EQUALIZE_FROM), "equalized")}
    for page in A.pages(f"/subscriptionPricePoints/{base_id}/equalizations?limit=200"):
        for x in page.get("data", []):
            try:
                chosen[A.territory_of(x["id"])] = (x["id"], float(x["attributes"]["customerPrice"]), "equalized")
            except (TypeError, ValueError):
                pass

    rows = []
    for t in sorted(chosen):
        if only and t not in only:
            continue
        pid, price, how = chosen[t]
        try:
            target = 2 * float(plus.get(t))
        except (TypeError, ValueError):
            print(f"   {t}  no Plus monthly price — skipped")
            continue
        if abs(price - target) / target > TOLERANCE:
            new_id, new_price = nearest_point(t, target)
            if new_id:
                pid, price, how = new_id, new_price, "repicked"
        rows.append((t, pid, price, target, how))

    shown = {"USA", "KOR", "DEU", "JPN", "GBR", "CAN", "FRA", "ESP", "TWN", "AUS"}
    for t, pid, price, target, how in rows:
        off = (price - target) / target * 100
        if only or t in shown or abs(off) > 3:
            print(f"   {t}  Plus×2 {target:>12,.2f} → Max {price:>12,.2f}   {off:+5.1f}%   [{how}]")
    worst = max(rows, key=lambda r: abs(r[2] - r[3]) / r[3])
    kinds = {}
    for r in rows:
        kinds[r[4]] = kinds.get(r[4], 0) + 1
    print(f"\n   {len(rows)} territories {kinds}; furthest from Plus×2: {worst[0]} "
          f"{(worst[2] - worst[3]) / worst[3] * 100:+.1f}%")

    if not send:
        print("plan only — --send sets them")
        return
    ok = 0
    for t, pid, price, _, _ in rows:
        try:
            A.call("POST", "/subscriptionPrices", {"data": {
                "type": "subscriptionPrices",
                "attributes": {"startDate": None},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": MAX_MONTHLY}},
                    "territory": {"data": {"type": "territories", "id": t}},
                    "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pid}},
                }}})
            ok += 1
        except RuntimeError as e:
            print(f"  FAIL  {t} → {price}: {str(e)[:200]}")
    print(f"  set {ok} of {len(rows)}")


if __name__ == "__main__":
    main()

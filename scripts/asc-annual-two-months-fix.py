#!/usr/bin/env python3
"""The last seven storefronts onto "2 months free" (2026-10-01).

After `asc-annual-prices.py` (live 2026-09-29), 168 of 175 storefronts per
plan read as two months free; these seven did not, because Apple's
equalization landed on a ladder step away from ten times the monthly. Each is
re-picked from the territory's own price points, closest to 10 x monthly and
in its own ending convention. Existing subscribers keep what they pay
(`preserveCurrentPrice`).

  Light CHN  68 → 678   HKG 88 → 878   ISR 34.9 → 349.9
        PAK  2900 → 28900   TWN 320 → 3190
  Plus  CHN 148 → 1488   ISR 69.9 → 699.9

  python3 scripts/asc-annual-two-months-fix.py           # plan: finds every point, changes nothing
  python3 scripts/asc-annual-two-months-fix.py --send    # schedule the seven price changes
"""

import datetime
import importlib.util
import os
import re
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("asc", os.path.join(_here, "asc-annual-prices.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

LIGHT, PLUS = "6801673709", "6801674470"
PLAN = [
    (LIGHT, "CHN", 678), (LIGHT, "HKG", 878), (LIGHT, "ISR", 349.9),
    (LIGHT, "PAK", 28900), (LIGHT, "TWN", 3190),
    (PLUS, "CHN", 1488), (PLUS, "ISR", 699.9),
]


def point(sub_id: str, territory: str, price: float):
    for page in A.pages(f"/subscriptions/{sub_id}/pricePoints?filter%5Bterritory%5D={territory}&limit=200"):
        for x in page.get("data", []):
            try:
                if abs(float(x["attributes"]["customerPrice"]) - price) < 1e-6:
                    return x["id"]
            except (TypeError, ValueError, KeyError):
                pass
    return None


def main() -> None:
    send = "--send" in sys.argv
    start = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    for sub_id, t, price in PLAN:
        pid = point(sub_id, t, price)
        name = "light_annual" if sub_id == LIGHT else "plus_annual"
        if not pid:
            print(f"  NO POINT  {name} {t} {price}")
            continue
        if not send:
            print(f"  plan  {name} {t} → {price}")
            continue
        for _ in range(3):
            try:
                A.call("POST", "/subscriptionPrices", {"data": {
                    "type": "subscriptionPrices",
                    "attributes": {"startDate": start, "preserveCurrentPrice": True},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                        "territory": {"data": {"type": "territories", "id": t}},
                        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pid}},
                    }}})
                print(f"  ok    {name} {t} → {price} from {start}")
                break
            except RuntimeError as e:
                # Apple names the earliest date it will take; adopt it.
                m = re.search(r"must be on or after (\d{4}-\d{2}-\d{2})", str(e))
                if m and m.group(1) != start:
                    start = m.group(1)
                    continue
                print(f"  FAIL  {name} {t}: {str(e)[:200]}")
                break
    if not send:
        print("plan only — --send schedules them")


if __name__ == "__main__":
    main()

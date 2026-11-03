#!/usr/bin/env python3
"""Change a subscription's price in App Store Connect, every territory at once.

    scripts/asc-subscription-price.py max_monthly 34.99 --krw 45000          # dry run
    scripts/asc-subscription-price.py max_monthly 34.99 --krw 45000 --send   # do it

The USD price is the base: Apple's own equalization table gives each of the
other territories its matching price point (the same thing the ASC page
does when you pick a base price). `--krw` then overrides Korea with that
exact KRW price point, because the Korean price is set by hand here
(docs/launch-billing.md: KRW never followed the USD raise of 2026-09-26).
Other territories can be pinned the same way with `--territory KOR=45000`.

A decrease applies to every subscriber at their next renewal and raises no
consent sheet; an increase would, and this script refuses one unless
`--preserve` keeps current subscribers at their price (Apple's
`preserveCurrentPrice`), which is the only kind of raise this app does.

Dry run by default: prints the current price and the planned one per
territory, posts nothing. Uses the same App Store Connect key as
scripts/billing-switch.py.
"""

import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location(
    "billing_switch", os.path.join(os.path.dirname(__file__), "billing-switch.py"))
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

# Every App Store Connect call retries a 500 (2026-11-03: one in three
# answers, on reads as much as writes), so one bad answer never aborts a
# run that posts 150 prices.
_asc_plain = bs.asc


def _asc_retry(method, path, body=None):
    for attempt, pause in enumerate((0, 4, 10, 20)):
        if pause: bs.time.sleep(pause)
        try:
            return _asc_plain(method, path, body)
        except RuntimeError as e:
            if attempt == 3 or ": 500 " not in str(e):
                raise
    raise RuntimeError("unreachable")


bs.asc = _asc_retry


def price_points(sub_id: str, territory: str):
    return bs.asc_all(f"/subscriptions/{sub_id}/pricePoints?filter[territory]={territory}&limit=200")


def current_prices(sub_id: str):
    """territory → (customerPrice, price point id, startDate) for the prices on file."""
    out = {}
    url = f"/subscriptions/{sub_id}/prices?include=subscriptionPricePoint,territory&limit=200"
    page = bs.asc("GET", url)
    while True:
        included = {(i["type"], i["id"]): i for i in page.get("included", [])}
        for row in page.get("data", []):
            rel = row["relationships"]
            pp = included.get(("subscriptionPricePoints", rel["subscriptionPricePoint"]["data"]["id"]))
            terr = rel["territory"]["data"]["id"]
            price = pp["attributes"]["customerPrice"] if pp else "?"
            start = row["attributes"].get("startDate")
            # Several rows per territory (scheduled changes): keep the latest start.
            if terr not in out or (start or "") >= (out[terr][2] or ""):
                out[terr] = (price, pp["id"] if pp else None, start)
        nxt = page.get("links", {}).get("next")
        if not nxt:
            return out
        page = bs.asc("GET", nxt)


def main():
    argv = sys.argv[1:]
    args, pins = [], {}
    only = None
    send = preserve = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--send": send = True
        elif a == "--preserve": preserve = True
        elif a == "--krw": pins["KOR"] = argv[i + 1]; i += 1
        elif a.startswith("--krw="): pins["KOR"] = a.split("=", 1)[1]
        elif a == "--territory":
            t, v = argv[i + 1].split("=", 1); pins[t] = v; i += 1
        elif a == "--only": only = set(argv[i + 1].split(",")); i += 1
        elif a.startswith("--"): sys.exit(f"unknown flag {a}\n{__doc__}")
        else: args.append(a)
        i += 1
    if len(args) != 2:
        sys.exit(__doc__)
    plan_id, usd = args

    plans = {p["id"]: p for p in bs.plans_on_sale()}
    if plan_id not in plans:
        sys.exit(f"not a plan on sale: {plan_id} (have {', '.join(plans)})")
    product = plans[plan_id]["apple_product_id"]
    sub_id = bs.asc_subscriptions().get(product)
    if not sub_id:
        sys.exit(f"{product} is not in App Store Connect")
    print(f"{plan_id} = {product} (subscription {sub_id})")

    now = current_prices(sub_id)
    usa = price_points(sub_id, "USA")
    base = next((p for p in usa if p["attributes"]["customerPrice"] == usd), None)
    if not base:
        have = sorted({p["attributes"]["customerPrice"] for p in usa}, key=float)
        sys.exit(f"no USD price point {usd}; nearby: {[h for h in have if abs(float(h) - float(usd)) < 6]}")
    eq = bs.asc("GET", f"/subscriptionPricePoints/{base['id']}/equalizations?include=territory&limit=200")
    plan = {"USA": (usd, base["id"])}
    rows = list(eq.get("data", []))
    nxt = eq.get("links", {}).get("next")
    while nxt:
        page = bs.asc("GET", nxt); rows += page.get("data", []); nxt = page.get("links", {}).get("next")
    for p in rows:
        terr = p["relationships"]["territory"]["data"]["id"]
        plan[terr] = (p["attributes"]["customerPrice"], p["id"])
    for terr, want in pins.items():
        pts = price_points(sub_id, terr)
        pp = next((p for p in pts if p["attributes"]["customerPrice"] == want), None)
        if not pp:
            have = sorted({p["attributes"]["customerPrice"] for p in pts}, key=float)
            sys.exit(f"no {terr} price point {want}; nearby: {[h for h in have if abs(float(h) - float(want)) < float(want) * 0.15]}")
        plan[terr] = (want, pp["id"])

    raises = []
    changes = 0
    for terr in sorted(plan):
        new_price, pp_id = plan[terr]
        cur = now.get(terr, ("—", None, None))
        if cur[1] == pp_id:
            continue
        changes += 1
        try:
            if cur[0] != "—" and float(new_price) > float(cur[0]):
                raises.append(terr)
        except ValueError:
            pass
        if terr in ("USA", "KOR", "DEU", "JPN", "GBR") or terr in pins:
            print(f"  {terr}: {cur[0]} → {new_price}")
    print(f"{changes} territories change ({len(plan)} priced, {len(now)} currently on file)"
          + (f"; the first few: {', '.join(sorted(plan)[:6])}…" if changes > 6 else ""))
    if raises and not preserve:
        sys.exit(f"✗ this is a price INCREASE in {len(raises)} territories ({', '.join(raises[:8])}…): "
                 "Korea would get a consent sheet. Re-run with --preserve to keep current subscribers "
                 "at their price, or pick a lower price.")
    if not send:
        print("\n(dry run: add --send to post these prices)")
        return
    import datetime
    start_date = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).strftime("%Y-%m-%d")
    print(f"start date {start_date}")
    done = failed = 0
    for terr in sorted(plan):
        new_price, pp_id = plan[terr]
        if now.get(terr, (None, None, None))[1] == pp_id:
            continue
        if only and terr not in only:
            continue
        body = {"data": {"type": "subscriptionPrices",
                         # An approved subscription takes only a SCHEDULED
                         # price ("Initial price cannot be created again after
                         # subscription is approved"): the earliest Apple
                         # accepts is tomorrow, UTC.
                         "attributes": {"preserveCurrentPrice": preserve, "startDate": start_date},
                         "relationships": {
                             "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                             "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp_id}}}}}
        # Apple's API answers with a 500 now and then (2026-11-03): retry
        # each territory, and never let one stop the rest.
        for attempt, pause in enumerate((0, 2, 5)):
            if pause: bs.time.sleep(pause)
            try:
                _asc_plain("POST", "/subscriptionPrices", body); done += 1
                print(f"  {terr}: posted {new_price}", flush=True)
                break
            except RuntimeError as e:
                if attempt == 2:
                    failed += 1; print(f"  {terr}: FAILED {str(e)[-200:]}", flush=True)
    print(f"posted {done}, failed {failed}")


if __name__ == "__main__":
    main()

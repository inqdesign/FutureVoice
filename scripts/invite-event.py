#!/usr/bin/env python3
"""The friend-invite event, run from here: no app build for any of it.

    scripts/invite-event.py                  # what is live now
    scripts/invite-event.py texts            # push scripts/invite-event-texts.json
    scripts/invite-event.py offers           # make the store offers for the current %
    scripts/invite-event.py discount 30      # change the %, offers and coupon with it
    scripts/invite-event.py on | off         # the switch
    scripts/invite-event.py announce         # show the announcement sheet once more

Dry run by default: every command prints what it would do; add --send to do it.

What the app shows comes from the `invite_event` row (percent, months, the
store offer per plan, every word per language), so a change here is on
every phone at its next launch. A reward already earned keeps the terms it
was earned under.

A discount needs three things outside the database, and `offers` /
`discount` make them:
  * App Store: one promotional offer per MONTHLY plan (`friend_<N>`), priced
    in every territory from Apple's own equalization of the USD price, Korea
    pinned to its exact KRW figure;
  * Stripe: one coupon (`friend_<N>_once`), N% off, once;
  * Google Play: not made here yet (the Android app has no claim button).
Annual plans get no offer: "one month at N%" has no meaning on a year.

Uses the keys scripts/billing-switch.py uses (App Store Connect, the
Supabase CLI token) and STRIPE_SECRET_KEY as scripts/stripe-web-discount.sh
finds it.
"""

import importlib.util
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("billing_switch", os.path.join(HERE, "billing-switch.py"))
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

_asc_plain = bs.asc


def _asc_retry(method, path, body=None):
    # Apple answers 500 to one call in three some days, reads included.
    for attempt, pause in enumerate((0, 4, 10, 20)):
        if pause:
            bs.time.sleep(pause)
        try:
            return _asc_plain(method, path, body)
        except RuntimeError as e:
            if attempt == 3 or ": 500 " not in str(e):
                raise


bs.asc = _asc_retry


def lit(value) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def event():
    return bs.sql("select * from invite_event where id = 1")[0]


def monthly_plans():
    return bs.sql("select id, apple_product_id from subscription_plans "
                  "where is_active and period = 'monthly' and apple_product_id is not null order by id")


def show():
    e = event()
    print(f"event         {'ON' if e['enabled'] else 'off'}")
    print(f"discount      {e['percent']}% for {e['months']} month(s)")
    print(f"announcement  version {e['announce_version']}")
    print(f"stripe coupon {e['stripe_coupon_id'] or '-'}")
    print("app store offers")
    for product, offer in (e["apple_offers"] or {}).items():
        print(f"   {product:48s} {offer}")
    if not e["apple_offers"]:
        print("   -")
    print(f"texts         {', '.join(f'{k} ({len(v)})' for k, v in (e['texts'] or {}).items()) or '-'}")
    counts = bs.sql("select status, count(*) n from invite_rewards group by 1 order by 1")
    print(f"rewards       {', '.join(str(r['n']) + ' ' + r['status'] for r in counts) or 'none yet'}")


def write(assignments: str, send: bool):
    query = f"update invite_event set {assignments}, updated_at = now() where id = 1"
    print(("RUN  " if send else "would run  ") + query[:400] + ("…" if len(query) > 400 else ""))
    if send:
        bs.sql(query)


# ── App Store ──────────────────────────────────────────────────────────────

def current_prices(sub_id: str):
    """territory -> customer price now on sale."""
    out = {}
    page = bs.asc("GET", f"/subscriptions/{sub_id}/prices?include=subscriptionPricePoint,territory&limit=200")
    while True:
        included = {(i["type"], i["id"]): i for i in page.get("included", [])}
        for row in page.get("data", []):
            rel = row["relationships"]
            point = included.get(("subscriptionPricePoints", rel["subscriptionPricePoint"]["data"]["id"]))
            territory = rel["territory"]["data"]["id"]
            start = row["attributes"].get("startDate") or ""
            if point and (territory not in out or start >= out[territory][1]):
                out[territory] = (float(point["attributes"]["customerPrice"]), start)
        nxt = page.get("links", {}).get("next")
        if not nxt:
            return {t: p for t, (p, _) in out.items()}
        page = bs.asc("GET", nxt)


def nearest_point(sub_id: str, territory: str, target: float):
    points = bs.asc_all(f"/subscriptions/{sub_id}/pricePoints?filter[territory]={territory}&limit=200")
    return min(points, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - target))


def apple_offer(sub_id: str, product: str, percent: int, months: int, send: bool):
    code = f"friend_{percent}"
    existing = bs.asc_all(f"/subscriptions/{sub_id}/promotionalOffers?limit=50")
    if any(o["attributes"]["offerCode"] == code for o in existing):
        print(f"   {product}: offer {code} already there")
        return code
    prices = current_prices(sub_id)
    keep = (100 - percent) / 100
    usa = nearest_point(sub_id, "USA", prices["USA"] * keep)
    points = {"USA": usa["id"]}
    for eq in bs.asc_all(f"/subscriptionPricePoints/{usa['id']}/equalizations?include=territory&limit=200"):
        territory = eq["relationships"]["territory"]["data"]["id"]
        if territory in prices:
            points[territory] = eq["id"]
    shown = {"USA": usa["attributes"]["customerPrice"]}
    if "KOR" in prices:
        kor = nearest_point(sub_id, "KOR", prices["KOR"] * keep)
        points["KOR"] = kor["id"]
        shown["KOR"] = kor["attributes"]["customerPrice"]
    print(f"   {product}: {code} in {len(points)} territories "
          f"(USA {prices['USA']} -> {shown['USA']}"
          + (f", KOR {prices['KOR']:.0f} -> {shown['KOR']}" if "KOR" in shown else "") + ")")
    if not send:
        return code
    period = "ONE_MONTH" if months == 1 else {2: "TWO_MONTHS", 3: "THREE_MONTHS", 6: "SIX_MONTHS"}.get(months)
    if period is None:
        sys.exit(f"the App Store has no {months}-month offer length (1, 2, 3 or 6)")
    bs.asc("POST", "/subscriptionPromotionalOffers", {
        "data": {
            "type": "subscriptionPromotionalOffers",
            "attributes": {"name": f"Friend invite {percent}%", "offerCode": code,
                           "duration": period, "offerMode": "PAY_UP_FRONT" if months > 1 else "PAY_AS_YOU_GO",
                           "numberOfPeriods": 1},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "prices": {"data": [{"type": "subscriptionPromotionalOfferPrices", "id": "${%s}" % t}
                                    for t in points]},
            },
        },
        "included": [{
            "type": "subscriptionPromotionalOfferPrices", "id": "${%s}" % t,
            "relationships": {
                "territory": {"data": {"type": "territories", "id": t}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": p}},
            }} for t, p in points.items()],
    })
    return code


# ── Stripe ─────────────────────────────────────────────────────────────────

def stripe_key():
    key = os.environ.get("STRIPE_SECRET_KEY")
    if not key:
        env = os.path.expanduser("~/humhumhum/.env.local")
        if os.path.exists(env):
            for line in open(env):
                if line.startswith("STRIPE_SECRET_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"')
    return key if key and key.startswith("sk_") else None


def stripe_coupon(percent: int, months: int, send: bool):
    coupon = f"friend_{percent}_once" if months == 1 else f"friend_{percent}_{months}m"
    key = stripe_key()
    if not key:
        print(f"   stripe: no STRIPE_SECRET_KEY here, coupon {coupon} NOT checked")
        return None
    def call(method, path, data=None):
        req = urllib.request.Request("https://api.stripe.com/v1" + path, method=method,
                                     data=urllib.parse.urlencode(data).encode() if data else None,
                                     headers={"Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(req) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            return {"error": e.code, "body": e.read().decode()[:200]}
    if "error" not in call("GET", f"/coupons/{coupon}"):
        print(f"   stripe: coupon {coupon} already there")
        return coupon
    print(f"   stripe: coupon {coupon} ({percent}% off, {'once' if months == 1 else str(months) + ' months'})")
    if send:
        data = {"id": coupon, "percent_off": percent, "name": f"Friend invite {percent}%"}
        data.update({"duration": "once"} if months == 1
                    else {"duration": "repeating", "duration_in_months": months})
        made = call("POST", "/coupons", data)
        if "error" in made:
            sys.exit(f"stripe refused the coupon: {made}")
    return coupon


def offers(percent: int, months: int, send: bool):
    """Make what the stores need for this size, then point the event at it."""
    subs = bs.asc_subscriptions()
    apple = {}
    print("app store")
    for plan in monthly_plans():
        product = plan["apple_product_id"]
        if product not in subs:
            print(f"   {product}: not in App Store Connect, skipped")
            continue
        apple[product] = apple_offer(subs[product], product, percent, months, send)
    print("stripe")
    coupon = stripe_coupon(percent, months, send)
    assignments = (f"percent = {percent}, months = {months}, "
                   f"apple_offers = {lit(json.dumps(apple))}::jsonb")
    if coupon:
        assignments += f", stripe_coupon_id = {lit(coupon)}"
    write(assignments, send)


def main():
    argv = [a for a in sys.argv[1:] if a != "--send"]
    send = "--send" in sys.argv
    if not argv:
        return show()
    cmd = argv[0]
    if cmd == "texts":
        texts = json.load(open(os.path.join(HERE, "invite-event-texts.json")))
        print(f"texts: {', '.join(f'{k} ({len(v)} lines)' for k, v in texts.items())}")
        write(f"texts = {lit(json.dumps(texts, ensure_ascii=False))}::jsonb", send)
    elif cmd == "offers":
        e = event()
        offers(e["percent"], e["months"], send)
    elif cmd == "discount" and len(argv) >= 2:
        percent = int(argv[1])
        months = int(argv[2]) if len(argv) > 2 else event()["months"]
        if percent != 50:
            print("NOTE: the texts say 'half price'. Change scripts/invite-event-texts.json "
                  "and run `texts` too, or the words and the number disagree.")
        offers(percent, months, send)
    elif cmd in ("on", "off"):
        e = event()
        if cmd == "on" and (not e["texts"] or not e["apple_offers"]):
            sys.exit("not ready: run `texts` and `offers` first (no words or no App Store offer on file)")
        write(f"enabled = {'true' if cmd == 'on' else 'false'}", send)
    elif cmd == "announce":
        write("announce_version = announce_version + 1", send)
    else:
        sys.exit(__doc__)
    if not send and cmd != "show":
        print("\ndry run. Add --send to do it.")


if __name__ == "__main__":
    main()

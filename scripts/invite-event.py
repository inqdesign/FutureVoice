#!/usr/bin/env python3
"""The friend-invite event, run from here: no app build for any of it.

    scripts/invite-event.py                  # what is live now
    scripts/invite-event.py texts            # push scripts/invite-event-texts.json
    scripts/invite-event.py offers           # make the store offers for the current %
    scripts/invite-event.py codes            # top up the App Store one-time codes
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
  * App Store: one offer-code offer per MONTHLY plan ("Friend invite N% <plan>",
    existing subscribers only), priced in every territory from Apple's own
    equalization of the USD price, Korea pinned to its exact KRW figure. Each
    reward spends ONE one-time code of it, so `codes` keeps a pool on file
    (500 at a time, six months' life; run it again whenever `show` says a
    plan is under 100);
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
    for row in bs.sql("select apple_product_id, count(*) filter (where reward_id is null "
                      "and expires_on > current_date + 1) free, count(*) filter (where reward_id is not null) given "
                      "from invite_offer_codes group by 1 order by 1"):
        print(f"   codes {row['apple_product_id']:42s} {row['free']} unused, {row['given']} handed out")
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


def offer_name(percent: int, plan_id: str) -> str:
    # Apple's renewal info names the offer by this, and the database matches
    # on it (`invite_reward_on_offer`), so it is never reworded.
    return f"Friend invite {percent}% {plan_id}"


def find_offer(sub_id: str, name: str):
    return next((o for o in bs.asc_all(f"/subscriptions/{sub_id}/offerCodes?limit=50")
                 if o["attributes"]["name"] == name), None)


def apple_offer(sub_id: str, product: str, plan_id: str, percent: int, months: int, send: bool):
    """An OFFER-CODE offer for existing subscribers: redeemed, it prices the
    next renewal. (A signed promotional offer does nothing for an active
    subscriber through StoreKit 2: sandbox, 2026-11-19.)"""
    name = offer_name(percent, plan_id)
    if find_offer(sub_id, name):
        print(f"   {product}: offer \"{name}\" already there")
        return name
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
    print(f"   {product}: \"{name}\" in {len(points)} territories "
          f"(USA {prices['USA']} -> {shown['USA']}"
          + (f", KOR {prices['KOR']:.0f} -> {shown['KOR']}" if "KOR" in shown else "") + ")")
    if not send:
        return name
    bs.asc("POST", "/subscriptionOfferCodes", {
        "data": {
            "type": "subscriptionOfferCodes",
            "attributes": {"name": name, "customerEligibilities": ["EXISTING"],
                           "offerEligibility": "REPLACE_INTRO_OFFERS",
                           "duration": "ONE_MONTH", "offerMode": "PAY_AS_YOU_GO",
                           "numberOfPeriods": months},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "prices": {"data": [{"type": "subscriptionOfferCodePrices", "id": "${%s}" % t}
                                    for t in points]},
            },
        },
        "included": [{
            "type": "subscriptionOfferCodePrices", "id": "${%s}" % t,
            "relationships": {
                "territory": {"data": {"type": "territories", "id": t}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": p}},
            }} for t, p in points.items()],
    })
    return name


# ── App Store: the pool of one-time codes ──────────────────────────────────

BATCH = 500      # Apple's smallest production batch
FLOOR = 100      # top up when fewer unused codes than this are left for a plan


def batch_values(batch_id: str):
    req = urllib.request.Request(
        bs.ASC + f"/subscriptionOfferCodeOneTimeUseCodes/{batch_id}/values",
        headers={"Authorization": f"Bearer {bs.asc_token()}", "Accept": "text/csv", **bs.UA})
    for pause in (0, 5, 15, 30):
        if pause:
            bs.time.sleep(pause)
        try:
            with urllib.request.urlopen(req) as r:
                return [line.strip() for line in r.read().decode().splitlines() if line.strip()]
        except urllib.error.HTTPError:
            continue
    return []


def codes(send: bool):
    """Every live batch's codes are on file, and each plan has FLOOR to spare.
    Safe to run any time: a code already on file is left as it is."""
    e = event()
    subs = bs.asc_subscriptions()
    today = bs.time.strftime("%Y-%m-%d")
    for product, name in (e["apple_offers"] or {}).items():
        offer = find_offer(subs[product], name) if product in subs else None
        if not offer:
            print(f"   {product}: no offer \"{name}\" in App Store Connect. Run `offers` first.")
            continue
        batches = [b for b in bs.asc_all(f"/subscriptionOfferCodes/{offer['id']}/oneTimeUseCodes?limit=50")
                   if b["attributes"].get("environment", "PRODUCTION") == "PRODUCTION"
                   and b["attributes"]["active"] and b["attributes"]["expirationDate"] > today]
        free = bs.sql("select count(*) n from invite_offer_codes where reward_id is null "
                      f"and apple_product_id = {lit(product)} and expires_on > current_date + 1")[0]["n"]
        print(f"   {product}: {free} unused codes on file, {len(batches)} live batch(es)")
        if free < FLOOR:
            # Apple lets a code live six months at most.
            expires = bs.time.strftime("%Y-%m-%d", bs.time.gmtime(bs.time.time() + 170 * 86400))
            print(f"   {product}: {'making' if send else 'would make'} {BATCH} codes, good until {expires}")
            if send:
                made = bs.asc("POST", "/subscriptionOfferCodeOneTimeUseCodes", {"data": {
                    "type": "subscriptionOfferCodeOneTimeUseCodes",
                    "attributes": {"numberOfCodes": BATCH, "expirationDate": expires,
                                   "environment": "PRODUCTION"},
                    "relationships": {"offerCode": {"data": {"type": "subscriptionOfferCodes",
                                                             "id": offer["id"]}}}}})["data"]
                batches.append(made)
        if not send:
            continue
        for batch in batches:
            values = batch_values(batch["id"])
            if not values:
                print(f"   {product}: batch {batch['id']} gave no codes yet. Run `codes --send` again later.")
                continue
            rows = ", ".join(f"({lit(v)}, {lit(product)}, {lit(batch['attributes']['expirationDate'])})"
                             for v in values)
            added = bs.sql("with ins as (insert into invite_offer_codes (code, apple_product_id, expires_on) "
                           f"values {rows} on conflict (code) do nothing returning 1) select count(*) n from ins")[0]["n"]
            print(f"   {product}: batch {batch['id']}: {added} new codes on file")


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
        apple[product] = apple_offer(subs[product], product, plan["id"], percent, months, send)
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
    elif cmd == "codes":
        codes(send)
    elif cmd in ("on", "off"):
        e = event()
        if cmd == "on" and (not e["texts"] or not e["apple_offers"]):
            sys.exit("not ready: run `texts` and `offers` first (no words or no App Store offer on file)")
        if cmd == "on" and not bs.sql("select 1 from invite_offer_codes where reward_id is null limit 1"):
            sys.exit("not ready: run `codes --send` first (no App Store codes on file)")
        write(f"enabled = {'true' if cmd == 'on' else 'false'}", send)
    elif cmd == "announce":
        write("announce_version = announce_version + 1", send)
    else:
        sys.exit(__doc__)
    if not send and cmd != "show":
        print("\ndry run. Add --send to do it.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""The free offer's switches, without a build (2026-10-21).

    scripts/billing-switch.py                         # show everything as it stands
    scripts/billing-switch.py free 20                 # new accounts start with 20 free minutes
    scripts/billing-switch.py free 0                  # no free minutes: the first paid tap meets the plans
    scripts/billing-switch.py offer-at onboarding     # offer the trial once, right after onboarding
    scripts/billing-switch.py offer-at after_free     # offer the plans when the free minutes run out (default)
    scripts/billing-switch.py trial-minutes 60        # a trial may talk 60 minutes in all
    scripts/billing-switch.py recharge 20             # the one free recharge after the free minutes is 20 min
    scripts/billing-switch.py recharge 0              # no recharge: the report's last card shows Subscribe alone
    scripts/billing-switch.py trial-minutes default   # back to Light's month x 7/30 (35 min)
    scripts/billing-switch.py trial on 1w             # a free trial on every plan on sale (3d|1w|2w|1m)
    scripts/billing-switch.py trial off               # no trial anywhere

DRY RUN by default: every command prints what it would do. Add --send to do it.

What each switch is:

  free / offer-at   one row, `public.billing_config` (20261021120000). New
                    accounts read `free` at signup; the app reads both on every
                    foreground (`BillingConfig`, iOS and Android). A change to
                    `free` never touches existing accounts — topping them up is
                    a separate decision, done the way 20260926100000 did it.
  trial-minutes     `billing_config.trial_talk_seconds` (20261022120000): what a
                    trialing account may talk in its WHOLE trial, whatever the
                    trial's length. The meter, the app's usage figure, the
                    voiceover's wall and the admin console all read it through
                    `trial_talk_seconds()`. Builds after 1.2.2 print it on the
                    paywall; older ones still print 35 there (they understate).
  recharge          `billing_config.free_recharge_seconds` (20261103150000):
                    what "Recharge N min free" on the trial report's last
                    card gives, once per account, once the free minutes are
                    spent (`claim_free_recharge`). The apps ask the server
                    (`free_recharge_offer`) and draw the button only on
                    `available`, so 0 removes it from every build at once.
  trial             the STORES' switch, not ours. App Store: an introductory
                    free-trial offer on every subscription on sale, in every
                    territory it is sold in. Google Play: the offer called
                    PLAY_OFFER_ID on each plan's base plan, activated or
                    deactivated (create it once in Play Console with that id;
                    the script never invents a Play offer's pricing). The apps
                    draw a trial only when the store says this account can
                    take one, so turning it off needs no app change either.

Facts to keep in mind when flipping:

  * Korea asks for a second consent before a trial turns into a charge
    (PriceConsent, 20261018170000). A 3-day trial gets no reminder from Apple;
    1w or longer does. That is why 1w is the shortest the script suggests.
  * A trialing account is metered at Light's month × 7/30 whatever the trial's
    length (`consume_metered_seconds`).
  * Apple takes from minutes to an hour to show a new or removed offer.
  * Only builds that read `billing_config` (iOS and Android after 1.2.2)
    follow `free` in their ring and `offer-at` at all; older builds keep the
    grant they were shipped with on screen, while the SERVER grant changes for
    everyone at once.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROJECT_REF = "chhzjtigzdotacutwcyo"
ASC = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6792794655"
PACKAGE = "com.roro.futurevoice"
PLAY = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
PLAY_KEY = os.environ.get("PLAY_SERVICE_ACCOUNT", os.path.expanduser("~/keys/play-service-account.json"))
PLAY_OFFER_ID = "free-trial"
UA = {"User-Agent": "nawana-billing-switch/1"}

DURATIONS = {"3d": "THREE_DAYS", "1w": "ONE_WEEK", "2w": "TWO_WEEKS", "1m": "ONE_MONTH"}


# ── Supabase ───────────────────────────────────────────────────────────────

def sql(query: str):
    raw = subprocess.run(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                         capture_output=True, text=True, check=True).stdout.strip()
    token = base64.b64decode(raw.removeprefix("go-keyring-base64:")).decode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", **UA})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"SQL: {e.code} {e.read().decode()[:300]}")


def plans_on_sale():
    return sql("select id, apple_product_id, google_product_id from subscription_plans "
               "where is_active order by id")


# ── App Store Connect ──────────────────────────────────────────────────────

_asc_token = None
_asc_token_at = 0.0


def asc_token() -> str:
    # A token lives 20 minutes and a full `trial off` is 875 deletes, which
    # takes about that long: the run of 2026-11-03 lost its token on the last
    # 39 territories of the last plan. Made again after 10 minutes.
    global _asc_token, _asc_token_at
    if _asc_token and time.time() - _asc_token_at < 600:
        return _asc_token
    _asc_token_at = time.time()
    key_dir = os.path.expanduser("~/.appstoreconnect/private_keys")
    keys = sorted(f for f in os.listdir(key_dir) if f.startswith("AuthKey_") and f.endswith(".p8"))
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
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                         input=signing, capture_output=True, check=True).stdout
    parsed = subprocess.run(["openssl", "asn1parse", "-inform", "DER"],
                            input=der, capture_output=True, check=True).stdout.decode()
    ints = [ln.split(":")[-1].strip() for ln in parsed.splitlines() if "INTEGER" in ln]
    sig = b"".join(bytes.fromhex(i.rjust(64, "0")) for i in ints)
    _asc_token = f"{header}.{payload}.{b64(sig)}"
    return _asc_token


def offer_territory(offer) -> str:
    """The territory an offer row belongs to, for a message."""
    try:
        return offer["relationships"]["territory"]["data"]["id"]
    except (KeyError, TypeError):
        try:
            raw = offer["id"] + "=" * (-len(offer["id"]) % 4)
            return json.loads(base64.b64decode(raw)).get("i", offer["id"])
        except Exception:
            return offer["id"]


def asc(method: str, path: str, body=None):
    url = path if path.startswith("http") else ASC + path
    req = urllib.request.Request(url, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {asc_token()}",
                                          "Content-Type": "application/json", **UA})
    try:
        with urllib.request.urlopen(req) as r:
            out = r.read()
            return json.loads(out) if out else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"ASC {method} {path}: {e.code} {e.read().decode()[:400]}")


def asc_all(path: str):
    out, url = [], ASC + path
    while url:
        page = asc("GET", url)
        out += page.get("data", [])
        url = page.get("links", {}).get("next")
    return out


def asc_subscriptions():
    """productId → subscription id, for every subscription of the app."""
    found = {}
    for group in asc_all(f"/apps/{APP_ID}/subscriptionGroups?limit=50"):
        for sub in asc_all(f"/subscriptionGroups/{group['id']}/subscriptions?limit=50"):
            found[sub["attributes"]["productId"]] = sub["id"]
    return found


def asc_territories(sub_id: str):
    avail = asc("GET", f"/subscriptions/{sub_id}/subscriptionAvailability")
    avail_id = (avail.get("data") or {}).get("id")
    if not avail_id:
        return []
    return [t["id"] for t in asc_all(f"/subscriptionAvailabilities/{avail_id}/availableTerritories?limit=200")]


def asc_offers(sub_id: str):
    return asc_all(f"/subscriptions/{sub_id}/introductoryOffers?limit=200&include=territory")


# ── Google Play ────────────────────────────────────────────────────────────

_play_token = None


def play_token() -> str:
    global _play_token
    if _play_token:
        return _play_token
    sa = json.load(open(PLAY_KEY))

    def b64(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    now = int(time.time())
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64(json.dumps({"iss": sa["client_email"],
                             "scope": "https://www.googleapis.com/auth/androidpublisher",
                             "aud": "https://oauth2.googleapis.com/token",
                             "iat": now, "exp": now + 3600}).encode())
    key_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".play-key.pem")
    try:
        with open(key_file, "w") as f:
            f.write(sa["private_key"])
        os.chmod(key_file, 0o600)
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_file],
                             input=f"{header}.{claims}".encode(), capture_output=True, check=True).stdout
    finally:
        if os.path.exists(key_file):
            os.remove(key_file)
    assertion = f"{header}.{claims}.{b64(sig)}"
    data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": assertion}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=data)) as r:
        _play_token = json.load(r)["access_token"]
    return _play_token


def play(method: str, path: str, body=None):
    req = urllib.request.Request(PLAY + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {play_token()}",
                                          "Content-Type": "application/json", **UA})
    try:
        with urllib.request.urlopen(req) as r:
            out = r.read()
            return json.loads(out) if out else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Play {method} {path}: {e.code} {e.read().decode()[:400]}")


def play_trial_offers(product_id: str):
    """[(basePlanId, offer state or None)] for PLAY_OFFER_ID on each base plan."""
    sub = play("GET", f"/subscriptions/{product_id}")
    out = []
    for bp in sub.get("basePlans", []):
        bp_id = bp["basePlanId"]
        try:
            offer = play("GET", f"/subscriptions/{product_id}/basePlans/{bp_id}/offers/{PLAY_OFFER_ID}")
            out.append((bp_id, offer.get("state")))
        except RuntimeError as e:
            out.append((bp_id, None if " 404 " in str(e) else f"? {e}"))
    return out


# ── Commands ───────────────────────────────────────────────────────────────

def show():
    try:
        row = sql("select free_talk_seconds, trial_offer_at, updated_at from billing_config")
    except RuntimeError:
        row = None
    if row:
        r = row[0]
        print(f"free minutes for new accounts: {r['free_talk_seconds'] // 60} "
              f"({r['free_talk_seconds']} s)")
        print(f"trial offered: {r['trial_offer_at']}   (set {r['updated_at']})")
        try:
            t = sql("select trial_talk_seconds from billing_config")[0]["trial_talk_seconds"]
            print("trial talk time: " + (f"{t // 60} min ({t} s)" if t is not None
                                         else "default, Light's month x 7/30 (35 min)"))
        except RuntimeError:
            print("trial talk time: default (migration 20261022120000 not applied)")
        try:
            r2 = sql("select free_recharge_seconds from billing_config")[0]["free_recharge_seconds"]
            print(f"free recharge after the free minutes: {r2 // 60} min ({r2} s)"
                  + (" — off, no button" if r2 == 0 else ""))
        except RuntimeError:
            print("free recharge: none (migration 20261103150000 not applied)")
    else:
        print("billing_config: no row (migration 20261021120000 not applied?)")

    plans = plans_on_sale()
    print("\nApp Store free trials:")
    subs = asc_subscriptions()
    for p in plans:
        sub_id = subs.get(p["apple_product_id"])
        if not sub_id:
            print(f"  {p['id']:14} not in App Store Connect")
            continue
        offers = asc_offers(sub_id)
        free = [o for o in offers if o["attributes"].get("offerMode") == "FREE_TRIAL"]
        kinds = sorted({o["attributes"].get("duration") for o in free})
        print(f"  {p['id']:14} {len(free)} territories {', '.join(kinds) or 'none'}")

    print("\nGoogle Play free trials (offer id '%s'):" % PLAY_OFFER_ID)
    if not os.path.exists(PLAY_KEY):
        print(f"  no Play key at {PLAY_KEY}")
        return
    for p in plans:
        if not p.get("google_product_id"):
            continue
        try:
            states = play_trial_offers(p["google_product_id"])
            text = ", ".join(f"{bp}: {st or 'not created'}" for bp, st in states) or "no base plans"
        except RuntimeError as e:
            text = f"? {e}"
        print(f"  {p['id']:14} {text}")


def set_free(minutes: str, send: bool):
    try:
        m = int(minutes)
    except ValueError:
        sys.exit(f"not a number of minutes: {minutes}")
    if not 0 <= m <= 600:
        sys.exit("free minutes must be 0–600")
    q = f"update billing_config set free_talk_seconds = {m * 60}, updated_at = now() where id"
    print(("SEND: " if send else "dry run: ") + q)
    print("  existing accounts are NOT topped up; new accounts start with "
          f"{m} min" + (" (no free minutes: the first paid tap meets the plans)" if m == 0 else ""))
    if send:
        sql(q)
        show()


def set_offer_at(where: str, send: bool):
    if where not in ("after_free", "onboarding"):
        sys.exit("offer-at is after_free or onboarding")
    q = f"update billing_config set trial_offer_at = '{where}', updated_at = now() where id"
    print(("SEND: " if send else "dry run: ") + q)
    if where == "onboarding":
        print("  shown only while a store trial is on (scripts/billing-switch.py trial on 1w)")
    if send:
        sql(q)
        show()


def set_trial_minutes(minutes: str, send: bool):
    if minutes in ("default", "null"):
        value = "null"
        said = "back to Light's month x 7/30 (35 min)"
    else:
        try:
            m = int(minutes)
        except ValueError:
            sys.exit(f"not a number of minutes: {minutes}")
        if not 0 <= m <= 600:
            sys.exit("trial minutes must be 0–600")
        value, said = str(m * 60), f"{m} min for the whole trial"
    q = f"update billing_config set trial_talk_seconds = {value}, updated_at = now() where id"
    print(("SEND: " if send else "dry run: ") + q)
    print(f"  every trialing account, running trials included: {said}")
    if send:
        sql(q)
        show()


def trial(state: str, length: str, send: bool):
    if state not in ("on", "off"):
        sys.exit("trial on <3d|1w|2w|1m> | trial off")
    if state == "on" and length not in DURATIONS:
        sys.exit(f"trial length is one of {', '.join(DURATIONS)}")
    if state == "on" and length == "3d":
        print("note: Apple sends Korea's consent reminder only for 1w or longer")
    plans = plans_on_sale()
    subs = asc_subscriptions()

    print("App Store:")
    for p in plans:
        sub_id = subs.get(p["apple_product_id"])
        if not sub_id:
            print(f"  {p['id']:14} not in App Store Connect, skipped")
            continue
        offers = asc_offers(sub_id)
        if state == "off":
            print(f"  {p['id']:14} delete {len(offers)} introductory offers")
            if send:
                # Apple answers a DELETE with a 500 now and then (2026-11-03,
                # the very first of 875): retry it, and never let one
                # territory stop the other 874 — what is left is printed and
                # a second run deletes it.
                failed = []
                for o in offers:
                    for attempt, pause in enumerate((0, 2, 6)):
                        time.sleep(pause)
                        try:
                            asc("DELETE", f"/subscriptionIntroductoryOffers/{o['id']}")
                            break
                        except RuntimeError as e:
                            if attempt == 2:
                                failed.append((offer_territory(o), str(e)[-120:]))
                print(f"  {p['id']:14} deleted {len(offers) - len(failed)}"
                      + (f", FAILED {len(failed)}: " + ", ".join(t for t, _ in failed)
                         + "\n    last error: " + failed[-1][1] if failed else ""))
            continue
        have = {(o["relationships"]["territory"]["data"] or {}).get("id") for o in offers
                if o.get("relationships", {}).get("territory", {}).get("data")}
        todo = [t for t in asc_territories(sub_id) if t not in have]
        print(f"  {p['id']:14} add a {length} free trial in {len(todo)} territories "
              f"({len(have)} already have an offer, left as they are)")
        if send:
            for t in todo:
                asc("POST", "/subscriptionIntroductoryOffers", {"data": {
                    "type": "subscriptionIntroductoryOffers",
                    "attributes": {"duration": DURATIONS[length], "offerMode": "FREE_TRIAL",
                                   "numberOfPeriods": 1},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                        "territory": {"data": {"type": "territories", "id": t}}}}})

    print("Google Play:")
    if not os.path.exists(PLAY_KEY):
        print(f"  no Play key at {PLAY_KEY}, skipped")
        return
    action = "activate" if state == "on" else "deactivate"
    for p in plans:
        pid = p.get("google_product_id")
        if not pid:
            continue
        try:
            states = play_trial_offers(pid)
        except RuntimeError as e:
            print(f"  {p['id']:14} ? {e}")
            continue
        for bp, st in states:
            if st is None:
                print(f"  {p['id']:14} {bp}: no '{PLAY_OFFER_ID}' offer — create it once in Play Console"
                      + (f" ({length} free trial)" if state == "on" else ""))
                continue
            want = "ACTIVE" if state == "on" else "INACTIVE"
            if st == want:
                print(f"  {p['id']:14} {bp}: already {st}")
                continue
            print(f"  {p['id']:14} {bp}: {st} -> {action}")
            if send:
                play("POST", f"/subscriptions/{pid}/basePlans/{bp}/offers/{PLAY_OFFER_ID}:{action}", {})
    if state == "on":
        print("note: the Play offer's own length is set where it was created; "
              f"'{length}' applies to the App Store only")


def set_recharge(minutes: str, send: bool):
    try:
        m = int(minutes)
    except ValueError:
        sys.exit(f"not a number of minutes: {minutes}")
    if not 0 <= m <= 600:
        sys.exit("recharge minutes must be 0–600")
    q = f"update billing_config set free_recharge_seconds = {m * 60}, updated_at = now() where id"
    print(("SEND: " if send else "dry run: ") + q)
    print("  accounts that already took their recharge are unchanged; "
          + ("the button disappears everywhere" if m == 0 else
             f"the next tap on 'Recharge free' gives {m} min, once per account"))
    if send:
        sql(q)
        show()


def main():
    args = [a for a in sys.argv[1:] if a != "--send"]
    send = "--send" in sys.argv[1:]
    if not args:
        show()
    elif args[0] == "free" and len(args) == 2:
        set_free(args[1], send)
    elif args[0] == "trial-minutes" and len(args) == 2:
        set_trial_minutes(args[1], send)
    elif args[0] == "recharge" and len(args) == 2:
        set_recharge(args[1], send)
    elif args[0] == "offer-at" and len(args) == 2:
        set_offer_at(args[1], send)
    elif args[0] == "trial" and len(args) >= 2:
        trial(args[1], args[2] if len(args) > 2 else "", send)
    else:
        sys.exit(__doc__)
    if not send and args:
        print("\n(dry run: add --send to do it)")


if __name__ == "__main__":
    main()

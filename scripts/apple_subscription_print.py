#!/usr/bin/env python3
"""Pretty-print one App Store Server API subscription-status payload.

Reads the JSON on stdin (see scripts/apple-subscription.sh, which signs the
call). Its own file rather than a heredoc because the f-strings here quote
JSON keys, and a shell-embedded script cannot carry both quote styles.
"""
import sys, json, base64, datetime

STATUS = {1: "active", 2: "expired", 3: "billing retry", 4: "grace", 5: "revoked"}
OFFER = {1: "intro", 2: "promotional", 3: "offer code", 4: "win-back"}


def jwt(token: str) -> dict:
    """Apple's payloads are signed; the signature was checked by fetching them
    from Apple over TLS, so this only decodes."""
    p = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))


def when(ms) -> str:
    if not ms:
        return "—"
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.UTC).strftime("%Y-%m-%d %H:%M UTC")


def money(milli, currency) -> str:
    if milli is None or currency is None:
        return "—"
    return f"{milli / 1000:,.2f} {currency}"


def offer_note(info: dict) -> str:
    kind = info.get("offerType")
    if not kind:
        return ""
    name = OFFER.get(kind, kind)
    ident = info.get("offerIdentifier")
    return f"  [{name} {ident}]" if ident else f"  [{name}]"


def main() -> int:
    d = json.load(sys.stdin)
    if "data" not in d:
        print(d.get("errorMessage") or json.dumps(d))
        return 1

    print(f'{d["bundleId"]} · {d["environment"]}')
    for group in d["data"]:
        for last in group["lastTransactions"]:
            t = jwt(last["signedTransactionInfo"])
            r = jwt(last["signedRenewalInfo"])
            status = STATUS.get(last["status"], last["status"])
            print()
            print(f'  {t.get("productId")}  [{status}]')
            print(f'    original tx   {last["originalTransactionId"]}'
                  f'  group {group["subscriptionGroupIdentifier"]}')
            print(f'    storefront    {t.get("storefront")}  ({t.get("currency")})')
            print(f'    this period   {when(t.get("purchaseDate"))} → {when(t.get("expiresDate"))}')
            print(f'    charged       {money(t.get("price"), t.get("currency"))}{offer_note(t)}')
            if t.get("revocationDate"):
                print(f'    REVOKED       {when(t.get("revocationDate"))}'
                      f'  reason {t.get("revocationReason")}')
            renews = r.get("autoRenewStatus") == 1
            print(f'    auto-renew    {"on" if renews else "OFF — ends at the date above"}')
            if renews:
                print(f'    next charge   {money(r.get("renewalPrice"), r.get("currency"))}'
                      f'{offer_note(r)}  on {when(r.get("renewalDate"))}')
                if r.get("autoRenewProductId") != t.get("productId"):
                    print(f'    CHANGES TO    {r.get("autoRenewProductId")}')
            token = t.get("appAccountToken")
            print(f'    our user      {token}' if token
                  else '    our user      — (no appAccountToken: bought outside the app)')
    return 0


if __name__ == "__main__":
    sys.exit(main())

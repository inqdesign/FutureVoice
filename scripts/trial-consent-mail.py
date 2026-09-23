#!/usr/bin/env python3
"""A way back for learners whose trial lapsed on Apple's consent step.

Korea asks for explicit consent before the first charge after a free trial —
Apple runs it as a PRICE INCREASE (₩0 → the plan's price). Measured
2026-09-23: every Korean trialer who reached their renewal date got the
prompt, four of six never answered it, and their subscription expired with
`expirationIntent 3` while auto-renew was still ON. Two US trialers in the
same week, same products, renewed silently. Nothing was wrong with their card
and nothing was wrong with our prices. See CLAUDE.md / memory
`korea-trial-needs-consent`.

Two situations, and the mail must not confuse them:

  resume  — Apple is still in its billing retry window and auto-renew is on.
            One confirmation in Settings brings the subscription back; there
            is nothing to buy again.
  restart — auto-renew is off and the retry window is done. Subscribing again
            is the only way back, and this mail must not push for it.

Which one each person is in is READ FROM APPLE at run time
(`scripts/apple-subscription.sh`), never assumed from our own tables: a retry
window can close between writing this and sending it, and "one tap and you're
back" sent to someone it no longer works for is worse than no mail.

Dry run by default. `--send` sends. `--only <substring>` narrows recipients.
Styling, Resend and SQL plumbing come from waitlist-launch-mail.py.
"""

import base64
import html
import importlib.util
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "trial-consent-2026-09"

# The four lapsed trials, by Apple original transaction id. Emails are resolved
# from the database at run time rather than pasted here.
ORIGINAL_TX = [
    "530003098792306",
    "380002564362134",
    "270003114617995",
    "310003179058251",
]

SUBJECT = {
    "resume":  "확인 한 번이면 그대로 이어집니다",
    "restart": "언제든 다시 이어가실 수 있습니다",
}

# The one paragraph that differs. Everything around it is shared, so the two
# mails cannot drift apart in tone.
MIDDLE = {
    # A LINK, not a path. "설정 → 맨 위 이름" is the Apple Account row at the top
    # of Settings, which nobody reads as an instruction; this URL opens the
    # subscriptions screen directly on the phone. The path stays as a fallback.
    # The button is not named — Apple's consent prompt wording is theirs, and a
    # label we invent is a thing they will look for and not find.
    "resume": [
        "아직 되돌릴 수 있습니다. 아이폰에서 아래 주소를 누르시면 구독 화면이 바로 열립니다.",
        "https://apps.apple.com/account/subscriptions",
        "거기서 nawana를 고르시고 안내에 따라 한 번만 확인해 주시면, 새로 결제하실 필요 없이 그대로 "
        "이어집니다. (직접 찾으시려면 설정 앱을 열고 맨 위에 있는 본인 이름(Apple 계정) → 구독 입니다.)",
    ],
    "restart": [
        "다시 시작하고 싶으시면 앱에서 구독을 한 번 눌러 주시면 됩니다. 물론 지금은 아니어도 괜찮습니다. "
        "그동안 만드신 목소리와 공부한 내용은 그대로 남아 있고, 언제 돌아오셔도 이어서 하실 수 있습니다.",
    ],
}

# The thank-you has to match what they actually did. 2,000 s over five days and
# one second on one day are both in this list, and one sentence cannot be true
# of both — `spokeALot` is read from `user_daily_usage`, never assumed.
OPENING_WARM = "지난 일주일 동안 나와나를 이용해 주셔서 고맙습니다. 어떠셨는지 너무 궁금해요!"
OPENING_PLAIN = "나와나를 써 보기로 해 주셔서 고맙습니다."

OPENING = [
    "안녕하세요, 나와나(nawana)입니다.",
    None,  # filled per person
    # No claim about Apple's policy in Korea — only about what happened to this
    # person. The pattern is measured, the rule behind it is not ours to state.
    "그런데 체험이 끝나면서 구독이 이어지지 않았습니다. 결제 수단에는 아무 문제가 없었습니다. "
    "무료 체험이 끝나고 첫 결제로 넘어갈 때 애플이 확인을 한 번 더 받는데, 그 안내를 놓치시면 "
    "구독이 그대로 끝나 버립니다. 저희가 미리 알려 드렸어야 했습니다. 죄송합니다.",
]

CLOSING_TOPPED_UP = (
    "그동안 대화가 끊기지 않도록 통화 시간을 미리 넣어 두었습니다. 지금 바로 이어서 말씀하실 수 있습니다.")

CLOSING = [
    "같은 일이 다시 생기지 않도록 고치고 있습니다.",
    "불편한 점이나 바라시는 점이 있으면 이 메일에 그대로 답장해 주세요. 직접 읽고 고치겠습니다.",
]


def body(kind: str, spoke_a_lot: bool, topped_up: bool) -> list[str]:
    opening = list(OPENING)
    opening[1] = OPENING_WARM if spoke_a_lot else OPENING_PLAIN
    tail = ([CLOSING_TOPPED_UP] if topped_up else []) + CLOSING
    return opening + MIDDLE[kind] + tail


# --- what Apple says, per person ------------------------------------------

def apple_state(original_tx: str) -> dict:
    """expirationIntent / autoRenewStatus / isInBillingRetryPeriod, from Apple."""
    out = subprocess.run(
        ["bash", os.path.join(_here, "apple-subscription.sh"), original_tx, "--json"],
        capture_output=True, text=True, timeout=60)
    data = json.loads(out.stdout)
    for group in data.get("data", []):
        for t in group.get("lastTransactions", []):
            if t.get("originalTransactionId") != original_tx or not t.get("signedRenewalInfo"):
                continue
            seg = t["signedRenewalInfo"].split(".")[1]
            seg += "=" * (-len(seg) % 4)
            return json.loads(base64.urlsafe_b64decode(seg))
    return {}


def classify(renewal: dict) -> str:
    if renewal.get("autoRenewStatus") == 1 and renewal.get("isInBillingRetryPeriod"):
        return "resume"
    return "restart"


def recipients() -> list[dict]:
    ids = ",".join(L.q(t) for t in ORIGINAL_TX)
    rows = L.sql(
        "select s.apple_original_tx_id tx, u.email, coalesce(c.balance, 0) balance, "
        "  coalesce((select sum(d.talk_seconds) from user_daily_usage d "
        "            where d.user_id = s.user_id), 0) talk_seconds, "
        "  (select count(*) from usage_ledger l where l.user_id = s.user_id "
        "     and l.kind = 'grant' and l.created_at > now() - interval '7 days') recent_grants "
        "from user_subscriptions s "
        "join auth.users u on u.id = s.user_id "
        "left join user_credits c on c.user_id = s.user_id "
        f"where s.apple_original_tx_id in ({ids})")
    out = []
    for r in rows:
        if not r.get("email"):
            continue
        renewal = apple_state(r["tx"])
        talk = int(r.get("talk_seconds") or 0)
        out.append({
            "tx": r["tx"],
            "email": r["email"],
            "kind": classify(renewal),
            # Ten minutes across the trial is the line for "많이": below it the
            # thank-you is flattery, and one of these four spoke for a second.
            "spoke_a_lot": talk >= 600,
            "talk_seconds": talk,
            # Both halves are needed. A balance alone can be a signup grant
            # nobody put there for this, and a grant that has since been spent
            # promises a conversation the balance cannot hold.
            "topped_up": int(r.get("recent_grants") or 0) > 0
                         and (r.get("balance") or 0) >= 300,
            "balance": r.get("balance") or 0,
            "intent": renewal.get("expirationIntent"),
        })
    return out


# --- rendering -------------------------------------------------------------

def text_body(kind: str, spoke_a_lot: bool, topped_up: bool) -> str:
    return "\n\n".join(body(kind, spoke_a_lot, topped_up) + [L.SIGN, L.SITE_URL])


def html_body(kind: str, spoke_a_lot: bool, topped_up: bool) -> str:
    def p(s, top=14):
        return (f'<p style="font-size:16px;line-height:1.7;color:{L.INK};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')
    lines = body(kind, spoke_a_lot, topped_up)
    paras = [p(lines[0], top=0)] + [p(s) for s in lines[1:]]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{L.FONT_FACE}</style></head><body style="margin:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="52" height="52" alt="nawana"
                       style="display:block;width:52px;height:52px;border-radius:13px;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:21px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</div>
                <div style="font-size:12px;color:{L.FAINT};margin-top:3px;font-family:{L.MONO};">{html.escape(L.TAGLINE)}</div>
              </td>
            </tr>
          </table>
          {"".join(paras)}
          <p style="font-size:15px;color:{L.DIM};margin:32px 0 0;">{html.escape(L.SIGN)}</p>
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(L.FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def send(key: str, person: dict) -> str:
    to, kind = person["email"], person["kind"]
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO, "subject": SUBJECT[kind],
        "text": text_body(kind, person["spoke_a_lot"], person["topped_up"]),
        "html": html_body(kind, person["spoke_a_lot"], person["topped_up"]),
        "headers": {"List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
                    "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": CAMPAIGN}, {"name": "kind", "value": kind}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # Resend's WAF 1010s urllib's default
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    really = "--send" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]

    people = [p for p in recipients() if not only or only in p["email"] or only in p["tx"]]
    if not people:
        print("no recipients matched.")
        return

    # One preview per VARIANT, not per kind: the thank-you and the top-up line
    # differ inside a kind, and a preview that averages them shows a mail
    # nobody receives.
    seen: list[tuple] = []
    for p in people:
        key = (p["kind"], p["spoke_a_lot"], p["topped_up"])
        if key in seen:
            continue
        seen.append(key)
        group = [x for x in people if (x["kind"], x["spoke_a_lot"], x["topped_up"]) == key]
        print(f"\n=== {p['kind']} / 많이={p['spoke_a_lot']} / 충전={p['topped_up']}"
              f" — subject: {SUBJECT[p['kind']]}\n")
        print(text_body(*key))
        print("\n--- recipients")
        for x in group:
            print(f"  {x['email']:46} tx={x['tx']} intent={x['intent']} "
                  f"통화={x['talk_seconds']}s 잔액={x['balance']}")

    if not really:
        print("\ndry run. add --send to send.")
        return
    key = L.resend_key()
    for p in people:
        print(f"sent {p['email']} ({p['kind']}): {send(key, p)}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

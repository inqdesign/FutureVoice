#!/usr/bin/env python3
"""Launch mail: nawana is on the App Store, and here are your half-price codes.

Run from the repo root:

  python3 scripts/waitlist-launch-mail.py --light L.csv --plus P.csv --dry-run       # who gets what
  python3 scripts/waitlist-launch-mail.py --preview out.html                          # render (beta variant)
  python3 scripts/waitlist-launch-mail.py --light L.csv --plus P.csv --test me@x.com  # one real send, no DB
  python3 scripts/waitlist-launch-mail.py --light L.csv --plus P.csv --limit 3        # a few at a time
  python3 scripts/waitlist-launch-mail.py --light L.csv --plus P.csv                  # everyone pending
  python3 scripts/waitlist-launch-mail.py --light L.csv --plus P.csv --only beta      # one group only

Who: two groups, one mail.
  * beta   — the hand-comped beta testers (`user_subscriptions.source = 'comp'`,
             Light). Their plan ends 2026-09-21; the mail says so. Mailed at the
             waitlist address they signed up with, else their sign-in email —
             unless that is an Apple private relay, which Resend cannot reach:
             those get codes RESERVED and printed for hand-over in the beta chat.
  * waitlist — every `public.waitlist` row with `notified_at IS NULL`, minus the
             beta testers above.

What: each person gets TWO App Store one-time offer codes — one for Light
monthly, one for Plus monthly (an offer is per product, and a Light code can't
buy Plus). Codes come from the two CSVs App Store Connect hands out (`--light`,
`--plus`); one is used per person per offer, in file order, skipping any code
already on file.

Record: every (code → person) is written to `offer_code_grants` BEFORE the
send, and `sent_at` is stamped after Resend accepts — so a re-run reuses the
same codes for anyone whose mail failed, never deals a person a second code,
and never mails anyone twice. `waitlist.notified_at` is stamped as before.
Nothing here needs the offer-code-mail edge function; this script is the
whole path.

How: Resend REST API, from hello@nawana.app. Key from RESEND_API_KEY or the
keychain (`security add-generic-password -s "Resend nawana" -a resend -w`).
Supabase Management API token from the keychain (`supabase login`).

Copy is bilingual — Korean first, formal (합니다체: this is a letter from the
founder, not app chrome), then English.
"""

import argparse
import base64
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
FROM = "nawana <hello@nawana.app>"
REPLY_TO = "hello@nawana.app"
APP_STORE_ID = "6792794655"
APP_STORE_URL = f"https://apps.apple.com/app/id{APP_STORE_ID}"
SITE_URL = "https://nawana.app"
CAMPAIGN = "launch-2026-09"
SUBJECT = "나와나가 App Store에 출시되었습니다 · nawana is on the App Store"
PER_SEND_PAUSE = 0.6  # Resend allows 2 req/s

LIGHT_OFFER = "Beta50 Light Monthly v2"   # ASC offer reference names, verbatim
PLUS_OFFER = "Beta50 Plus Monthly v2"
CODE_VALID_UNTIL_KO = "2026년 12월 31일"
CODE_VALID_UNTIL_EN = "December 31, 2026"
RELAY = "@privaterelay.appleid.com"
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@.][^\s@]*\.[^\s@]+$")


def redeem(code: str) -> str:
    return f"https://apps.apple.com/redeem?ctx=offercodes&id={APP_STORE_ID}&code={code}"


# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

KO_OPEN = [
    "안녕하세요, 나와나(nawana)입니다.",
    "우선, 기다려 주셔서 정말 고맙습니다. 그리고 드디어, 나와나가 App Store에 출시되었습니다.",
    "유창한 나와 언어 학습을 한다. 제가 남긴 오디오를 들어 보신 분들은 어느 정도 감을 잡으셨겠지만, "
    "다른 사람을 흉내 내지 않고 내 목소리로 유창하게 말하는 나와 대화하고, 따라 하면서 조금씩 조금씩 "
    "그 미래의 나와 가까워지는 경험을 꼭 하시길 바라면서 앱을 만들었습니다.",
    "App Store에서 직접 만나 보시고, 혹시 좋다고 생각되시면 꼭 주위 분들께 알려 주시거나 리뷰를 남겨 주셔서 "
    "많은 사람이 나와나를 알 수 있게 도와주세요.",
    "아직 부족하지만, 정말 열심히 만들었습니다. 앞으로 더 많이 지켜봐 주세요.",
]
KO_OFFER_BETA = (
    "베타 기간 동안 함께해 주셔서 고맙습니다. 지금 사용하시는 플랜은 9월 21일에 만료됩니다. "
    "앞으로도 계속 사용하고 싶으신 분들을 위해 출시 기념으로 1년간 50% 할인 코드를 준비했습니다."
)
KO_OFFER_WAITLIST = (
    "알림과 베타 신청을 하셨지만 체험하지 못하신 분들을 위해 출시 기념으로 1년간 50% 할인 코드를 준비했습니다."
)
KO_CODES_INTRO = "두 가지 플랜 중 하나를 고르실 수 있습니다. 둘 중 하나만 사용할 수 있고, 사용하지 않은 코드는 그대로 사라집니다."
KO_LIGHT_LABEL = "Light — 월 150분 통화"
KO_PLUS_LABEL = "Plus — 통화 무제한"
KO_CTA = "App Store에서 코드 사용하기"
KO_HOWTO = (
    "사용 방법은 간단합니다. iPhone에서 위 버튼을 누르면 App Store가 열리고, 앱이 없으면 받기까지 함께 진행됩니다. "
    "첫 7일은 무료이고, 그다음 12개월 동안 월 정가의 반값으로 사용하실 수 있습니다. 12개월이 지나면 정가로 이어지며, "
    f"설정에서 언제든 해지할 수 있습니다. 코드는 한 분만 사용할 수 있고 {CODE_VALID_UNTIL_KO}까지 유효합니다."
)
KO_TAIL = "사용해 보시고 의견이 있으시면 이 메일에 답장해 주세요. 제가 직접 읽습니다."
KO_UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."

EN_OPEN = [
    "Hi, this is nawana.",
    "Thank you for waiting — nawana is on the App Store.",
    "Clone your voice once, then learn a language by talking with the fluent version of yourself, "
    "in your own voice, and getting a little closer to that future self every day.",
]
EN_OFFER_BETA = "Thank you for testing the beta. Your current plan ends on September 21. To keep going, here is a year at half price."
EN_OFFER_WAITLIST = "You asked to be told, or to test the beta, and never got to try it. Here is a year at half price to start with."
EN_CODES_INTRO = "Pick one of the two plans. Only one code can be used; the other simply expires."
EN_HOWTO = (
    "Open the button on your iPhone. The App Store opens and installs the app if you don't have it. "
    "The first 7 days are free, then 12 months at half the monthly price, then the regular price — cancel any time in Settings. "
    f"Each code works once and is valid until {CODE_VALID_UNTIL_EN}."
)
EN_TAIL = "Try it, and if you have a thought, just reply to this email. I read every one."
EN_UNSUB = "Don't want more mail from us? Reply and say so."

SIGN = "— nawana"
FOOTER = "Dear RoRo · Munich"
TAGLINE = "Learn a language from your fluent self."
# The app icon, served from the site (web/mail/, deployed with it). Mail
# clients load remote images through their own proxy; a data: URI would be
# stripped by Gmail. 256 px source, drawn at 56 px so it stays crisp on 2x.
LOGO_URL = f"{SITE_URL}/mail/nawana-icon-256.png"


def text_body(kind: str, light: str, plus: str) -> str:
    ko = list(KO_OPEN) + [
        KO_OFFER_BETA if kind == "beta" else KO_OFFER_WAITLIST,
        KO_CODES_INTRO,
        f"{KO_LIGHT_LABEL}\n코드: {light}\n{redeem(light)}",
        f"{KO_PLUS_LABEL}\n코드: {plus}\n{redeem(plus)}",
        KO_HOWTO, KO_TAIL, KO_UNSUB,
    ]
    en = list(EN_OPEN) + [
        EN_OFFER_BETA if kind == "beta" else EN_OFFER_WAITLIST,
        EN_CODES_INTRO,
        f"Light — 150 min of talk a month\nCode: {light}\n{redeem(light)}",
        f"Plus — unlimited talk\nCode: {plus}\n{redeem(plus)}",
        EN_HOWTO, EN_TAIL, EN_UNSUB,
    ]
    return "\n\n".join(ko + ["— · —"] + en + [SIGN, SITE_URL])


def html_body(kind: str, light: str, plus: str) -> str:
    def p(s, color="#3a332e", top=14, size="15.5px"):
        return (f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def code_box(label, code, cta):
        return (
            '<div style="margin:16px 0 0;padding:16px 18px;background:#f4f3ef;border:1px solid #e6e4dd;">'
            f'<div style="font-size:12px;letter-spacing:.06em;color:#8a7c6d;">{html.escape(label)}</div>'
            f'<div style="font-size:21px;font-weight:700;letter-spacing:.08em;margin-top:6px;font-family:Menlo,Consolas,monospace;">{html.escape(code)}</div>'
            f'<p style="margin:12px 0 0;"><a href="{redeem(code)}" '
            'style="display:inline-block;background:#1c1814;color:#ffffff;text-decoration:none;'
            f'font-size:14px;font-weight:600;padding:10px 16px;border-radius:8px;">{html.escape(cta)} &rarr;</a></p>'
            '</div>'
        )

    ko = [p(KO_OPEN[0], top=0)] + [p(s) for s in KO_OPEN[1:]]
    ko.append(p(KO_OFFER_BETA if kind == "beta" else KO_OFFER_WAITLIST, top=22))
    ko.append(p(KO_CODES_INTRO))
    ko.append(code_box(KO_LIGHT_LABEL, light, KO_CTA))
    ko.append(code_box(KO_PLUS_LABEL, plus, KO_CTA))
    ko.append(p(KO_HOWTO, top=18, size="14px"))
    ko.append(p(KO_TAIL, top=24))
    ko.append(p(KO_UNSUB, color="#8a7c6d", top=10, size="13px"))

    en = [p(EN_OPEN[0], top=0)] + [p(s) for s in EN_OPEN[1:]]
    en.append(p(EN_OFFER_BETA if kind == "beta" else EN_OFFER_WAITLIST, top=22))
    en.append(p(EN_CODES_INTRO))
    en.append(code_box("Light — 150 min of talk a month", light, "Redeem on the App Store"))
    en.append(code_box("Plus — unlimited talk", plus, "Redeem on the App Store"))
    en.append(p(EN_HOWTO, top=18, size="14px"))
    en.append(p(EN_TAIL, top=24))
    en.append(p(EN_UNSUB, color="#8a7c6d", top=10, size="13px"))

    divider = '<div style="margin:34px 0 30px;border-top:1px solid #ececE6;"></div>'
    return f"""<!doctype html><html><body style="margin:0;background:#f4f3ef;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f3ef;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px;background:#ffffff;border:1px solid #e6e4dd;">
        <tr><td style="padding:34px 34px 36px;font-family:Helvetica,Arial,sans-serif;color:#1c1814;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 28px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{SITE_URL}" style="text-decoration:none;">
                  <img src="{LOGO_URL}" width="56" height="56" alt="nawana"
                       style="display:block;width:56px;height:56px;border-radius:14px;border:1px solid #e6e4dd;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:22px;font-weight:700;letter-spacing:-.01em;color:#1c1814;">nawana</div>
                <div style="font-size:13px;color:#8a7c6d;margin-top:3px;">{html.escape(TAGLINE)}</div>
              </td>
            </tr>
          </table>
          <div style="font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#8a7c6d;margin:0 0 18px;">Now on the App Store</div>
          {"".join(ko)}
          {divider}
          {"".join(en)}
          <div style="margin-top:30px;padding-top:20px;border-top:1px solid #ececE6;">
            <div style="font-size:14px;color:#3a332e;">{html.escape(SIGN)}</div>
          </div>
        </td></tr>
      </table>
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:18px;font-family:Helvetica,Arial,sans-serif;">
        <tr>
          <td style="vertical-align:middle;padding-right:10px;">
            <img src="{LOGO_URL}" width="20" height="20" alt="" style="display:block;width:20px;height:20px;border-radius:5px;opacity:.85;">
          </td>
          <td style="vertical-align:middle;font-size:11px;color:#a89f92;line-height:1.6;">
            <a href="{SITE_URL}" style="color:#8a7c6d;text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{APP_STORE_URL}" style="color:#8a7c6d;text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{REPLY_TO}" style="color:#8a7c6d;text-decoration:none;">{REPLY_TO}</a>
            <br>{html.escape(FOOTER)}
          </td>
        </tr>
      </table>
    </td></tr>
  </table></body></html>"""


# --------------------------------------------------------------------------
# Plumbing.
# --------------------------------------------------------------------------

def keychain(service: str, account: str | None = None) -> str | None:
    cmd = ["security", "find-generic-password", "-s", service, "-w"]
    if account:
        cmd[3:3] = ["-a", account]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    raw = r.stdout.strip()
    if raw.startswith("go-keyring-base64:"):
        raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
    return raw or None


def supabase_token() -> str:
    tok = keychain("Supabase CLI")
    if not tok:
        sys.exit("no Supabase CLI token in the keychain — run `supabase login` first")
    return tok


_TOKEN: str | None = None


def sql(query: str) -> list[dict]:
    global _TOKEN
    _TOKEN = _TOKEN or supabase_token()
    body = json.dumps({"query": query}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/database/query",
        data=body, method="POST")
    req.add_header("Authorization", f"Bearer {_TOKEN}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # urllib's default UA is 403'd
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def q(s: str) -> str:
    """SQL string literal."""
    return "'" + s.replace("'", "''") + "'"


def resend_key() -> str:
    key = os.environ.get("RESEND_API_KEY") or keychain("Resend nawana")
    if not key:
        sys.exit("no Resend key: export RESEND_API_KEY=… or "
                 "`security add-generic-password -s \"Resend nawana\" -a resend -w`")
    return key


def send(key: str, to: str, kind: str, light: str, plus: str, idem: str) -> str:
    payload = {
        "from": FROM,
        "to": [to],
        "reply_to": REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(kind, light, plus),
        "html": html_body(kind, light, plus),
        "headers": {
            "List-Unsubscribe": f"<mailto:{REPLY_TO}?subject=unsubscribe>",
            "X-Entity-Ref-ID": idem,
        },
        "tags": [{"name": "campaign", "value": CAMPAIGN}, {"name": "kind", "value": kind}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # api.resend.com's WAF 1010s urllib's default
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


# --------------------------------------------------------------------------
# Codes and recipients.
# --------------------------------------------------------------------------

def read_codes(path: str) -> list[str]:
    out: list[str] = []
    with open(path, newline="") as f:
        for line in f:
            cell = line.split(",")[0].strip().strip('"')
            if re.fullmatch(r"[A-Z0-9]{8,24}", cell):   # ASC codes; anything else is a header
                out.append(cell)
    if not out:
        sys.exit(f"no codes found in {path}")
    return out


RECIPIENTS_SQL = f"""
with beta as (
  select s.user_id,
         coalesce(m.waitlist_email,
                  case when u.email not like '%{RELAY}' then u.email end) as email,
         u.email as auth_email
    from user_subscriptions s
    join auth.users u on u.id = s.user_id
    left join user_waitlist_mapping m on m.user_id = s.user_id
   where s.source = 'comp' and s.plan_id like 'light%'
)
select 'beta' as kind, user_id::text, email, auth_email, null::text as waitlist_id
  from beta
union all
select 'waitlist', m.user_id::text, w.email, null, w.id::text
  from waitlist w
  left join user_waitlist_mapping m on m.waitlist_email = w.email
 where w.notified_at is null
   and lower(w.email) not in (select lower(email) from beta where email is not null)
order by 1, 3
"""


class Grants:
    """What is already on file, and the pool of unused codes per offer."""

    def __init__(self, light_codes: list[str], plus_codes: list[str]):
        rows = sql("select code, offer, lower(email) as email, sent_at from offer_code_grants")
        self.used = {r["code"] for r in rows}
        self.by_person = {(r["offer"], r["email"]): r for r in rows}
        self.pool = {
            LIGHT_OFFER: [c for c in light_codes if c not in self.used],
            PLUS_OFFER: [c for c in plus_codes if c not in self.used],
        }

    def code_for(self, offer: str, email: str) -> tuple[str, bool]:
        """(code, already_sent). Reuses a filed code; else takes the next unused one."""
        prior = self.by_person.get((offer, email.lower()))
        if prior:
            return prior["code"], prior["sent_at"] is not None
        if not self.pool[offer]:
            sys.exit(f"out of {offer} codes — request a bigger batch in ASC")
        code = self.pool[offer].pop(0)
        self.used.add(code)
        return code, False

    def file(self, offer: str, code: str, kind: str, email: str, user_id: str | None, note: str | None):
        if (offer, email.lower()) in self.by_person:
            return
        sql("insert into offer_code_grants (code, offer, kind, email, user_id, note) values ("
            f"{q(code)}, {q(offer)}, {q(kind)}, {q(email)}, "
            f"{q(user_id) + '::uuid' if user_id else 'null'}, {q(note) if note else 'null'}) "
            "on conflict (code) do nothing")
        self.by_person[(offer, email.lower())] = {"code": code, "offer": offer, "email": email.lower(), "sent_at": None}

    def mark_sent(self, codes: list[str]):
        sql("update offer_code_grants set sent_at = now() where sent_at is null and code in ("
            + ",".join(q(c) for c in codes) + ")")
        for r in self.by_person.values():
            if r["code"] in codes:
                r["sent_at"] = "now"


def stamp_waitlist(row_id: str) -> None:
    sql(f"update public.waitlist set notified_at = now() where id = {q(row_id)} and notified_at is null")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--light", metavar="CSV", help="ASC one-time codes for the Light monthly offer")
    ap.add_argument("--plus", metavar="CSV", help="ASC one-time codes for the Plus monthly offer")
    ap.add_argument("--dry-run", action="store_true", help="plan only: nothing sent, nothing written")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML (beta variant, sample codes) and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL with sample codes; touches no DB row")
    ap.add_argument("--limit", type=int, help="send to at most N people")
    ap.add_argument("--only", choices=["beta", "waitlist"], help="one group only")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body("beta", "SAMPLELIGHTCODE000", "SAMPLEPLUSCODE0000"))
        print(f"wrote {args.preview}\n\n--- text variant ---\n{text_body('beta', 'SAMPLELIGHTCODE000', 'SAMPLEPLUSCODE0000')}")
        return

    if args.test:
        mid = send(resend_key(), args.test, "beta", "SAMPLELIGHTCODE000", "SAMPLEPLUSCODE0000",
                   idem=f"{CAMPAIGN}:test:{int(time.time())}")
        print(f"sent test to {args.test}: {mid}")
        return

    if not (args.light and args.plus):
        sys.exit("--light and --plus CSVs are required (see --help)")

    grants = Grants(read_codes(args.light), read_codes(args.plus))
    people = [p for p in sql(RECIPIENTS_SQL) if not args.only or p["kind"] == args.only]

    plan, skipped = [], []
    for p in people:
        email = p["email"]
        if email is None:
            # Relay-only beta tester: reserve both codes, hand over by hand.
            e = p["auth_email"]
            lc, _ = grants.code_for(LIGHT_OFFER, e)
            pc, _ = grants.code_for(PLUS_OFFER, e)
            plan.append({"kind": "beta", "email": e, "user_id": p["user_id"], "waitlist_id": None,
                         "light": lc, "plus": pc, "send": False})
            continue
        if not EMAIL_RE.match(email):
            skipped.append((email, "invalid address"))
            continue
        lc, l_sent = grants.code_for(LIGHT_OFFER, email)
        pc, p_sent = grants.code_for(PLUS_OFFER, email)
        if l_sent and p_sent:
            skipped.append((email, "already sent"))
            continue
        plan.append({"kind": p["kind"], "email": email, "user_id": p["user_id"], "waitlist_id": p["waitlist_id"],
                     "light": lc, "plus": pc, "send": True})

    if args.limit:
        plan = plan[:args.limit]

    print(f"{len(plan)} to deal" + (f" (limit {args.limit})" if args.limit else "") + f", {len(skipped)} skipped"
          + ("   DRY RUN" if args.dry_run else ""))
    for who, why in skipped:
        print(f"  skip      {who:40} {why}")
    for r in plan:
        print(f"  {'send' if r['send'] else 'reserve':9} {r['kind']:9} {r['email']:40} L={r['light']}  P={r['plus']}")
    if args.dry_run or not plan:
        return

    key = resend_key()
    ok = failed = reserved = 0
    handover = []
    for r in plan:
        note = None if r["send"] else "relay only — handed over in the beta chat"
        grants.file(LIGHT_OFFER, r["light"], r["kind"], r["email"], r["user_id"], note)
        grants.file(PLUS_OFFER, r["plus"], r["kind"], r["email"], r["user_id"], note)
        if not r["send"]:
            reserved += 1
            handover.append(r)
            continue
        try:
            mid = send(key, r["email"], r["kind"], r["light"], r["plus"],
                       idem=f"{CAMPAIGN}:{r['email'].lower()}")
        except Exception as e:  # keep going — one bad address must not stop the rest
            failed += 1
            print(f"  FAIL {r['email']}: {e}")
            continue
        grants.mark_sent([r["light"], r["plus"]])
        if r["waitlist_id"]:
            stamp_waitlist(r["waitlist_id"])
        ok += 1
        print(f"  sent {r['email']}  {mid}")
        time.sleep(PER_SEND_PAUSE)

    print(f"\n{ok} sent, {reserved} reserved, {failed} failed; re-run to retry the failures with the same codes")
    if handover:
        print("\nHand these over by hand (relay-only beta testers):")
        for r in handover:
            print(f"  {r['email']}\n    Light {r['light']}  {redeem(r['light'])}\n    Plus  {r['plus']}  {redeem(r['plus'])}")


if __name__ == "__main__":
    main()

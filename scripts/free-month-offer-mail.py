#!/usr/bin/env python3
"""A month free, for anyone who wants it (2026-10-30).

Who: signed up in the last 30 days, no subscription row (never subscribed),
not an admin account, and talked at least 10 minutes (talk_time on the
ledger), whether or not the twenty free minutes are spent. 28 matched on
2026-10-30; the DearRoRo bookkeeping test account and the 12 below are out. The list is
re-checked at send time: anyone who has subscribed since is skipped.

The letter thanks them and offers a one-month free code to whoever replies
(by mail, Threads or Instagram DM). Codes are sent by hand to the people who
answer. Everyone left reads Korean; the English copy stays for later use. Copy is the founder's
(합니다체, no em dash).

  python3 scripts/free-month-offer-mail.py --preview out.html [--lang en]
  python3 scripts/free-month-offer-mail.py            # dry run
  python3 scripts/free-month-offer-mail.py --send     # after approval
"""

import argparse
import html
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "free-month-offer-2026-10-30"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

USER_IDS = [
    "ed64e23b-0010-4ecf-aeb1-1eb2187347dd",  # 2026-10-28 · 20.0 min · ko
    "ca8ddfea-d147-4d3c-905f-58baf90d665e",  # 2026-10-28 · 19.1 min · ko
    "7eb25a5a-c5b1-4277-b327-89a68e0d8ef4",  # 2026-10-25 · 20.0 min · ko
    "829ed692-bf54-4222-bdb8-f725157742f8",  # 2026-10-21 · 13.7 min · ko
    "2c0c54de-5266-4f6c-ab8d-4842844542dd",  # 2026-10-21 · 10.3 min · ko
    "cd667cb3-c59b-403b-8af0-f55944392e73",  # 2026-10-18 · 18.8 min · ko
    "761b7a70-0509-40e7-b628-ac42a6314913",  # 2026-10-15 · 12.7 min · ko
    "8d160fea-f5a1-4cb6-acd8-46d9f06f49ab",  # 2026-10-14 · 12.5 min · ko
    "b085762e-fdb5-409d-a60b-33b3ffa633b8",  # 2026-10-08 · 19.6 min · ko
    "b6b73f58-c11e-41e6-a5c7-72564e99bd83",  # 2026-10-06 · 15.6 min · ko
    "40d201be-ca31-4147-a15c-44d7c86e9431",  # 2026-10-05 · 17.5 min · ko
    "12633542-738b-439d-b4a6-ec506b9b1b31",  # 2026-10-04 · 20.0 min · ko
    "78d54677-78d3-4746-9236-38490f462cb5",  # 2026-10-02 · 20.0 min · ko
    "6769bc53-9375-408d-85bb-1f84916fed5a",  # 2026-10-01 · 19.2 min · ko
    "48f3d742-d166-4db8-bea9-a175c3a4dbb5",  # 2026-10-01 · 19.3 min · ko
    "ace93bcc-a8d5-4f61-929d-c6340548dc1f",  # 2026-10-01 · 11.7 min · ko
]

# Left out (2026-10-30, founder): 8b6bb9c6 (rated the app 3, the call 2,
# "難しいです。") and everyone already sent a personal mail: 2ed2f038,
# 7c654ccc, fc68aaeb, f3899bc9, b74ee57b, fcf5b6b1, bce8a689, 622135cd,
# 197040e0, 85f291d7, 1e5e1cbd. Everyone left is Korean.
ENGLISH: set[str] = set()

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

COPY = {
    "ko": dict(
        subject="나와나를 한 달 동안 무료로 써 보시겠어요?",
        open=[
            "안녕하세요. 나와나를 만든 이응규입니다.",
            "나와나에서 미래의 나와 이야기를 나눠 주셔서 고맙습니다. "
            "처음부터 10분 넘게 대화를 이어가 주셔서 정말 반가웠습니다.",
            "그래서 나와나를 한 달 동안 무료로 써 보실 수 있는 코드를 드리려고 합니다. "
            "한 달 동안 매일 짧게라도 통화해 보시면, 내 말이 조금씩 달라지는 걸 직접 느끼실 수 있을 겁니다.",
        ],
        offer="관심 있으시면 이 메일에 답장으로 한 줄만 보내 주세요. 스레드나 인스타그램 DM도 괜찮습니다. "
              "확인하는 대로 코드를 보내 드리겠습니다.",
        middle=["써 보시면서 좋았던 점이나 불편했던 점이 있었다면 함께 적어 주셔도 큰 도움이 됩니다."],
        buttons=("답장하기", "스레드", "인스타그램 DM"),
        links=("답장", "스레드", "인스타그램"),
        close="고맙습니다.",
        sign="이응규 드림",
        unsub="더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요.",
    ),
    "en": dict(
        subject="A free month of nawana, if you'd like one",
        open=[
            "Hi, this is Eunggyu, the maker of nawana.",
            "Thank you for talking with your future self on nawana. "
            "You kept the conversation going for more than ten minutes from the start, and that made my day.",
            "So I'd like to give you a code for one free month of nawana. "
            "A month of short daily calls is enough to hear your own speaking change.",
        ],
        offer="If you're interested, just reply to this mail with one line. A message on Threads or Instagram works too. "
              "I'll send you the code as soon as I see it.",
        middle=["If anything felt great or got in your way while using it, I'd love to hear that too."],
        buttons=("Reply", "Threads", "Instagram DM"),
        links=("Reply", "Threads", "Instagram"),
        close="Thank you.",
        sign="Eunggyu",
        unsub="If you'd rather not get mail from me, just reply and let me know.",
    ),
}


def text_body(lang: str) -> str:
    c = COPY[lang]
    r, t, i = c["links"]
    parts = list(c["open"])
    parts.append(f"{c['offer']}\n\n{r}: {L.REPLY_TO}\n{t}: {THREADS_URL}\n{i}: {INSTAGRAM_URL}")
    parts += c["middle"]
    parts += [c["close"], c["sign"], L.APP_STORE_URL, c["unsub"]]
    return "\n\n".join(parts)


def html_body(lang: str) -> str:
    c = COPY[lang]
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(c["open"][0], top=0) + "".join(p(s) for s in c["open"][1:])
        + p(c["offer"], top=20)
        + '<div style="margin:16px 0 0;">'
        + button(c["buttons"][0], f"mailto:{L.REPLY_TO}", True)
        + button(c["buttons"][1], THREADS_URL, False)
        + button(c["buttons"][2], INSTAGRAM_URL, False)
        + '</div>'
        + "".join(p(s, top=(14 if i == 0 else 10)) for i, s in enumerate(c["middle"]))
        + p(c["close"], top=22)
        + p(c["sign"], color=L.DIM, top=6)
    )

    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@media only screen and (max-width:480px) {{
  .wrap {{ padding:22px 4px 28px !important; }}
}}
</style></head><body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" class="wrap" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;word-break:keep-all;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;">
            <tr>
              <td style="vertical-align:middle;padding-right:10px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                       style="display:block;width:36px;height:36px;border-radius:9px;">
                </a>
              </td>
              <td style="vertical-align:middle;font-size:17px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</td>
            </tr>
          </table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(c["unsub"])}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def recipients() -> list[dict]:
    ids = ",".join(f"'{u}'" for u in USER_IDS)
    return L.sql(f"""
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email,
             s.status
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
       where u.id in ({ids}) and u.deleted_at is null
       order by u.created_at""")


def send(key: str, to: str, idem: str, lang: str) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": COPY[lang]["subject"],
        "text": text_body(lang),
        "html": html_body(lang),
        "headers": {
            "List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
            "X-Entity-Ref-ID": idem,
        },
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL")
    ap.add_argument("--lang", choices=sorted(COPY), default="ko", help="copy for --preview / --test")
    ap.add_argument("--send", action="store_true", help="send to the list (after the copy is approved)")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body(args.lang))
        print(f"wrote {args.preview}\n\n--- subject ---\n{COPY[args.lang]['subject']}\n\n--- text ---\n{text_body(args.lang)}")
        return

    if args.test:
        print("sent test:", send(L.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}", args.lang))
        return

    plan = []
    for r in recipients():
        if r["status"] in ("active", "trialing"):
            print(f"  skip  {r['user_id'][:8]}  subscribed ({r['status']})")
        elif not r["email"] or not L.EMAIL_RE.match(r["email"]):
            print(f"  skip  {r['user_id'][:8]}  no address")
        else:
            plan.append(r)
    for r in plan:
        r["lang"] = "en" if r["user_id"][:8] in ENGLISH else "ko"
        print(f"  send  {r['user_id'][:8]}  {r['lang']}  {r['email']}")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, f'{CAMPAIGN}:{email.lower()}', r['lang'])}")
        except Exception as e:
            print(f"  FAIL  {r['email']}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""A letter to early learners who have not come back since (2026-10-01).

Who: four accounts the founder picked by hand, all from the launch week
(joined 09-14 to 09-16), plans long expired, last opened 09-27 to 09-30.
Two kinds, decided by what is left on the account WHEN THIS RUNS:
  * free minutes left → "it has got much better, you still have N minutes,
    come and try it again";
  * nothing left (07ad19f0) → the same offer the 2026-10-01 letter made:
    say so, and twenty more minutes are opened by hand.
4e4d6bf5 has no email address at all (no sign-in email, no waitlist row) and
is skipped by the address check. Relay addresses go out like the welcome mail
did on 09-29.

Copy is the founder's (합니다체, no em dash). Nothing is granted here.

  python3 scripts/early-learners-letter-mail.py --preview out   # out-<kind>.html
  python3 scripts/early-learners-letter-mail.py                 # dry run
  python3 scripts/early-learners-letter-mail.py --send          # after approval
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

CAMPAIGN = "early-learners-letter-2026-10-01"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

USER_IDS = [
    "a680574d-b3c8-4fd7-9633-6a5e4dcf2723",
    "2ba4ed7d-9f92-4289-8970-0684aa362b71",
    "4e4d6bf5-be9a-45cf-ac08-feb8b3ca5ade",
    "07ad19f0-6383-4242-b03a-4bfe993409c3",
]

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

def subject(minutes: int) -> str:
    return "나와나가 그때보다 많이 좋아졌습니다" if minutes > 0 else "통화 시간 20분을 더 열어 드리겠습니다"


def paragraphs(minutes: int) -> list[str]:
    first = ["안녕하세요. 나와나를 만든 이응규입니다.",
             "처음부터 나와나와 함께해 주셔서 고맙습니다."]
    if minutes > 0:
        return first + [
            "처음 써 보셨을 때보다 많이 좋아졌을 겁니다. "
            f"아직 무료 통화 시간이 {minutes}분 남아 있으니, 한번 다시 사용해 보세요.",
        ]
    return first + [
        "지금은 무료 통화 시간을 모두 쓰셔서 통화를 하실 수 없는 상태입니다.",
        "처음 써 보셨을 때보다 많이 좋아졌을 겁니다. 아직 관심이 있으시고 조금 더 써 보고 "
        "싶으시다면, 제가 통화 시간 20분을 더 열어 드리겠습니다. 이 메일에 답장하시거나, "
        "스레드 또는 인스타그램 DM 중 편하신 방법으로 연락 주세요.",
    ]


TAIL = ("물론 아직 완벽하지는 않습니다. 매일 개선하고 있으니 조금만 너그럽게 봐 주시면 "
        "감사하겠습니다. 써 보시고 불편한 점이나 바라는 점이 있으면 언제든 편하게 알려 주세요.")
CLOSE = "고맙습니다."
SIGN = "이응규 드림"
UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body(minutes: int) -> str:
    parts = paragraphs(minutes)
    link = L.APP_STORE_URL if minutes > 0 else f"답장: {L.REPLY_TO}"
    parts.append(f"{link}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}")
    parts += [TAIL, CLOSE, SIGN, UNSUB]
    return "\n\n".join(parts)


def html_body(minutes: int) -> str:
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def _unused_feature_rows():
        rows = []
        for i, (title, desc) in enumerate(FEATURES):
            border = "" if i == 0 else f"border-top:1px solid {L.SURF};"
            rows.append(
                f'<tr><td style="padding:12px 0;{border}">'
                f'<div style="font-size:15px;font-weight:700;color:{L.INK};line-height:1.4;">{html.escape(title)}</div>'
                f'<div style="font-size:15px;color:{L.DIM};line-height:1.55;margin-top:2px;">{html.escape(desc)}</div>'
                '</td></tr>')
        return (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
                f'style="margin:20px 0 0;border-top:1px solid {L.SURF};border-bottom:1px solid {L.SURF};">'
                + "".join(rows) + '</table>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        "".join(p(s, top=(0 if i == 0 else 16)) for i, s in enumerate(paragraphs(minutes)))
        + '<div style="margin:16px 0 0;">'
        + (button("다시 써 보기", L.APP_STORE_URL, True) if minutes > 0 else
           button("답장하기", f"mailto:{L.REPLY_TO}", True))
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(TAIL, top=22)
        + p(CLOSE, top=22)
        + p(SIGN, color=L.DIM, top=6)
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
            <br>{html.escape(UNSUB)}
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
             s.status,
             floor(coalesce(c.balance, 0) / 60)::int as minutes
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
        left join user_credits c on c.user_id = u.id
       where u.id in ({ids}) and u.deleted_at is null
       order by u.created_at""")


def send(key: str, to: str, idem: str, minutes: int) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": subject(minutes),
        "text": text_body(minutes),
        "html": html_body(minutes),
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
    ap.add_argument("--preview", metavar="PREFIX", help="write both HTML variants and exit")
    ap.add_argument("--send", action="store_true", help="send (after the copy is approved)")
    args = ap.parse_args()

    if args.preview:
        for kind, m in (("minutes", 14), ("none", 0)):
            with open(f"{args.preview}-{kind}.html", "w") as f:
                f.write(html_body(m))
            print(f"=== {kind} ===\n--- subject ---\n{subject(m)}\n\n--- text ---\n{text_body(m)}\n")
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
        kind = f"{r['minutes']} min left" if r["minutes"] > 0 else "nothing left → 20 min offer"
        print(f"  send  {r['user_id'][:8]}  {r['email']}  ({kind})")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, f'{CAMPAIGN}:{email.lower()}', r['minutes'])}")
        except Exception as e:
            print(f"  FAIL  {email}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

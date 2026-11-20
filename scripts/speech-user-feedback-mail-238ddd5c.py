#!/usr/bin/env python3
"""Thanking a learner who mostly uses Speech, and asking why the rest isn't used (2026-11-13).

Who: 238ddd5c ("June" on the boards), signed up 2026-10-22, no subscription.
Active on 15 days through 2026-11-12. Nine speech challenges, read again and
again (16 tries on one), ~240 pronunciation reads. Talk: about 11 minutes of
the free twenty over a few calls, the last on 11-05; one Watch scene on 10-24.

Copy is the founder's (합니다체, no em dash).

  python3 scripts/speech-user-feedback-mail-238ddd5c.py --preview out.html
  python3 scripts/speech-user-feedback-mail-238ddd5c.py            # dry run
  python3 scripts/speech-user-feedback-mail-238ddd5c.py --send     # after approval
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

CAMPAIGN = "speech-user-feedback-238ddd5c-2026-11-13"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

USER_IDS = ["238ddd5c-13e9-47e3-b8a8-528bc61ef459"]

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "나와나를 잘 써 주셔서 고맙습니다"

OPEN = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "스피치 챌린지를 자주 써 주셔서 고맙습니다. 채점 방식을 조금 더 바꾸고 있고, "
    "좀 더 큰 소식이 앞으로 있답니다. 기대해 주세요!",
    "하지만 통화 기능들은 많이 사용을 안 하시는 것 같아서, 제가 어떤 면을 개선해야 하는지 "
    "배울 수 있을 것 같아 연락드렸습니다.",
]

QUESTIONS = [
    "통화 기능에 손이 덜 가셨다면, 이유가 있을까요? "
    "어렵거나, 부담스럽거나, 필요가 없거나, 무엇이든 괜찮습니다.",
    "제가 어떤 점을 고치면 나와나가 더 좋아질까요?",
]

OFFER = ("한 줄만 주셔도 충분합니다. 이 메일에 답장하시거나, 스레드나 인스타그램 DM 중 "
         "편하신 곳으로 보내 주세요. 보내 주신 이야기는 빠짐없이 읽겠습니다.")

MIDDLE: list[str] = []

CLOSE = "시간 내 주셔서 정말 고맙습니다. 좋은 하루 보내세요."
SIGN = "이응규 드림"
UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body() -> str:
    parts = list(OPEN)
    parts.append("\n\n".join(f"{i}. {q}" for i, q in enumerate(QUESTIONS, 1)))
    parts.append(f"{OFFER}\n\n답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}")
    parts += MIDDLE
    parts += [CLOSE, SIGN, L.APP_STORE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def qp(i, q):
        first, *opts = q.split("\n")
        out = p(f"{i + 1}. {first}", top=(18 if i == 0 else 12))
        for o in opts:
            out += (f'<p style="font-size:15px;line-height:1.6;color:{L.DIM};margin:4px 0 0 18px;">'
                    f'{html.escape(o)}</p>')
        return out

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
        p(OPEN[0], top=0) + "".join(p(s) for s in OPEN[1:])
        + "".join(qp(i, q) for i, q in enumerate(QUESTIONS))
        + p(OFFER, top=20)
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + "".join(p(s, top=(22 if i == 0 else 10)) for i, s in enumerate(MIDDLE))
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
             s.status
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
       where u.id in ({ids}) and u.deleted_at is null
       order by u.created_at""")


def send(key: str, to: str, idem: str) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(),
        "html": html_body(),
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
    ap.add_argument("--send", action="store_true", help="send to the list (after the copy is approved)")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"wrote {args.preview}\n\n--- subject ---\n{SUBJECT}\n\n--- text ---\n{text_body()}")
        return

    if args.test:
        print("sent test:", send(L.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}"))
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
        print(f"  send  {r['user_id'][:8]}  {r['email']}")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, f'{CAMPAIGN}:{email.lower()}')}")
        except Exception as e:
            print(f"  FAIL  {r['email']}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

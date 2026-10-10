#!/usr/bin/env python3
"""Apology to the learners whose accent was blocked (2026-10-10).

From 2026-10-08 22:16 UTC the voice-quota reserve (_shared/voice-quota.ts)
refused every accent remix while the ElevenLabs account sat under 12 voice
add/edits for the month. New English learners got a plain clone: two of them
(Hanna, Jay) tapped an accent and saw a raw 503, three on 1.1.4 never knew.
The founder picked four to write to; we remix them to American by hand after
the quota resets (2026-10-12 09:24 UTC). A = saw the error, B = didn't.

Copy is the founder's (합니다체, no em dash).

  python3 scripts/accent-apology-mail.py --preview out.html
  python3 scripts/accent-apology-mail.py            # dry run
  python3 scripts/accent-apology-mail.py --send
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

CAMPAIGN = "accent-apology-2026-10-10"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

# user id → (variant, time in their zone; remix lands by 10:00 UTC Oct 12)
RECIPIENTS = {
    "7bc59bb6-5a93-46dd-bdbf-c09fb7b56972": ("A", "10월 12일 오후 7시"),           # Hanna, Seoul
    "90637b70-9f40-4008-9e67-cb93a7a63e65": ("A", "10월 12일 오후 9시(시드니 시간)"),  # Jay, Sydney
    "e04fbe3b-b378-4bc6-998b-9462db8f738f": ("B", "10월 12일 오후 7시"),           # 윤하, Tokyo
    "b74ee57b-9c34-4f31-b798-532a9a5c4779": ("B", "10월 12일 오후 7시"),           # 수진, Seoul
}

SUBJECT = {
    "A": "억양을 고르실 때 오류가 났던 점 사과드립니다",
    "B": "목소리에 억양을 넣어 드리겠습니다",
}

OPEN = {
    "A": [
        "안녕하세요, 나와나를 만든 이응규입니다.",
        "가입하시고 목소리에 억양을 고르셨을 때 오류가 났을 겁니다. 저희 쪽 문제였고, "
        "처음 만나는 순간에 불편을 드려 정말 죄송합니다.",
    ],
    "B": [
        "안녕하세요, 나와나를 만든 이응규입니다.",
        "가입해 주셔서 감사합니다. 원래 만들어 주신 목소리에는 영어 억양이 함께 입혀져야 하는데, "
        "저희 쪽 문제로 빠진 채로 만들어졌습니다. 죄송합니다.",
    ],
}


def promise(when: str) -> str:
    return (f"{when}까지 저희가 직접 목소리에 미국 억양을 입혀 넣어 드리겠습니다. "
            "따로 하실 일은 없고, 그 뒤 첫 대화부터 억양이 들어간 목소리로 들리실 겁니다.")


OFFER = ("영국이나 호주 억양을 원하시면 이 메일에 답장하시거나, 스레드 또는 인스타그램 DM으로 "
         "알려 주세요. 그 억양으로 만들어 드리겠습니다.")

CLOSE = {
    "A": "그때까지도 지금 목소리로 바로 대화하실 수 있습니다. 다시 한번 죄송합니다.",
    "B": "그때까지도 지금 목소리로 바로 대화하실 수 있습니다.",
}
SIGN = "이응규 드림"
UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def paragraphs(variant: str, when: str) -> list[str]:
    return OPEN[variant] + [promise(when), OFFER, CLOSE[variant]]


def text_body(variant: str, when: str) -> str:
    parts = paragraphs(variant, when)
    parts.append(f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}")
    parts += [SIGN, L.APP_STORE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body(variant: str, when: str) -> str:
    def p(s, color=L.INK, top=16):
        return (f'<p style="font-size:16px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    paras = paragraphs(variant, when)
    body = (
        p(paras[0], top=0) + "".join(p(s) for s in paras[1:4])
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(paras[4], top=16)
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
    ids = ",".join(f"'{u}'" for u in RECIPIENTS)
    return L.sql(f"""
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
       where u.id in ({ids}) and u.deleted_at is null
       order by u.created_at""")


def send(key: str, to: str, variant: str, when: str, idem: str) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": SUBJECT[variant],
        "text": text_body(variant, when),
        "html": html_body(variant, when),
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
    ap.add_argument("--preview", metavar="FILE", help="write variant A's HTML and exit")
    ap.add_argument("--send", action="store_true", help="send to the list")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body("A", "10월 12일 오후 7시"))
        for v in ("A", "B"):
            print(f"\n=== {v}: {SUBJECT[v]} ===\n{text_body(v, '10월 12일 오후 7시')}")
        return

    plan = []
    for r in recipients():
        if not r["email"] or not L.EMAIL_RE.match(r["email"]):
            print(f"  skip  {r['user_id'][:8]}  no address")
            continue
        variant, when = RECIPIENTS[r["user_id"]]
        plan.append((r, variant, when))
        print(f"  send  {r['user_id'][:8]}  {variant}  {when}  {r['email']}")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r, variant, when in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, variant, when, f'{CAMPAIGN}:{email.lower()}')}")
        except Exception as e:
            print(f"  FAIL  {email}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

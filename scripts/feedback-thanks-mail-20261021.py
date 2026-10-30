#!/usr/bin/env python3
"""Thanking two learners for their 5-star feedback, and asking for more (2026-10-21).

Who (both app language ko, free accounts, rated app 5 and call 5 in the
returning_talk feedback sheet with no written comment, build 108):
  f3899bc9  zbt7y6hj5r@privaterelay.appleid.com  English, joined 10-16, ~19 min talk
  98d23968  2hp59rgc6t@privaterelay.appleid.com  German,  joined 10-01, ~7 min talk

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/feedback-thanks-mail-20261021.py --preview out.html
  python3 scripts/feedback-thanks-mail-20261021.py            # dry run
  python3 scripts/feedback-thanks-mail-20261021.py --send     # after approval
"""

import argparse
import html
import importlib.util
import json
import os
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "feedback-thanks-2026-10-21"
RECIPIENTS = [
    ("zbt7y6hj5r@privaterelay.appleid.com", "영어"),
    ("2hp59rgc6t@privaterelay.appleid.com", "독일어"),
]
TO = RECIPIENTS[0][0]
LANG = RECIPIENTS[0][1]

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "나와나를 사용해 주셔서 고맙습니다"

PARAS_TEMPLATE = [
    "안녕하세요, nawana 만드는 이응규입니다.",
    "nawana를 써 주시고, 좋은 피드백까지 주셔서 정말 고맙습니다.",
    "어떻게 하면 더 좋은 앱을 만들 수 있을지, 그리고 처음 써 보시는 분들은 "
    "어떻게 느끼시는지 궁금해서 이렇게 메일을 드립니다.",
    "써 보시니까 어떠세요? "
    "불편했던 점이나, 이런 게 있으면 좋겠다 싶은 아이디어가 있으면 꼭 듣고 싶습니다. "
    "사소한 거라도 편하게 알려 주세요.",
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 좋습니다.",
    "다시 한번 고맙습니다!",
]
PARAS = [s.format(lang=LANG) for s in PARAS_TEMPLATE]
SIGN = "이응규"
UNSUB = "메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body() -> str:
    return "\n\n".join(PARAS[:-1] + [
        f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}",
        PARAS[-1], SIGN, UNSUB])


def html_body() -> str:
    def p(s, color=L.INK, top=16):
        return (f'<p style="font-size:16px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:-1])
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(PARAS[-1], top=18) + p(SIGN, color=L.DIM, top=6)
    )
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;"><tr>
            <td style="vertical-align:middle;padding-right:10px;"><a href="{L.SITE_URL}">
              <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                   style="display:block;width:36px;height:36px;border-radius:9px;"></a></td>
            <td style="vertical-align:middle;font-size:17px;font-weight:700;color:{L.INK};">nawana</td>
          </tr></table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a> &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a> &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a> &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
        "headers": {"List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
                    "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    global TO, LANG, PARAS
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    key = L.resend_key() if args.send else None
    for to, lang in RECIPIENTS:
        TO, LANG = to, lang
        PARAS = [s.format(lang=lang) for s in PARAS_TEMPLATE]
        if args.preview and to == RECIPIENTS[0][0]:
            open(args.preview, "w").write(html_body())
        print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\n")
        print(text_body())
        print("\n" + "-" * 40)
        if args.send:
            print("sent", send(key))
    if not args.send:
        print("DRY RUN")


if __name__ == "__main__":
    main()

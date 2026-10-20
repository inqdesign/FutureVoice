#!/usr/bin/env python3
"""Thanking a subscriber for staying on, and asking how it's going (2026-10-20).

Who: 00c6a881 (setia1115@gmail.com, app language ko, learning English).
Light monthly since 2026-09-13 on the Beta50 code, renewed for a second paid
month on 10-19. Talked on 24 days (~122 min), daily call and coach mode on,
shadows often. #1 on all three English speech
challenge boards (100 / 98 / 96). Never in touch with the founder before.

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/thanks-subscriber-mail-00c6a881.py --preview out.html
  python3 scripts/thanks-subscriber-mail-00c6a881.py            # dry run
  python3 scripts/thanks-subscriber-mail-00c6a881.py --send     # after approval
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

CAMPAIGN = "thanks-subscriber-00c6a881-2026-10-20"
TO = "setia1115@gmail.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "늘 써 주셔서 고맙습니다"

PARAS = [
    "안녕하세요, nawana 만드는 응규입니다.",
    "베타 테스트 때부터 nawana를 써 주셨는데, 아직 제대로 인사를 못 드린 것 같아 메일 드립니다. "
    "구독 이어 주셔서 정말 고맙습니다. 앱이 한참 삐걱대던 때부터 꾸준히 와 주셔서, "
    "혼자 만드는 입장에서 그게 얼마나 힘이 되는지 모릅니다.",
    "업데이트도 많고, 앱이 자주 바뀌어서 혼란스럽진 않은지 모르겠어요! "
    "빨리 더 안정적이고 좋은 기능을 소개해 드리고 싶은 마음이 커서, "
    "앞으로 속도 조절도 좀 해야 할 것 같네요!",
    "아, 그리고 스피치 챌린지요. 열 때마다 맨 위에 계셔서 깜짝 놀랍니다. "
    "저도 매일 해 보고 있는데 아무리 해도 못 따라가겠더라고요. 진짜 대단하십니다. "
    "그래도 포기 안 하고 쫓아가 볼게요!!",
    "요즘 써 보시기엔 어떠세요? 좋은 것도, 불편한 것도 다 궁금합니다. "
    "사소한 거라도 편하게 알려 주시면 바로 들여다볼게요.",
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 좋습니다.",
    "늘 고맙습니다!",
]
SIGN = "응규"
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    if args.preview:
        open(args.preview, "w").write(html_body())
    print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key()))


if __name__ == "__main__":
    main()

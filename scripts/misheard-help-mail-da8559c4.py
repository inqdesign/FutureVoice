#!/usr/bin/env python3
"""Reply to an in-app review asking for partial transcript fixes (2026-11-05).

Who: da8559c4 (825211@naver.com, English A1, month-free Light code QPMGS8QT).
In-app feedback 11-05 06:41 KST, app 4 / call 4: wants to fix a misheard word
like the iPhone autocorrect. No such feature; the answer: talk as to a person, redo with ↺ before Send (he has
Answer with Send on in every call), and mark Misheard afterwards from the
sentence card's top-right menu or the book's Grammar review (swipe left).

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/misheard-help-mail-da8559c4.py --preview out.html
  python3 scripts/misheard-help-mail-da8559c4.py            # dry run
  python3 scripts/misheard-help-mail-da8559c4.py --send     # after approval
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

CAMPAIGN = "misheard-help-da8559c4-2026-11-05"
TO = "825211@naver.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "남겨 주신 의견 잘 읽었습니다"

PARAS = [
    "안녕하세요, nawana 만드는 이응규입니다.",
    "앱에 남겨 주신 의견 잘 읽었습니다. 발음을 잘못 알아들었을 때 아이폰 자동수정처럼 "
    "그 부분만 고칠 수 있으면 좋겠다고 하셨지요. 시간 내서 적어 주셔서 고맙습니다.",
    "통화하실 때는 실제로 사람과 이야기하는 것처럼 하시면 됩니다. "
    "말이 헛나오거나 상대가 못 알아들어도, 다시 천천히 말하면 되는 것처럼요. "
    "화면에 어떻게 적히는지는 너무 신경 쓰지 않으셔도 괜찮습니다.",
    "말씀하신 뒤 받아 적힌 문장이 이상하다 싶으면, 보내기 버튼을 누르기 전에 "
    "그 오른쪽에 있는 다시 말하기 버튼(↺)을 눌러 주세요. 적힌 말이 지워지고 다시 말씀하실 수 있습니다. "
    "보내기를 누르실 때까지 기다리니, 천천히 다시 말씀하신 다음 보내기를 누르시면 됩니다.",
    "이미 보낸 문장이 잘못 적혔다면, 나중에 채점에서 빼실 수 있습니다. "
    "빼면 그 문장은 점수에 들어가지 않고, 그 문장에서 나온 교정 카드도 복습에서 빠집니다. "
    "아래 두 곳 중 편한 곳에서 하시면 됩니다.",
]
STEPS = [
    ("문장 카드에서",
     "복습하다가 잘못 알아들은 문장이 카드로 나오면, 카드 오른쪽 위 ⋯ 버튼을 누르고 "
     "'잘못 들림'을 고르시면 됩니다."),
    ("문법 복습에서",
     "복습 탭에서 그 통화를 열고, 점수 아래 '문법'을 누르면 고친 문장 목록이 나옵니다. "
     "잘못 알아들은 문장을 왼쪽으로 밀고 '잘못 들림'을 누르시면 됩니다. "
     "문법 점수도 그에 맞게 다시 계산됩니다."),
]
CLOSING = [
    "말씀해 주신 부분 수정 기능도 어떻게 하면 좋을지 계속 고민해 보겠습니다.",
    "다른 불편한 점이나 아이디어가 있으면 언제든 알려 주세요. "
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "고맙습니다!",
]
SIGN = "이응규"
UNSUB = "메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body() -> str:
    steps = [f"{i}. {t}\n{d}" for i, (t, d) in enumerate(STEPS, 1)]
    return "\n\n".join(PARAS + steps + CLOSING[:-1] + [
        f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}",
        CLOSING[-1], SIGN, UNSUB])


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
        p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:])
        + "".join(
            f'<div style="margin:16px 0 0;padding:14px 16px;background:{L.SURF};border-radius:12px;">'
            f'<div style="font-size:15px;font-weight:700;color:{L.INK};">{i}. {html.escape(t)}</div>'
            f'<div style="font-size:15px;line-height:1.65;color:{L.INK};margin-top:4px;">{html.escape(d)}</div></div>'
            for i, (t, d) in enumerate(STEPS, 1))
        + "".join(p(s) for s in CLOSING[:-1])
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(CLOSING[-1], top=18) + p(SIGN, color=L.DIM, top=6)
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

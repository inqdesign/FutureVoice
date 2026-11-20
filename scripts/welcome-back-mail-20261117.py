#!/usr/bin/env python3
"""How was it, coming back after a while? (2026-11-17)

Who: 9429d812, joined 10-01 (Irvine, iPhone 15, app language ko), last used
10-07, came back 11-17 on 1.3.5 and made 15 short calls in 20 minutes.

Copy is the founder's own (no em dash).

  python3 scripts/welcome-back-mail-20261117.py            # dry run
  python3 scripts/welcome-back-mail-20261117.py --send     # after approval
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

CAMPAIGN = "welcome-back-2026-11-17"
TO = "seosmileyy@gmail.com"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "오랜만에 찾아와 주셔서 고맙습니다"

PARAS = [
    "오랜만에 찾아와 주셔서 고맙습니다!",
    "예전에 오셨을 때보다 많이 바뀌었을 텐데, 어떠셨는지 궁금합니다. 대화도 잘 됐는지도 궁금합니다.",
    "답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "앞으로 더 자주 들러주세요!",
]
SIGN = "이응규 드림"
BUTTONS = [
    ("답장하기", f"mailto:{L.REPLY_TO}", True),
    ("스레드", THREADS_URL, False),
    ("인스타그램 DM", INSTAGRAM_URL, False),
]


def text_body() -> str:
    links = f"스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}"
    return "\n\n".join(PARAS + [SIGN, links])


def html_body() -> str:
    def para(i, s):
        return (f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
                f'{html.escape(s).replace(chr(10), "<br>")}</p>')

    def button(label, url, filled):
        bg, fg, bd = ("#0A84FF", "#ffffff", "#0A84FF") if filled else ("transparent", "#111", "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    ps = "".join(para(i, s) for i, s in enumerate(PARAS + [SIGN]))
    btns = "".join(button(*b) for b in BUTTONS)
    return (f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{ps}'
            f'<p style="margin:22px 0 0;">{btns}</p></div>')


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
        "headers": {"X-Entity-Ref-ID": idem},
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
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    print(f"to       {TO}\nfrom     {L.FROM}\nreply-to {L.REPLY_TO}\nsubject  {SUBJECT}\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("sent", TO, send(L.resend_key()))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Thanks for joining, and please update from the App Store (2026-10-17).

Who: fc68aaeb (dearmyrim@gmail.com, US, app language ko, learning en). Signed
up 10-17 and talked 11 min on 1.1.2 (build 64), most likely downloaded around
9-28 and first opened today; 1.1.10 is live.

Copy is the founder's to approve (no em dash).

  python3 scripts/update-mail-fc68aaeb.py            # dry run
  python3 scripts/update-mail-fc68aaeb.py --send     # after approval
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

CAMPAIGN = "update-fc68aaeb-2026-10-17"
TO = "dearmyrim@gmail.com"
APP_STORE_URL = "https://apps.apple.com/app/id6792794655"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "nawana에 가입해 주셔서 고맙습니다. 최신 버전으로 업데이트해 주세요"

PARAS = [
    "안녕하세요. nawana를 만든 이응규입니다.",
    "먼저 nawana에 가입해 주셔서 정말 감사합니다! 아래 버튼으로 최신 버전으로 업데이트해 주세요.",
    "BUTTON",
    "버튼을 누르면 App Store의 nawana 페이지가 열립니다. 「업데이트」를 눌러 주세요.\n"
    "「열기」만 보인다면 이미 최신 버전입니다.",
    "아마 오래전에 앱을 다운로드해 두셨다가 이번에 가입해 주신 것 같습니다. "
    "지금 쓰시는 버전은 1.1.2이고, 지금은 1.1.10까지 나왔습니다 :) "
    "그사이 많은 발전이 있었으니 꼭 최신 버전으로 업데이트해 주세요!",
    "써 보시다가 궁금한 점이나 불편한 점이 있으면 이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.\n"
    "Threads: " + THREADS_URL + "\nInstagram DM: " + INSTAGRAM_URL,
    "고맙습니다.",
]
BUTTON_LABEL = "App Store에서 업데이트하기"
SIGN = "이응규 드림"


def text_body() -> str:
    return "\n\n".join([f"{BUTTON_LABEL}\n{APP_STORE_URL}" if x == "BUTTON" else x for x in PARAS] + [SIGN])


def linkify(s: str) -> str:
    for u in (APP_STORE_URL, THREADS_URL, INSTAGRAM_URL):
        s = s.replace(html.escape(u), f'<a href="{u}" style="color:#0A84FF;">{html.escape(u)}</a>')
    return s


def html_body() -> str:
    def para(i, s):
        if s == "BUTTON":
            return (f'<p style="margin:18px 0 0;"><a href="{APP_STORE_URL}" style="display:inline-block;background:#0A84FF;'
                    f'color:#fff;text-decoration:none;font-size:16px;font-weight:600;padding:14px 24px;border-radius:999px;">'
                    f'{html.escape(BUTTON_LABEL)}</a></p>')
        return (f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
        f'{linkify(html.escape(s).replace(chr(10), "<br>"))}</p>')
    ps = "".join(para(i, s) for i, s in enumerate(PARAS + [SIGN]))
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{ps}</div>'


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
    print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key()))


if __name__ == "__main__":
    main()

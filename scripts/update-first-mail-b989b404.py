#!/usr/bin/env python3
"""Please update from the App Store first (2026-10-13).

Who: b989b404 (hyewon4261@gmail.com, KR). Light subscriber, talks most days
(57 turns on 10-13), still on 1.1.6 (build 86); 1.1.8 went live 10-13 07:02 UTC.
The founder asked for a personal nudge to update before anything else.

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/update-first-mail-b989b404.py            # dry run
  python3 scripts/update-first-mail-b989b404.py --send     # after approval
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

CAMPAIGN = "update-first-b989b404-2026-10-13"
TO = "hyewon4261@gmail.com"
APP_STORE_URL = "https://apps.apple.com/app/id6792794655"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "nawana를 App Store에서 먼저 업데이트해 주세요"

PARAS = [
    "안녕하세요. nawana를 만든 이응규입니다.",
    "오늘 새 버전(1.1.8)이 App Store에 나왔습니다. 먼저 아래 버튼으로 업데이트해 주세요.",
    "BUTTON",
    "버튼을 누르면 App Store의 nawana 페이지가 열립니다. 「업데이트」를 눌러 주세요.\n"
    "「열기」만 보인다면 이미 최신 버전입니다.",
    "요즘 거의 매일 미래의 나와 통화해 주셔서 정말 고맙습니다. "
    "지금 쓰시는 앱은 아직 이전 버전(1.1.6)이라 먼저 연락드립니다.",
    "업데이트 후 앱을 열면 목소리를 새 음성 엔진으로 옮기는 안내가 나옵니다. 악센트를 고르고 한 번 누르시면 됩니다.",
    "써 보시다가 궁금한 점이나 불편한 점이 있으면 이 메일에 답장하시거나, 스레드나 인스타그램 DM으로 편하게 알려 주세요.\n"
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

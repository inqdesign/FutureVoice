#!/usr/bin/env python3
"""Check-in to a learner who came back with no time left (2026-11-03).

Who: f3899bc9 (Apple relay). Signed up 2026-10-16, learning English, spent
the 20 free minutes over 10-16..10-20, came back 2026-11-03 (1.2.8), opened
the plans, tapped Plus with the 3-day trial and closed Apple's sheet.

  python3 scripts/comeback-hesitating-mail-f3899bc9.py            # dry run
  python3 scripts/comeback-hesitating-mail-f3899bc9.py --send
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

CAMPAIGN = "comeback-hesitating-f3899bc9-2026-11-03"
TO = "zbt7y6hj5r@privaterelay.appleid.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "나와나 써 보시니 어떠셨나요?"

PARAS = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "나와나를 써 주셔서 고맙습니다. 써 보시니 어떠셨는지 궁금해서 이렇게 연락드립니다.",
    "지금은 3일 동안 무료로 먼저 체험해 보실 수 있습니다. 체험 중에 해지하시면 결제되지 않고, "
    "해지는 설정 → 이름 → 구독에서 하실 수 있습니다.",
    "혹시 망설여지는 부분이 있으시다면 어떤 점인지 꼭 듣고 싶습니다. "
    "가격이든, 써 보시면서 아쉬웠던 점이든 무엇이든 괜찮습니다.",
    "테스트해 보실 시간이 더 필요하시면 편하게 말씀해 주세요. 시간을 더 넣어 드리겠습니다. "
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "고맙습니다!",
]
SIGN = "나와나 이응규 드림"


def text_body() -> str:
    links = f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}"
    return "\n\n".join(PARAS[:5] + [links] + PARAS[5:] + [SIGN])


def html_body() -> str:
    def p(s, top=16, color="#111"):
        return (f'<p style="font-size:16px;line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", "#111", "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:5])
            + '<div style="margin:16px 0 0;">'
            + button("답장하기", f"mailto:{L.REPLY_TO}", True)
            + button("스레드", THREADS_URL, False)
            + button("인스타그램 DM", INSTAGRAM_URL, False)
            + '</div>'
            + "".join(p(s) for s in PARAS[5:])
            + p(SIGN, top=10, color="#666"))
    footer = (f'<div style="margin-top:32px;padding-top:14px;border-top:1px solid #eee;'
              f'font-size:12px;line-height:1.7;color:#999;">'
              f'<a href="{L.SITE_URL}" style="color:#999;text-decoration:none;">nawana.app</a>'
              f' &nbsp;·&nbsp; <a href="{THREADS_URL}" style="color:#999;text-decoration:none;">Threads</a>'
              f' &nbsp;·&nbsp; <a href="{INSTAGRAM_URL}" style="color:#999;text-decoration:none;">Instagram</a>'
              f' &nbsp;·&nbsp; <a href="mailto:{L.REPLY_TO}" style="color:#999;text-decoration:none;">{L.REPLY_TO}</a>'
              f'</div>')
    return (f'<div style="font-family:-apple-system,sans-serif;max-width:560px;word-break:keep-all;">'
            f'{body}{footer}</div>')


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

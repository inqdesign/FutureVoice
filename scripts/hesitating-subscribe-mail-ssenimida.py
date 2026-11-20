#!/usr/bin/env python3
"""Tell a learner who keeps opening the purchase and backing out that the web is 10% cheaper (2026-11-17).

Who: ssenimida@gmail.com. Founder saw them tap Subscribe and cancel Apple's
sheet repeatedly. Account state not looked up (DB read was not allowed).

  python3 scripts/hesitating-subscribe-mail-ssenimida.py            # dry run
  python3 scripts/hesitating-subscribe-mail-ssenimida.py --send
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

CAMPAIGN = "hesitating-subscribe-ssenimida-2026-11-17"
TO = "ssenimida@gmail.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "나와나는 웹에서 구독하시면 10% 저렴합니다"

PARAS = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "나와나를 써 주셔서 고맙습니다. 구독을 고민하고 계신 것 같아 한 가지 알려 드리려고 연락드립니다.",
    "나와나는 웹사이트에서 구독하시면 App Store보다 10% 저렴합니다. "
    "앱에서 쓰시는 계정 그대로 로그인하시면 되고, 구독은 앱에 바로 반영됩니다. 편하시다면 그렇게 해 보세요.",
    "혹시 망설여지는 부분이 있으시다면 어떤 점인지 듣고 싶습니다. "
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "고맙습니다!",
]
WEB_URL = "https://nawana.app/ko.html#pricing"
SIGN = "나와나 이응규 드림"


def text_body() -> str:
    links = f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}"
    return "\n\n".join(PARAS[:3] + [f"웹에서 구독하기: {WEB_URL}"] + PARAS[3:4] + [links] + PARAS[4:] + [SIGN])


def html_body() -> str:
    def p(s, top=16, color="#111"):
        return (f'<p style="font-size:16px;line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", "#111", "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:3])
            + '<div style="margin:16px 0 0;">' + button("웹에서 구독하기", WEB_URL, True) + '</div>'
            + p(PARAS[3])
            + '<div style="margin:16px 0 0;">'
            + button("답장하기", f"mailto:{L.REPLY_TO}", False)
            + button("스레드", THREADS_URL, False)
            + button("인스타그램 DM", INSTAGRAM_URL, False)
            + '</div>'
            + "".join(p(s) for s in PARAS[4:])
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

#!/usr/bin/env python3
"""Thank-you and feedback ask to a Plus subscriber who turned renewal off (2026-10-25).

Who: b989b404 (hyewon4261@gmail.com). Plus monthly, cancel_at_period_end,
runs until 2026-11-02. Talked a lot early on and asked for a longer plan.
Copy is the founder's own (합니다체, no em dash); only spelling and spacing
were touched, plus the Threads/Instagram line every learner mail carries.

  python3 scripts/cancelled-plus-mail-b989b404.py            # dry run
  python3 scripts/cancelled-plus-mail-b989b404.py --send
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

CAMPAIGN = "cancelled-plus-b989b404-2026-10-25"
TO = "hyewon4261@gmail.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "한 달 동안 함께해 주셔서 고맙습니다"

PARAS = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "열심히 한 달 동안 써 주셔서 고맙습니다. 아쉽게도 계속 함께하시지 못하게 됐지만, "
    "제가 귀담아들을 것이 있을 것 같아서 이렇게 연락을 드렸습니다.",
    "초반엔 정말 오랜 시간 쓰셔서, 더 긴 구독도 만들어 달라고 하셔서 제가 준비를 했었는데, "
    "어떤 부분에서 가장 불편하셨는지, 제가 더 좋은 서비스를 할 수 있도록 "
    "혹시 해 주실 말씀이 있으시다면 꼭 듣고 싶습니다.",
    "바쁘시겠지만, 시간 괜찮으실 때 피드백을 부탁드려도 될까요? "
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "다시 한번, 한 달 동안 덕분에 지금까지 올 수 있는 힘을 얻었습니다. "
    "나와나의 처음을 함께해 주셔서 정말 감사드립니다. "
    "언제든 꼭 다시 돌아와서 함께 영어 공부했으면 좋겠습니다!",
    "고맙습니다! 또 뵐게요!",
]
SIGN = "나와나 이응규 드림"


def text_body() -> str:
    links = f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}"
    return "\n\n".join(PARAS[:4] + [links] + PARAS[4:] + [SIGN])


def html_body() -> str:
    def p(s, top=16, color="#111"):
        return (f'<p style="font-size:16px;line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", "#111", "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:4])
            + '<div style="margin:16px 0 0;">'
            + button("답장하기", f"mailto:{L.REPLY_TO}", True)
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

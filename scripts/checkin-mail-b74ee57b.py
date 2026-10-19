#!/usr/bin/env python3
"""How was it, and is the free time what's holding you back (2026-10-12).

Who: b74ee57b (Apple relay vfcd2h5jsz@privaterelay.appleid.com, KR / Daegu,
app language ko). Signed up 10-09, talked in German (10 min) and English
(4 + 6 min), first call felt "just right" at A1, slow voice. The 20 free
minutes are spent (14 s left), no subscription, saw the plans after the
10-12 call and closed them.

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/checkin-mail-b74ee57b.py            # dry run
  python3 scripts/checkin-mail-b74ee57b.py --send     # after approval
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

CAMPAIGN = "checkin-b74ee57b-2026-10-12"
TO = "vfcd2h5jsz@privaterelay.appleid.com"

SUBJECT = "nawana, 써 보시니 어떠셨나요?"

PARAS = [
    "안녕하세요. nawana를 만든 이응규입니다.",
    "독일어와 영어로 미래의 나와 통화해 주셔서 고맙습니다.\n"
    "써 보시니 어떠셨는지 궁금해서 연락드립니다.",
    "좋았던 점도, 어색하거나 불편했던 점도 편하게 들려주세요.\n"
    "한 줄이라도 정말 큰 도움이 됩니다.",
    "그리고 처음에 드린 무료 통화 시간을 거의 다 쓰셨더라고요.\n"
    "혹시 통화 시간이 조금 부족하게 느껴져서, 계속할지 고민하고 계신 건 아닌지 궁금합니다.\n"
    "어떤 점이 망설여지시는지 알려 주시면 더 나은 방법을 찾아보겠습니다.",
    "읽어 주셔서 고맙습니다.",
]
SIGN = "이응규 드림"


def text_body() -> str:
    return "\n\n".join(PARAS + [SIGN])


def html_body() -> str:
    ps = "".join(
        f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
        f'{html.escape(s).replace(chr(10), "<br>")}</p>'
        for i, s in enumerate(PARAS + [SIGN]))
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

#!/usr/bin/env python3
"""Good to see you again, and what should I improve? (2026-11-08)

Who: 2ba4ed7d (msoul0404@gmail.com), joined 09-14 in the launch week, Plus
annual trial cancelled and ended 09-21, came back 11-08 for a minute.

Copy is the founder's own, spelling and spacing fixed only (no em dash).

  python3 scripts/welcome-back-mail-20261108.py            # dry run
  python3 scripts/welcome-back-mail-20261108.py --send     # after approval
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

CAMPAIGN = "welcome-back-2026-11-08"
TO = "msoul0404@gmail.com"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "오랜만에 나와나에 와주셔서 반가웠습니다"

PARAS = [
    "오랜만에 나와나에 와주셔서 너무 반가웠습니다.\n"
    "그동안 많은 것들이 달라졌고, 예전에도 기능이 많아서 잘 쓰고 있는지 생각하셨었는데, "
    "어쩌죠, 기능이 더 많아져 버렸어요. :) 하지만 모두 정리된 상태로 개선이 된 것이라 "
    "생각하시면 될 것 같아요.",
    "예전에 잘 쓰셨다고 생각해서 계속 같이 할 수 있을 거라 기대했는데 아쉬웠답니다! "
    "영어공부는 잘하고 계시죠?",
    "나와나 처음을 함께해 주셨던 분이라 제 나름의 애정이 있는 분이시고, 유저님도 그러하시리라고 믿어요.",
    "그래서 여쭤보고 싶은 말이, 어떤 부분이 아쉬워서 계속 하시지 않게 되신 건지, "
    "다른 앱을 쓰고 계신다면 어떤 면을 제가 배워야 할지, 어떤 면을 제가 더 발전시켰으면 좋을지 "
    "들을 수 있다면, "
    "제가 앞으로 나와나를 이끌어가는 데 정말 큰 힘이 될 거라 생각이 들어요! 혹시 기회가 된다면, "
    "짧은 의견이라도 좋으니 생각을 나눠주시길 기대합니다.",
    "나와나에서 무료로 쓰실 수 있는 기능들은 늘 그대로 있답니다. 그리고, 스피치라는 기능을 "
    "추가했는데, 챌린지에 참여하는 건 모든 유저에게 무료입니다. 언제든지 나와나 오셔서 예전에 "
    "하셨던 교재, 대화로 공부도 하시구요, 팟캐스트도 만들었는데, 이동 중에 편하게 들으실 수 "
    "있었으면 좋겠어요!",
    "그럼 좋은 하루 되시구요!\n오랜만에 반가웠습니다. 앞으로 자주 뵙길 기대할게요!",
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

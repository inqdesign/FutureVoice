#!/usr/bin/env python3
"""Please apply again: the challenger rules are settled now (2026-11-14).

Who: creator_applications 9269fa87 (10bliss, 5234065@naver.com), applied as a
challenger on 2026-11-11 16:46 UTC, before the challenger tab had rules,
country or payment. Row is still `new`, so a new application from the same
email replaces it (creator_apply).

  python3 scripts/challenger-reapply-mail-9269fa87.py            # dry run
  python3 scripts/challenger-reapply-mail-9269fa87.py --send     # after approval
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

CAMPAIGN = "challenger-reapply-2026-11-14"
TO = "5234065@naver.com"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
APPLY_URL = "https://nawana.app/creators#apply"

SUBJECT = "나와나 100일 챌린지, 신청서를 한 번 더 부탁드립니다"

PARAS = [
    "10bliss님, 안녕하세요. 나와나를 만들고 있는 이응규입니다.\n"
    "11월 11일에 100일 챌린지에 신청해 주셔서 고맙습니다. 나와나를 이미 쓰고 계신 분이 "
    "먼저 손을 들어 주셔서 정말 반가웠습니다.",
    "신청해 주신 때는 챌린저 규칙이 아직 다 정해지기 전이었습니다. 그 뒤로 내용이 모두 정리되어서, "
    "번거로우시겠지만 웹사이트에서 신청서를 한 번 더 써 주시면 좋겠습니다.",
    "정해진 내용은 이렇습니다.\n"
    "· 하루: 통화 4분 이상과 스피치 1개. 둘 다 채우면 자동으로 체크인됩니다.\n"
    "· 한 달: 시작일부터 30일씩 세고, 쉬는 날은 한 달에 한 번까지입니다.\n"
    "· 참가비: 3개월 구독료를 한 번에 결제합니다. Light 기준 ₩40,500이고, 마지막 10일은 나와나가 드립니다. 자동으로 다시 결제되지 않습니다.\n"
    "· 보상: 100일이 끝나면 지키신 달 수만큼 이어서 무료로 쓰실 수 있습니다.\n"
    "· 일정: 12월 1일에 시작해서 3월 10일에 끝날 예정입니다. 아직 확정된 날짜는 아니고, 신청자 수에 따라 바뀔 수 있습니다. 신청은 11월 19일까지 받습니다.",
    "신청서 맨 위에서 '챌린저'를 고르시고, 사는 나라는 한국으로, 규칙 동의까지 채워 주시면 바로 결제로 이어집니다. "
    "같은 이메일로 보내 주시면 지난 신청서는 새 것으로 바뀝니다. 자세한 내용도 같은 페이지에 있으니 "
    "천천히 읽어 보시고 신청해 주세요.",
    "궁금한 점은 이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.\n"
    "곧 같이 시작하길 기대하겠습니다!",
]
SIGN = "이응규 드림"
BUTTONS = [
    ("다시 신청하기", APPLY_URL, True),
    ("답장하기", f"mailto:{L.REPLY_TO}", False),
    ("스레드", THREADS_URL, False),
    ("인스타그램 DM", INSTAGRAM_URL, False),
]


def text_body() -> str:
    links = f"다시 신청하기: {APPLY_URL}\n스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}"
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

#!/usr/bin/env python3
"""Cohort 1: Sunny is in, and a short check to the three who did not reply
to the 2026-11-17 welcome (coco, 리지, Daisy) (2026-11-20).

  python3 scripts/creator-cohort1-sunny-and-nudge-mail.py            # dry run
  python3 scripts/creator-cohort1-sunny-and-nudge-mail.py --send     # after approval
"""

import argparse
import html
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "creator-cohort1-2026-11-20"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
SENT_LOG = os.path.expanduser(f"~/.nawana-mail-sent/{CAMPAIGN}.json")

WELCOME_SUBJECT = "나와나 크리에이터 1기로 모시게 되었습니다"
NUDGE_SUBJECT = "지난 메일 확인 부탁드립니다"


def welcome(name: str) -> list[str]:
    return [
        f"안녕하세요, {name} 님!",
        "1기 크리에이터로 모실 수 있게 되어서 정말 영광입니다!\n"
        "나와나 크리에이터 프로그램에 지원해 주셔서 고맙습니다.",
        "독일에서 직장을 구해 동료들과 즐겁게 일하는 모습, 그리고 독일어를 "
        "혼자 공부하는 분들이 끝까지 포기하지 않게 돕고 싶다는 마음이 "
        "정말 와닿았습니다.",
        "제 계획은 이렇습니다.\n"
        "먼저 제가 한 분 한 분께 따로 연락드려서 이야기를 나누고,\n"
        "전체 공지는 오픈 채팅방을 만들어서 전해 드리려고 합니다.",
        "이 메일에 답장으로 본인 스레드 아이디(또는 인스타그램 아이디)를 "
        "한 번만 남겨 주시면, 제가 연락드리는 데 큰 도움이 됩니다.",
        "서로에게 좋은 에너지가 되어, 끝까지 함께할 수 있었으면 좋겠습니다.\n"
        "좋은 하루 보내시고, 곧 메시지로 뵙겠습니다.",
        "나와나. 이응규 드림.",
    ]


def nudge(name: str, platform: str = "스레드") -> list[str]:
    return [
        f"안녕하세요, {name} 님!",
        "지난번 1기 크리에이터 안내 메일 잘 받으셨는지 확인차 연락드립니다.",
        f"이 메일에 답장으로 {platform} 아이디를 한 번만 남겨 주시면, "
        "제가 바로 따로 연락드리겠습니다.",
        "나와나. 이응규 드림.",
    ]


# (name, email, subject, body)
PEOPLE = [
    ("Sunny", "yskim9219@gmail.com", WELCOME_SUBJECT, welcome),
    ("coco", "conie1995@naver.com", NUDGE_SUBJECT, nudge),
    ("리지", "fpahswusdl@naver.com", NUDGE_SUBJECT, nudge),
    ("Daisy", "shygain2@naver.com", NUDGE_SUBJECT, nudge),
    # Instagram only on her application, so the 11-17 mail asked for that.
    ("ssong", "loveqpt6997@naver.com", NUDGE_SUBJECT,
     lambda n: nudge(n, "인스타그램")),
]


def text_body(ps: list[str]) -> str:
    return "\n\n".join(ps) + f"\n\n스레드 {THREADS_URL}\n인스타그램 DM {INSTAGRAM_URL}"


def html_body(ps: list[str]) -> str:
    body = "".join(
        f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
        f'{html.escape(s).replace(chr(10), "<br>")}</p>'
        for i, s in enumerate(ps))
    foot = (f'<p style="font-size:13px;line-height:1.6;color:#666;margin:24px 0 0;">'
            f'<a href="{THREADS_URL}" style="color:#666;">스레드</a> · '
            f'<a href="{INSTAGRAM_URL}" style="color:#666;">인스타그램 DM</a></p>')
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{body}{foot}</div>'


def send(key: str, to: str, subject: str, ps: list[str]) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
        "subject": subject, "text": text_body(ps), "html": html_body(ps),
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
    print(f"from     {L.FROM}\n")
    for name, to, subject, _ in PEOPLE:
        print(f"  {name:8} {to:24} {subject}")
    print(f"\n--- {WELCOME_SUBJECT} ---\n" + text_body(welcome("Sunny")))
    print(f"\n--- {NUDGE_SUBJECT} ---\n" + text_body(nudge("coco")))
    if not args.send:
        print(f"\nDRY RUN, {len(PEOPLE)} mails")
        return
    os.makedirs(os.path.dirname(SENT_LOG), exist_ok=True)
    done = json.load(open(SENT_LOG)) if os.path.exists(SENT_LOG) else {}
    key = L.resend_key()
    for name, to, subject, body in PEOPLE:
        if to in done:
            print("already sent", name)
            continue
        try:
            done[to] = send(key, to, subject, body(name))
        except RuntimeError as e:
            print("stopped at", name, e)
            raise SystemExit(2)
        json.dump(done, open(SENT_LOG, "w"), indent=1)
        print("sent", name, done[to])
        time.sleep(0.6)
    print(f"all {len(PEOPLE)} sent")


if __name__ == "__main__":
    main()

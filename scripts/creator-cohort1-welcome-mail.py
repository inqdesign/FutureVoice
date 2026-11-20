#!/usr/bin/env python3
"""Cohort 1 creators: you are in, and how we will talk (2026-11-17).

Who: the ten `kind = creator` applications on file that day. 10bliss is a
challenger application and is not among them. The founder talks to each one
by DM first, then makes an open chat room for announcements; this mail asks
for the Threads id (Instagram for the three who post there only).

Copy is the founder's own, typos fixed. Sent one mail per person.

  python3 scripts/creator-cohort1-welcome-mail.py            # dry run
  python3 scripts/creator-cohort1-welcome-mail.py --send     # after approval
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

CAMPAIGN = "creator-cohort1-welcome-2026-11-17"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
SENT_LOG = os.path.expanduser(f"~/.nawana-mail-sent/{CAMPAIGN}.json")

# (name on the application, email, posts on Threads)
PEOPLE = [
    ("새라", "srjeon24@gmail.com", True),
    ("Daisy", "shygain2@naver.com", True),
    ("리지", "fpahswusdl@naver.com", True),
    ("밍구", "hurmina9@gmail.com", True),
    ("Seul", "cosx12910@gmail.com", True),
    ("upgrace", "haeunyu0729@gmail.com", False),
    ("ssong", "loveqpt6997@naver.com", False),
    ("coco", "conie1995@naver.com", True),
    ("라몽", "jandy6543@naver.com", True),
    ("이송", "eeyoung524@naver.com", False),
]

SUBJECT = "나와나 크리에이터 1기로 모시게 되었습니다"


def paras(name: str, on_threads: bool) -> list[str]:
    ask = ("이 메일에 답장으로 본인 스레드 아이디를 한 번만 다시 남겨 주시면, "
           "제가 연락드리는 데 큰 도움이 됩니다."
           if on_threads else
           "이 메일에 답장으로 본인 인스타그램 아이디를 한 번만 다시 남겨 주시면, "
           "제가 연락드리는 데 큰 도움이 됩니다. 스레드도 쓰신다면 스레드 아이디도 좋습니다.")
    return [
        f"안녕하세요, {name} 님!",
        "1기 크리에이터로 모실 수 있게 되어서 정말 영광입니다!\n"
        "나와나 크리에이터 프로그램에 함께해 주셔서 고맙습니다.",
        "이제 신청은 어느 정도 다 받은 것 같습니다. 고민해 보니 제가 감당할 수 있는 "
        "인원은 열 분이 최대인 것 같아서, 1기는 이렇게 열 분과 해 보려고 합니다. "
        "앞으로도 계속 이어지는 프로그램이 되었으면 좋겠습니다.",
        "제 계획은 이렇습니다.\n"
        "먼저 제가 한 분 한 분께 따로 연락드려서 이야기를 나누고,\n"
        "전체 공지는 오픈 채팅방을 만들어서 전해 드리려고 합니다.",
        ask,
        "서로에게 좋은 에너지가 되어, 끝까지 함께할 수 있었으면 좋겠습니다.\n"
        "그리고 무엇보다, 저에게 좋은 인연이 되어 주셔서 고맙습니다!\n"
        "좋은 하루 보내시고, 곧 메시지로 뵙겠습니다.",
        "나와나. 이응규 드림.",
    ]


def text_body(name: str, on_threads: bool) -> str:
    return ("\n\n".join(paras(name, on_threads))
            + f"\n\n스레드 {THREADS_URL}\n인스타그램 DM {INSTAGRAM_URL}")


def html_body(name: str, on_threads: bool) -> str:
    ps = "".join(
        f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
        f'{html.escape(s).replace(chr(10), "<br>")}</p>'
        for i, s in enumerate(paras(name, on_threads)))
    foot = (f'<p style="font-size:13px;line-height:1.6;color:#666;margin:24px 0 0;">'
            f'<a href="{THREADS_URL}" style="color:#666;">스레드</a> · '
            f'<a href="{INSTAGRAM_URL}" style="color:#666;">인스타그램 DM</a></p>')
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{ps}{foot}</div>'


def send(key: str, name: str, to: str, on_threads: bool) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(name, on_threads), "html": html_body(name, on_threads),
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
    print(f"from     {L.FROM}\nsubject  {SUBJECT}\n")
    for name, to, on_threads in PEOPLE:
        print(f"  {name:8} {to:28} {'threads' if on_threads else 'instagram'}")
    print("\n--- threads version ---\n" + text_body(*[PEOPLE[0][0], True]))
    print("\n--- instagram version, the ask only ---\n" + paras(PEOPLE[5][0], False)[4])
    if not args.send:
        print(f"\nDRY RUN, {len(PEOPLE)} mails")
        return
    # Who already got it, kept outside the repo: a run stopped by the daily
    # limit is picked up later, and nobody is mailed twice.
    os.makedirs(os.path.dirname(SENT_LOG), exist_ok=True)
    done = json.load(open(SENT_LOG)) if os.path.exists(SENT_LOG) else {}
    key = L.resend_key()
    for name, to, on_threads in PEOPLE:
        if to in done:
            print("already sent", name)
            continue
        try:
            done[to] = send(key, name, to, on_threads)
        except RuntimeError as e:
            print("stopped at", name, e)
            raise SystemExit(2)
        json.dump(done, open(SENT_LOG, "w"), indent=1)
        print("sent", name, done[to])
        time.sleep(0.6)
    print(f"all {len(PEOPLE)} sent")


if __name__ == "__main__":
    main()

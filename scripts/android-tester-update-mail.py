#!/usr/bin/env python3
"""Android closed-test update mail for 1.1.11 (17), 2026-10-18, sent once
Play's review of the release is done. Korean only, no social links: every
tester is already in touch with the founder on Threads.

  python3 scripts/android-tester-update-mail.py            # dry run
  python3 scripts/android-tester-update-mail.py --send     # sends all
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

CAMPAIGN = "android-tester-update-1-1-11-17"
STORE = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

# The founder's own test account (hello.threesby) is left out.
TESTERS = [
    "dlektha2580@gmail.com",
    "jsmoon3810@gmail.com",
    "chloessook@gmail.com",
    "sumin.k1311@gmail.com",
    "pistazie65208@gmail.com",
    "ginakim0804@gmail.com",
    "arooshadeylamiii@gmail.com",
    "nimmo9040@gmail.com",
    "shalomeunkyoung@gmail.com",
    "chjo0330@gmail.com",
    "1219dixie@gmail.com",
]

SUBJECT = "nawana 안드로이드 1.1.11 업데이트"

# ("btn",) the store button · ("p", text) · ("h", text) · ("ul", [items])
BLOCKS = [
    ("btn",),
    ("p", "플레이 스토어에서 nawana를 열고 업데이트를 눌러 주세요."),
    ("p", "안녕하세요, nawana를 만들고 있는 이응규입니다."),
    ("p", "안드로이드 1.1.11 업데이트가 나왔습니다. 그동안 알려 주신 버그들을 고쳤습니다."),
    ("h", "고친 것"),
    ("ul", [
        "통화 중에 미래의 나 목소리가 내 말에 섞여 들어가던 것",
        "앱을 열 때 대화 탭의 인사말과 원이 덜컹 올라가던 것",
        "섀도잉에서 이전 문장의 피드백이 다음 문장에 남던 것",
        "글자를 크게 키운 폰에서 탭 바와 버튼이 겹치던 것",
        "휴대폰을 다시 켜면 매일 오는 전화가 울리지 않던 것",
        "멈춘 통화를 다시 이을 때 아래 버튼이 사라지던 것",
        "창을 닫았다 열면 쓰던 글이 사라지던 것",
        "고른 색이 바로 바뀌지 않던 것",
        "공유 카드가 흐리고 비율이 깨지던 것",
        "뉴스 통화의 제목이 잘려 보이던 것",
        "일본어나 스페인어를 배울 때 사람 목록이 비어 보이던 것",
        "'내 목소리로 듣기'가 원고 길이보다 시간을 많이 쓰던 것",
    ]),
    ("p", "통화 중에 미래의 나 목소리가 다시 마이크로 들어와 대화가 엉키는 일이 아직 있다면 "
          "꼭 알려 주세요. 어떤 폰에서, 스피커였는지 이어폰이었는지만 알려 주셔도 큰 도움이 됩니다."),
    ("p", "이미 스레드로 닿아 있으니 편하게 말씀해 주세요."),
    ("p", "고맙습니다."),
    ("p", "이응규 드림"),
]


def text_body() -> str:
    out = []
    for b in BLOCKS:
        if b[0] == "btn":
            out.append(f"업데이트: {STORE}")
        elif b[0] in ("p", "h"):
            out.append(b[1])
        elif b[0] == "ul":
            out.append("\n".join(f"- {t}" for t in b[1]))
    return "\n\n".join(out)


def html_body() -> str:
    p = 'font-size:16px;line-height:1.7;color:#111;margin:16px 0 0;'
    parts = []
    for b in BLOCKS:
        kind = b[0]
        if kind == "btn":
            parts.append(
                f'<p style="margin:8px 0 0;"><a href="{STORE}" style="display:inline-block;'
                f'background:#1E5BD8;color:#fff;text-decoration:none;font-size:16px;'
                f'font-weight:600;padding:12px 22px;border-radius:12px;">플레이 스토어에서 업데이트</a></p>')
        elif kind == "p":
            parts.append(f'<p style="{p}">{html.escape(b[1])}</p>')
        elif kind == "h":
            parts.append(f'<p style="{p}margin-top:24px;"><b>{html.escape(b[1])}</b></p>')
        elif kind == "ul":
            items = "".join(f'<li style="margin:4px 0;">{html.escape(t)}</li>' for t in b[1])
            parts.append(f'<ul style="font-size:16px;line-height:1.7;color:#111;'
                         f'margin:12px 0 0;padding-left:22px;">{items}</ul>')
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{"".join(parts)}</div>'


def send(key: str, to: str) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
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
    assert "—" not in text_body(), "em dash in copy"
    print(f"from     {L.FROM}\nreply_to {L.REPLY_TO}\nsubject  {SUBJECT}\n"
          f"to       {len(TESTERS)} testers, one mail each\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    key = L.resend_key()
    for to in TESTERS:
        print(f"sent {to} {send(key, to)}")


if __name__ == "__main__":
    main()

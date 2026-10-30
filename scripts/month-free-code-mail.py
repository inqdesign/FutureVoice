#!/usr/bin/env python3
"""One month of Light, free (2026-10-30): one mail per learner, each with
their own comp code from 20261030160000_month_free_light_codes. The code
REPLACES the 20 free minutes (redeeming it takes the balance to 0), and the
month ends by itself with no charge.

Every recipient is on iPhone, so the steps are the iOS ones. The code is
entered in Me -> Usage -> Invite, never on the paywall's "Have a code?",
which opens Apple's offer-code sheet and cannot take a comp code.

  python3 scripts/month-free-code-mail.py EMAILS.txt          # dry run
  python3 scripts/month-free-code-mail.py EMAILS.txt --send   # sends

EMAILS.txt: one address per line. Codes are dealt in file order, so keep the
file as it is between the dry run and the send. The run prints the SQL that
writes each address into `comp_codes.note`, the only record of who got which.
"""

import argparse
import html
import importlib.util
import json
import os
import re
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "month-free-light-2026-10-30"
SUBJECT = "nawana 한 달 무료 코드를 보내 드립니다"
REDEEM_BY = "11월 29일"   # the codes lapse 30 days after the migration runs

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

CODES = [
    "KP63STHD", "EVCLJF5X", "GT6AXS2C", "3G9WRDJH", "5AL8VL8Q",
    "GXUX6PEU", "EJ5JBMWT", "9EBUKRFK", "EYXF3BNB", "GNCNJ6X3",
]

# ("p", text) · ("b", text) · ("h", text) · ("ol", [items]) · ("code",)
BLOCKS = [
    ("p", "안녕하세요, nawana를 만들고 있는 이응규입니다."),
    ("p", "지난 한 달 반 동안 구독해 주시고 앱을 써 주신 분들 덕분에 지금의 최신 버전을 만들어 올 수 있었습니다."),
    ("p", "이제 이 버전을 처음부터 써 봐 주실 분들이 필요했고, 여러분께서 이 앱을 잘 써 주셨으면 하는 마음으로 초대합니다."),
    ("p", "nawana는 유지 비용이 많이 드는 앱입니다. 그래서 언어 학습이 정말 필요한 분께 쓰였으면 하는 것이 제 바람입니다."),
    ("p", "한 달 동안 무료로 쓰실 수 있는 코드를 드립니다. 코드를 등록하시면 "
          "Light 요금제가 바로 열려서 한 달 동안 150분을 통화하실 수 있습니다. "
          "결제 정보는 필요 없고, 한 달이 지나면 자동으로 끝나며 따로 결제되지 않습니다."),
    ("code",),
    ("h", "등록하는 방법"),
    ("ol", [
        f"iPhone에서 App Store를 열고 nawana를 설치합니다: {L.APP_STORE_URL}",
        "앱을 열고 가입 절차를 거치신 뒤 Apple로 가입합니다. 이미 쓰고 계시다면 이 단계는 건너뛰셔도 됩니다.",
        "대화 탭 오른쪽 위의 내 프로필 사진을 누르고, 사용 내역 → 초대하고 통화 시간 받기로 들어갑니다.",
        "\"초대 코드 입력\" 칸에 위 코드를 넣고 등록을 누릅니다.",
    ]),
    ("p", "등록이 끝나면 바로 통화를 시작하실 수 있습니다."),
    ("h", "알아 두실 것"),
    ("ol", [
        "요금제 화면 아래의 \"코드가 있나요?\"는 App Store 코드를 넣는 곳이라 이 코드는 들어가지 않습니다. "
        "꼭 위의 사용 내역 화면에서 등록해 주세요.",
        "이 한 달은 처음 드리는 무료 20분을 대신합니다. 가입하신 뒤 바로 등록하시는 것이 가장 좋습니다.",
        f"코드는 한 분만 쓰실 수 있고, {REDEEM_BY}까지 등록하실 수 있습니다. 한 달은 등록하신 날부터 셉니다.",
    ]),
    ("p", "써 보시고 불편한 점이 있으시면 바로 연락 주세요. 제게 큰 도움이 됩니다. "
          "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다."),
    ("p", "써 보시고 좋다고 생각되시면 App Store에 리뷰를 남겨 주세요. "
          f"다른 분들이 nawana를 발견하는 데 큰 도움이 됩니다: {L.APP_STORE_URL}?action=write-review"),
    ("p", "다시 한번 관심 가져 주셔서 고맙습니다. 앞으로 잘 부탁드립니다. "
          "nawana가 꼭 도움이 되었으면 좋겠습니다."),
    ("p", "이응규 드림"),
]


def text_body(code: str) -> str:
    out = []
    for b in BLOCKS:
        kind = b[0]
        if kind in ("p", "b", "h"):
            out.append(b[1])
        elif kind == "code":
            out.append(f"코드: {code}")
        elif kind == "ol":
            out.append("\n".join(f"{i}. {t}" for i, t in enumerate(b[1], 1)))
    out.append(f"스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}")
    return "\n\n".join(out)


def _link(t: str) -> str:
    return re.sub(r'https://\S+', lambda m: f'<a href="{m[0]}" style="color:#1E5BD8;">{m[0]}</a>',
                  html.escape(t))


def _button(label: str, url: str) -> str:
    return (f'<a href="{url}" style="display:inline-block;margin:0 8px 8px 0;padding:8px 14px;'
            f'border:1px solid #C7C7CC;border-radius:999px;color:#111;text-decoration:none;'
            f'font-size:14px;">{html.escape(label)}</a>')


def html_body(code: str) -> str:
    p = 'font-size:16px;line-height:1.7;color:#111;margin:16px 0 0;'
    parts = []
    for b in BLOCKS:
        kind = b[0]
        if kind == "p":
            parts.append(f'<p style="{p}">{_link(b[1])}</p>')
        elif kind == "b":
            parts.append(f'<p style="{p}"><b>{html.escape(b[1])}</b></p>')
        elif kind == "h":
            parts.append(f'<p style="{p}margin-top:24px;"><b>{html.escape(b[1])}</b></p>')
        elif kind == "code":
            parts.append(
                f'<p style="{p}">코드: <span style="font-family:ui-monospace,Menlo,monospace;'
                f'font-size:18px;font-weight:700;letter-spacing:1px;background:#F2F2F7;'
                f'padding:4px 10px;border-radius:8px;">{html.escape(code)}</span></p>')
        elif kind == "ol":
            items = "".join(f'<li style="margin:4px 0;">{_link(t)}</li>' for t in b[1])
            parts.append(f'<ol style="font-size:16px;line-height:1.7;color:#111;'
                         f'margin:12px 0 0;padding-left:22px;">{items}</ol>')
    parts.append(f'<p style="{p}margin-top:24px;">'
                 f'{_button("답장하기", "mailto:" + L.REPLY_TO)}'
                 f'{_button("스레드", THREADS_URL)}{_button("인스타그램 DM", INSTAGRAM_URL)}</p>')
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{"".join(parts)}</div>'


def send(key: str, to: str, code: str) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(code), "html": html_body(code),
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
    ap.add_argument("emails")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()

    emails = []
    for line in open(args.emails, encoding="utf-8"):
        e = line.strip().lower()
        if e and e not in emails:
            assert L.EMAIL_RE.match(e), f"not an email: {e}"
            emails.append(e)
    assert emails, "no addresses"
    assert len(emails) <= len(CODES), f"{len(emails)} addresses, only {len(CODES)} codes"
    pairs = list(zip(emails, CODES))

    body = text_body(pairs[0][1])
    assert "—" not in body and "—" not in html_body("X"), "em dash in copy"
    print(f"from     {L.FROM}\nreply_to {L.REPLY_TO}\nsubject  {SUBJECT}\n"
          f"to       {len(pairs)} people, one mail each\n\n--- first mail ({pairs[0][0]}) ---\n")
    print(body)
    print("\n--- assignments ---")
    for to, code in pairs:
        print(f"{code}  {to}")
    print("\n--- note SQL (run with the migration applied) ---")
    for to, code in pairs:
        print(f"update public.comp_codes set note = 'month free: {to}' where code = '{code}';")

    if not args.send:
        print("\nDRY RUN")
        return
    key = L.resend_key()
    for to, code in pairs:
        print(f"sent {to} {code} {send(key, to, code)}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

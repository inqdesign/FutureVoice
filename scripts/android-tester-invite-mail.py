#!/usr/bin/env python3
"""Android closed-test invite (2026-10-15), one mail per tester, each with
their own Light comp code. Copy approved by the founder the same day
(docs/android-beta-invite.md in the Android repo). Korean only: every tester
is Korean and already in touch with the founder on Threads, so no social
links.

  python3 scripts/android-tester-invite-mail.py            # dry run (prints the first)
  python3 scripts/android-tester-invite-mail.py --send     # sends all 8

English (2026-10-20), one tester at a time:
  python3 scripts/android-tester-invite-mail.py --en EMAIL CODE          # dry run
  python3 scripts/android-tester-invite-mail.py --en EMAIL CODE --send
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

CAMPAIGN = "android-tester-invite-2026-10-15"
OPT_IN = "https://play.google.com/apps/testing/com.roro.futurevoice"

TESTERS = [
    ("dlektha2580@gmail.com", "HNL45RQJ"),
    ("jsmoon3810@gmail.com", "3S6BADST"),
    ("chloessook@gmail.com", "SC64C6VZ"),
    ("sumin.k1311@gmail.com", "JW7QAWC9"),
    ("pistazie65208@gmail.com", "YF4CYJDM"),
    ("ginakim0804@gmail.com", "BDLN6D9X"),
    ("arooshadeylamiii@gmail.com", "FUVFVXRJ"),
    ("nimmo9040@gmail.com", "ZC8PLJ8P"),
]

SUBJECT = "nawana 안드로이드 테스트 안내"

# Blocks: ("p", text) paragraph · ("ol", [items]) · ("ul", [items]) ·
# ("code",) the code line · ("b", text) a bold paragraph · ("h", text) heading.
BLOCKS = [
    ("p", "안녕하세요, nawana를 만들고 있는 이응규입니다."),
    ("p", "안드로이드 테스트에 함께해 주셔서 감사합니다. 계획했던 것보다 조금 늦어졌는데, "
          "기다려 주셔서 고맙습니다. 그럼 천천히 안내해 드리겠습니다."),
    ("p", "구글 플레이 규정상 테스터 열두 분이 14일 동안 앱을 설치해 두셔야 정식 출시가 열립니다. "
          "그 14일 동안 편하게 써 주시면 됩니다."),
    ("h", "시작하는 방법"),
    ("ol", [
        f'안드로이드 폰에서 이 링크를 열고 "테스터 되기"를 눌러 주세요: {OPT_IN}',
        "같은 화면의 플레이 스토어 링크에서 nawana를 설치합니다.",
        "목소리를 녹음하고 Google 계정으로 가입합니다.",
    ]),
    ("p", "처음에는 모두 일반 사용자와 똑같이 시작합니다. 무료 시간 20분이 주어지고, "
          "그다음 아래 코드를 넣어 구독하시면 됩니다. 코드를 넣으면 Light 요금제를 "
          "한 달 동안 무료로 쓰실 수 있습니다."),
    ("code",),
    ("p", "20분을 다 쓰실 때까지 기다리실 필요는 없습니다. 써 보시다가 "
          '"이거 좋다, 구독하고 싶다"는 마음이 드는 그 순간에 넣어 주세요.'),
    ("b", '대화 탭 오른쪽 위 내 프로필 사진 → 구독하기 → 요금제 화면 아래 "코드가 있나요?"에서 '
          "넣으시면 됩니다."),
    ("h", "부탁드리고 싶은 것"),
    ("p", "테스터라기보다, 매달 돈을 내고 구독할지 고민하는 사람의 입장에서 써 봐 주세요."),
    ("p", "사소한 버그는 금방 고칠 수 있습니다. 제가 정말 듣고 싶은 건 이런 이야기입니다."),
    ("ul", [
        "다른 서비스와 비교했을 때, nawana를 구독해서 써 보실 의사가 있으신지",
        "아니라면, 대신 어떤 서비스를 쓰실 것 같은지",
        "이미 쓰고 계신 서비스가 있다면, nawana를 함께 써 보고 싶으신지, 아니라면 왜 그런지",
    ]),
    ("p", "듣기 좋은 말보다 솔직한 이야기가 더 큰 도움이 됩니다."),
    ("p", "이미 스레드로 모두 닿아 있으니, 정말 편하게 말씀해 주세요. "
          "버그가 있다면 바로 고쳐서 업데이트하겠습니다."),
    ("p", "다시 한번 정말 고맙습니다."),
    ("p", "독일에서 혼자, 큰 꿈을 안고 nawana를 진심으로 만들고 있습니다. "
          "어떻게 인연이 닿아 연결되었는지는 알 수 없지만, 저에게는 정말 귀한 인연이라고 생각합니다."),
    ("p", "훗날 nawana를 안드로이드에서 처음 써 본 사람이라고 자랑하실 수 있을 만큼 "
          "잘해 보고 싶습니다."),
    ("p", "이응규 드림"),
]


SUBJECT_EN = "Testing nawana on Android"
CAMPAIGN_EN = "android-tester-invite-en-2026-10-20"

BLOCKS_EN = [
    ("p", "Hi, I'm Eunggyu, the person building nawana."),
    ("p", "Thank you for joining the Android test. Here is everything you need to get started."),
    ("p", "Google Play only opens a public release once twelve testers have kept the app "
          "installed for 14 days. Please keep it on your phone for those two weeks and use it "
          "whenever you like."),
    ("h", "How to start"),
    ("ol", [
        f'On your Android phone, open this link and tap "Become a tester": {OPT_IN}',
        "Install nawana from the Play Store link on that page.",
        "Record your voice and sign up with your Google account.",
    ]),
    ("p", "You start like any new user, with 20 free minutes. After that, subscribe with the "
          "code below and the Light plan is yours, free for a month."),
    ("code",),
    ("p", "No need to wait until the 20 minutes are used up. Enter it whenever you find "
          "yourself thinking you'd actually pay for this."),
    ("b", 'Tap your profile photo at the top right of the Talk tab, then Subscribe, then '
          '"Have a code?" at the bottom of the plans screen.'),
    ("h", "What I'd love to hear"),
    ("p", "Rather than testing it like a tester, try it as someone deciding whether to pay for "
          "it every month."),
    ("p", "Small bugs are quick to fix. What I really want to know is this:"),
    ("ul", [
        "Compared with what else is out there, would you pay for nawana?",
        "If not, what would you use instead?",
        "If you already use another app, would you use nawana alongside it, and if not, why?",
    ]),
    ("p", "An honest answer helps far more than a kind one. Just reply to this email, and if "
          "something breaks, I'll fix it and ship an update."),
    ("p", "I'm building nawana on my own in Germany, with big hopes for it. Thank you for being "
          "one of the first people to try it on Android."),
    ("p", "Eunggyu"),
]


def text_body(code: str, blocks=BLOCKS, label="코드") -> str:
    out = []
    for b in blocks:
        kind = b[0]
        if kind in ("p", "b", "h"):
            out.append(b[1])
        elif kind == "code":
            out.append(f"{label}: {code}")
        elif kind == "ol":
            out.append("\n".join(f"{i}. {t}" for i, t in enumerate(b[1], 1)))
        elif kind == "ul":
            out.append("\n".join(f"- {t}" for t in b[1]))
    return "\n\n".join(out)


def _link(t: str) -> str:
    e = html.escape(t)
    return e.replace(OPT_IN, f'<a href="{OPT_IN}" style="color:#1E5BD8;">{OPT_IN}</a>')


def html_body(code: str, blocks=BLOCKS, label="코드") -> str:
    p = 'font-size:16px;line-height:1.7;color:#111;margin:16px 0 0;'
    parts = []
    for b in blocks:
        kind = b[0]
        if kind == "p":
            parts.append(f'<p style="{p}">{_link(b[1])}</p>')
        elif kind == "b":
            parts.append(f'<p style="{p}"><b>{html.escape(b[1])}</b></p>')
        elif kind == "h":
            parts.append(f'<p style="{p}margin-top:24px;"><b>{html.escape(b[1])}</b></p>')
        elif kind == "code":
            parts.append(
                f'<p style="{p}">{label}: <span style="font-family:ui-monospace,Menlo,monospace;'
                f'font-size:18px;font-weight:700;letter-spacing:1px;background:#F2F2F7;'
                f'padding:4px 10px;border-radius:8px;">{html.escape(code)}</span></p>')
        elif kind in ("ol", "ul"):
            tag = kind
            items = "".join(f'<li style="margin:4px 0;">{_link(t)}</li>' for t in b[1])
            parts.append(f'<{tag} style="font-size:16px;line-height:1.7;color:#111;'
                         f'margin:12px 0 0;padding-left:22px;">{items}</{tag}>')
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{"".join(parts)}</div>'


def send(key: str, to: str, code: str, en: bool = False) -> str:
    campaign = CAMPAIGN_EN if en else CAMPAIGN
    idem = f"{campaign}:{to}"
    blocks, label, subject = (BLOCKS_EN, "Code", SUBJECT_EN) if en else (BLOCKS, "코드", SUBJECT)
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
        "subject": subject, "text": text_body(code, blocks, label),
        "html": html_body(code, blocks, label),
        "headers": {"X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": campaign}],
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
    ap.add_argument("--en", nargs=2, metavar=("EMAIL", "CODE"))
    args = ap.parse_args()
    if args.en:
        to, code = args.en
        body = text_body(code, BLOCKS_EN, "Code")
        assert "—" not in body, "em dash in copy"
        print(f"from     {L.FROM}\nreply_to {L.REPLY_TO}\nsubject  {SUBJECT_EN}\nto       {to}\n\n{body}")
        if not args.send:
            print("\nDRY RUN")
            return
        print(f"sent {to} {code} {send(L.resend_key(), to, code, en=True)}")
        return
    assert "—" not in text_body("X"), "em dash in copy"
    to, code = TESTERS[0]
    print(f"from     {L.FROM}\nreply_to {L.REPLY_TO}\nsubject  {SUBJECT}\n"
          f"to       {len(TESTERS)} testers, one mail each\n\n--- first mail ({to}) ---\n")
    print(text_body(code))
    if not args.send:
        print("\nDRY RUN")
        return
    key = L.resend_key()
    for to, code in TESTERS:
        print(f"sent {to} {code} {send(key, to, code)}")


if __name__ == "__main__":
    main()

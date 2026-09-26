#!/usr/bin/env python3
"""The founder writes to the one Plus ANNUAL subscriber before it charges.

g4n4778kwv (d48b0216) signed up 2026-09-24, hit the free-call wall, saw the
paywall four times and bought Plus ANNUAL at €149.99 — on a card that said
"Talking: No limit". Apple charges them 2026-09-27 08:11 CEST. Plus stopped
being uncapped on 2026-09-26 (600 min + 30 scenes), so the founder tells them
before the money moves, and promises to leave THIS account on what it bought.

Two things in the draft were checked against production and changed:

  · The usage claim, measured properly. Billed minutes are SPEECH — silence
    is free — so the ledger's 33 minutes hid a 63-minute call. By the clock
    someone really has talked over an hour in a day (2026-08-30, three calls,
    63 min) and a current learner did 56 minutes across seven calls on
    2026-09-25. What the data does NOT show is three consecutive days of it,
    so the mail says the part that is true, which is just as convincing.

  · Their OWN first day went badly and the draft didn't know it: three
    `daily_cap_reached` walls on 2026-09-24, because a trial is metered at 35
    minutes whatever plan it trials and build 54 never said so. They talked 35
    minutes, were stopped, and have not opened the app since. Writing to
    someone about a limit without mentioning the limit they already hit would
    read as not knowing your own product, so the mail owns it first.

NEVER sends on its own (`--send` only after the copy is approved), and it
REFUSES to send unless the account is actually stamped with what it promises
— see `guard()`. Run `supabase/migrations/20260926180000_honour_annual_plus.sql`
first.
"""

import html
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "plus-annual-cap-2026-09-26"
SUBJECT = "결제 전에 꼭 드리고 싶은 말씀이 있습니다"
TO = "g4n4778kwv@privaterelay.appleid.com"
USER_ID = "d48b0216-9438-482d-87c1-4947063c6ff1"

# What the mail promises to leave on this account: Plus as it was SOLD on
# 09-24 — no talk ceiling, 120 Watch scenes.
PROMISED_SCENES = 120

BODY = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "추석 연휴는 잘 보내셨어요? 우선 나와나를 써주시고, 구독까지 결정해 주셔서 정말 고맙습니다. "
    "저에겐 큰 힘이 되었습니다.",

    "지금 플러스 연간을 체험 중이시고, 독일 시간으로 9월 27일 일요일 오전 8시 11분에 "
    "자동으로 결제가 됩니다. 그 전에 꼭 직접 말씀드리고 싶은 것이 두 가지 있어서 "
    "급하게 연락을 드립니다.",

    "첫째로, 사과를 드려야 합니다. 9월 24일에 35분쯤 대화하시다가 갑자기 막히셨을 텐데요. "
    "체험 기간에는 통화 시간이 35분으로 제한되어 있었는데, 그 사실을 앱이 미리 말씀드리지 "
    "않았습니다. 무제한이라고 적힌 화면을 보고 결제하셨을 텐데 바로 그날 막히셨으니, "
    "많이 당황하셨을 것 같습니다. 죄송합니다. 지금 버전에서는 결제 전에 그 숫자를 "
    "먼저 보여드리도록 고쳤습니다.",

    "둘째로, 제가 잘못 생각한 것이 있어 바로잡으려 합니다. 플러스를 \"무제한 통화\"라고 "
    "내놓았는데, 이게 제 계산 착오였습니다. 처음엔 설마 하루에 10분 이상 매일 하는 분이 "
    "있을까 싶었어요. 저도 직접 써보니 그게 쉬운 일이 아니더라고요. 그런데 하루에 한 "
    "시간 넘게 통화하신 분이 나오고, 최근에도 하루에 한 시간 가까이 쓰시는 분이 "
    "나타났습니다. 그 속도면 한 달에 600분을 훌쩍 넘습니다. 통화는 1분마다 실제 비용이 "
    "나가는 구조라, 이대로 두면 제가 적자를 넘어 사업을 접어야 하는 일이 생길 것 "
    "같습니다.",

    "그래서 플러스를 무제한이 아니라 한 달 통화 600분(하루 20분)과 상황연습 30개로 "
    "바꾸기로 했습니다. 대부분의 분께는 사실상 제한 없이 쓰시는 것과 같은 경험이 될 거라 "
    "생각합니다. 아직 서비스를 시작한 지 2주밖에 되지 않아 한 달치 기록도 없는 상태라 "
    "확신할 수는 없지만, 지금 흐름으로는 쉽지 않아 보입니다.",

    "다만 g4n4778kwv 님은 \"무제한\"이라고 적힌 화면을 보고 결정해 주신 분입니다. "
    "그래서 이 계정은 처음 구매하셨을 때 그대로, 통화 제한 없이 쓰실 수 있도록 이미 "
    "설정해 두었습니다. 혹시 연락이 닿지 않아 그대로 결제가 되더라도 걱정하지 않으셔도 "
    "됩니다. 약속드린 것은 지킵니다.",

    "그럼에도 이 메일을 드리는 이유는, 바뀐 내용을 모르신 채로 결제되는 일만은 없었으면 "
    "해서입니다. 부탁을 드리는 것이 아니라 알려드리는 것입니다. 참고로 구독 취소는 "
    "아이폰 설정 앱 → 맨 위의 본인 이름 → 구독 → nawana 에서 하실 수 있고, 결제 전에 "
    "하셔야 반영됩니다.",

    "지금까지 연락드린 분들은 오히려 저보다 더 걱정을 해주시면서 600분과 상황연습 30개를 "
    "이해해 주셨고, 오래 쓰시던 분도 \"쓰다 보면 의미 없이 쓰게 될 때도 있어서 오히려 "
    "나을 수 있겠다\"고 말씀해 주시더군요. g4n4778kwv 님은 어떻게 느끼실지 궁금합니다.",

    "메일 말고는 닿을 방법이 없어 아쉽습니다. 혹시 스레드나 인스타그램 DM으로 연락 "
    "주시면 더 자세히 설명드리고, 직접 의견을 듣고 싶습니다. 애플 계정을 가리는 메일이라 "
    "g4n4778kwv 라는 이름으로밖에 부르지 못해 죄송합니다.",

    "이제 막 시작하는 중이라 매끄럽지 못한 부분이 많습니다. 번거롭게 해드려 죄송하고, "
    "계속 나아지는 모습으로 갚겠습니다. 목표하시는 곳까지 가시는 데 도움이 되도록 "
    "잘 만들어 보겠습니다.",

    "그럼 연락 기다리겠습니다.",
    "이응규 드림",
]


def text_body() -> str:
    return "\n\n".join(BODY + [L.SITE_URL])


def html_body() -> str:
    def p(s, top=14):
        return (f'<p style="font-size:16px;line-height:1.7;color:{L.INK};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')
    paras = [p(BODY[0], top=0)] + [p(s) for s in BODY[1:]]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{L.FONT_FACE}</style></head><body style="margin:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="52" height="52" alt="nawana"
                       style="display:block;width:52px;height:52px;border-radius:13px;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:21px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</div>
                <div style="font-size:12px;color:{L.FAINT};margin-top:3px;font-family:{L.MONO};">{html.escape(L.TAGLINE)}</div>
              </td>
            </tr>
          </table>
          {"".join(paras)}
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(L.FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def guard() -> tuple[bool, str]:
    """The mail promises this account keeps uncapped talk. Refuse to send it
    until the row actually says so — a promise the server contradicts is
    worse than no mail."""
    rows = L.sql("select status, talk_unlimited, monthly_scenes, monthly_seconds "
                 f"from user_subscriptions where user_id = '{USER_ID}'")
    if not rows:
        return False, "no subscription row for this user"
    r = rows[0]
    ok = bool(r.get("talk_unlimited")) and r.get("monthly_scenes") == PROMISED_SCENES
    return ok, (f"status={r.get('status')} talk_unlimited={r.get('talk_unlimited')} "
                f"scenes={r.get('monthly_scenes')} seconds={r.get('monthly_seconds')}")


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO, "subject": SUBJECT,
        "text": text_body(), "html": html_body(),
        "headers": {"List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
                    "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    print(f"to: {TO}\nsubject: {SUBJECT}\n")
    print(text_body())
    ok, detail = guard()
    print(f"\n--- account: {detail}")
    print(f"--- promise kept on the server: {'YES' if ok else 'NO'}")
    if "--send" not in sys.argv:
        print("dry run. add --send once the copy is approved.")
        return
    if not ok:
        print("REFUSED: the mail promises uncapped talk and the row does not say so. "
              "Apply 20260926180000_honour_annual_plus.sql first.")
        return
    print(f"sent: {send(L.resend_key())}")


if __name__ == "__main__":
    main()

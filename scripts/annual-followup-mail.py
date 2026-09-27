#!/usr/bin/env python3
"""The day-after note to the annual subscriber (2026-09-27).

Yesterday's mail (`plus-annual-cap-mail.py`) warned d48b0216 that Plus was
losing its uncapped talk before the charge landed. The charge landed this
morning — €149.99, active to 2027-09-27 — and their evening went badly in a
way worth writing about rather than leaving them to guess at:

  · 21:28–21:32 Berlin: SEVEN calls died before a single turn
    (`talk_rt_failed`, code `socket`, turns 0, each lasting 17–28 s). Nobody
    else failed today, so it was not the gateway. It is the bug the founder
    had already reproduced on their own phone — three in a row, 23 s of
    speech, 0 turns, cut at 29 s — and fixed in `366266a`: the idle watchdog
    was reading the BILLING condition ("nothing counts before the first turn
    is confirmed"), so a long opening utterance looked like an empty room and
    the call put itself down mid-sentence. Their 22:14 call ran 30 turns, so
    the workaround in this mail is the one their own evening demonstrates.
  · 21:30–21:32, between those failures, they opened the subscription screen
    three times. The annual plan is off sale while its price is re-cut, so
    that screen currently shows monthly cards and no "current plan" marker to
    an annual subscriber — they were almost certainly checking whether their
    subscription was what had broken.

So: thanks, the cause, the workaround, and the reassurance. What the mail
does NOT do is recite their session log back at them — the advice stands on
its own, and a founder quoting timestamps at a customer reads as surveillance
rather than service.

Dry run by default. `--send` only after the copy is approved.
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

CAMPAIGN = "annual-followup-2026-09-27"
SUBJECT = "오늘 통화가 끊긴 이유를 찾았습니다"
TO = "g4n4778kwv@privaterelay.appleid.com"
USER_ID = "d48b0216-9438-482d-87c1-4947063c6ff1"

BODY = [
    "안녕하세요. 나와나를 만든 이응규입니다.",

    "어제에 이어 또 연락드려 죄송합니다. 오늘 아침에 연간 구독이 시작되었습니다. "
    "믿고 결정해 주셔서 정말 고맙습니다.",

    "그런데 오늘 저녁에 통화가 자꾸 끊기셨을 것 같습니다. 원인을 찾았고, 앱 문제가 "
    "맞습니다. 죄송합니다.",

    "통화를 시작하고 첫 마디가 30초 가까이 길어지면, 앱이 \"아무도 말하지 않고 있다\"고 "
    "잘못 판단해서 말씀하시는 도중에 통화를 멈춰 버리고 있었습니다. 저도 제 폰에서 "
    "똑같이 세 번 연속으로 겪고 나서야 알아챘습니다.",

    "이미 고쳤고 다음 버전에 들어갑니다. 그때까지는 통화를 시작하실 때 "
    "첫 마디만 짧게 던져 주세요. 한 문장이면 충분하고, 미래의 내가 한 번 대답하고 "
    "나면 그다음부터는 얼마든지 길게 말씀하셔도 괜찮습니다.",

    "한 가지 더 말씀드립니다. 혹시 구독 화면을 열어 보셨을 때 연간 요금제가 보이지 "
    "않으셨다면, 어제 말씀드린 요금 정리를 하면서 연간 가격을 다시 매기는 중이라 잠시 "
    "판매를 내려둔 것뿐입니다. 이틀 안에 다시 올라갑니다.",

    "g4n4778kwv 님의 연간 구독은 아무 영향도 받지 않습니다. 어제 약속드린 대로 통화 "
    "시간 제한 없이 쓰실 수 있도록 그대로 두었습니다.",

    "이제 막 시작하는 중이라 자꾸 번거롭게 해드립니다. 그래도 이렇게 실제로 써 주시는 "
    "덕분에 하나씩 찾아서 고치고 있습니다. 불편한 점이 있으시면 이 메일로 답장 "
    "주시거나, 스레드나 인스타그램 DM으로도 편하게 알려주세요.",

    "고맙습니다.",
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
    """The mail says their subscription is untouched and still uncapped.
    Refuse to send while the row says otherwise."""
    rows = L.sql("select status, plan_id, talk_unlimited, monthly_scenes "
                 f"from user_subscriptions where user_id = '{USER_ID}'")
    if not rows:
        return False, "no subscription row"
    r = rows[0]
    ok = r.get("status") == "active" and bool(r.get("talk_unlimited"))
    return ok, (f"status={r.get('status')} plan={r.get('plan_id')} "
                f"talk_unlimited={r.get('talk_unlimited')} scenes={r.get('monthly_scenes')}")


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
    print(f"--- still uncapped, as the mail says: {'YES' if ok else 'NO'}")
    if "--send" not in sys.argv:
        print("dry run. add --send once the copy is approved.")
        return
    if not ok:
        print("REFUSED: the mail promises an untouched, uncapped subscription "
              "and the row does not say that.")
        return
    print(f"sent: {send(L.resend_key())}")


if __name__ == "__main__":
    main()

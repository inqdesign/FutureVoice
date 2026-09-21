#!/usr/bin/env python3
"""Follow-up mail to the six first callers whose free call misbehaved.

They signed up while the first-call grant ran on 1.0.5 (2026-09-17 → 09-19)
and met the old wall: a call cut before the pool was empty, and no trial offer.
The mail asks how the call was and tells them five more minutes are waiting —
so it MUST NOT reach anyone the time has not actually reached. Every recipient
is checked against the ledger (`goodwill_grant`, written by
20260921090000_extra_time_for_first_callers.sql) before a send, and skipped
if it is missing.

Dry run by default: prints who would get it and the text. `--send` sends.
Resend's Idempotency-Key is per recipient, so a re-run never sends twice.

Styling, keys and plumbing come from waitlist-launch-mail.py so the two mails
look like they came from the same person.
"""

import html
import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "first-call-followup-2026-09"
SUBJECT = "미래의 나와의 첫 통화, 어떠셨나요?"

RECIPIENTS = [
    "sajacall@gmail.com",
    "sodamkim25@gmail.com",
    "ninakimsuyeon@gmail.com",
    "hbkim1042@gmail.com",
    "hsht6r2z9b@privaterelay.appleid.com",
    "joohami0806@gmail.com",
]

BODY = [
    "안녕하세요, 나와나(nawana)입니다.",
    "가입하시고 미래의 나와 첫 통화를 해 주셔서 고맙습니다. 처음 들어 본 내 목소리의 통화, 어떠셨나요?",
    "더 사용해 보시라고 통화 5분을 추가로 넣어 드렸습니다. 앱을 열고 통화 버튼을 누르면 바로 이어서 쓰실 수 있습니다. "
    "그사이 통화가 더 자연스럽게 이어지도록 앱도 손봤습니다.",
    "마음에 드시면 앱 위쪽 프로필의 '구독하기'에서 7일 무료 체험도 시작하실 수 있습니다.",
    "스레드나 인스타 DM으로 언제든지 편하게 피드백을 알려주세요! 인스타 DM은 앱 설정에서 바로 보내실 수 있습니다. "
    "더 좋은 앱을 만들어 보겠습니다.",
]


def text_body() -> str:
    return "\n\n".join(BODY + [L.SIGN, L.SITE_URL])


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
          <p style="font-size:15px;color:{L.DIM};margin:32px 0 0;">{html.escape(L.SIGN)}</p>
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


def granted() -> dict[str, int]:
    """email → balance, for recipients whose goodwill grant is on the ledger."""
    emails = ",".join(L.q(e) for e in RECIPIENTS)
    rows = L.sql(f"""
        select u.email, c.balance
          from auth.users u join user_credits c on c.user_id = u.id
         where u.email in ({emails})
           and exists (select 1 from usage_ledger l
                        where l.user_id = u.id and l.action = 'goodwill_grant')""")
    return {r["email"]: r["balance"] for r in rows}


def send(key: str, to: str) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO, "subject": SUBJECT,
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
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # Resend's WAF 1010s urllib's default
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    really = "--send" in sys.argv
    ok = granted()
    print(f"subject: {SUBJECT}\n")
    print(text_body())
    print("\n--- recipients")
    for to in RECIPIENTS:
        print(f"  {'✓' if to in ok else '✗'} {to}"
              + (f"  (balance {ok[to]}s)" if to in ok else "  — no goodwill grant yet, SKIPPED"))
    if not really:
        print("\ndry run. add --send to send to the ✓ rows.")
        return
    key = L.resend_key()
    for to in RECIPIENTS:
        if to not in ok:
            continue
        print(f"sent {to}: {send(key, to)}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

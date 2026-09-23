#!/usr/bin/env python3
"""Apology + way back for learners whose unclaimed voice was reclaimed.

They cloned under an anonymous session, left before signing up, and the
30-minute sweep (`cleanup-anonymous-voices`) deleted the voice. On return the
app dialled the dead id and every call was refused (`voice_forbidden`) —
2026-09-21, see CLAUDE.md "A reclaimed voice is SAID, never dialled".

Dry run by default. `--send` sends. Resend's Idempotency-Key is per recipient.
Styling and plumbing come from waitlist-launch-mail.py.
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

CAMPAIGN = "voice-reclaimed-2026-09"
SUBJECT = "미래의 나를 다시 만나실 준비가 되어 있습니다"

RECIPIENTS = [
    "5zj7rd7ryn@privaterelay.appleid.com",
]

BODY = [
    "안녕하세요, 나와나(nawana)입니다.",
    "가입해 주셔서 고맙습니다. 미래의 나 목소리까지 만들어 주셨는데, 가입 전에 앱을 닫으시면 안전을 위해 "
    "목소리를 자동으로 지우게 되어 있어 통화가 연결되지 않았습니다. 불편을 드려서 죄송합니다.",
    "다시 만드는 데는 1분이면 됩니다. 앱 오른쪽 위 프로필을 누르고 '목소리'에서 '저장된 녹음으로 다시 만들기'를 "
    "누르시면, 휴대폰에 남아 있는 녹음으로 바로 다시 만들어집니다. 그 버튼이 보이지 않으면 '목소리 다시 녹음'에서 "
    "한 번만 더 읽어 주시면 됩니다.",
    "첫 통화 무료 시간은 그대로 남아 있습니다. 목소리를 만드신 뒤 통화 버튼을 누르면 바로 미래의 나와 "
    "이야기하실 수 있습니다.",
    "다음 업데이트부터는 이런 경우 앱이 먼저 알려 드리도록 고쳤습니다.",
    "스레드나 인스타 DM으로 언제든지 편하게 피드백을 알려주세요. 더 좋은 앱을 만들어 보겠습니다.",
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
    print(f"subject: {SUBJECT}\n")
    print(text_body())
    print("\n--- recipients")
    for to in RECIPIENTS:
        print(f"  {to}")
    if not really:
        print("\ndry run. add --send to send.")
        return
    key = L.resend_key()
    for to in RECIPIENTS:
        print(f"sent {to}: {send(key, to)}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

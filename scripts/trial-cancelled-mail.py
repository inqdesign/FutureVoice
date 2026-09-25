#!/usr/bin/env python3
"""A personal note to a trialer who cancelled (2026-09-25).

meehoo4u (2bda6067) started the 3-day Light trial on 09-25, turned auto-renew
off five seconds later, talked out the 35-minute trial pool the same morning
and has been using review ever since. The founder writes to ask why, and to
say how to resume while the trial is still running.

NEVER sends on its own: `--send` is honored only after the copy is approved,
and the grant line below must be TRUE before it goes out.
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

CAMPAIGN = "trial-cancelled-2026-09-25"
SUBJECT = "나와나를 써주셔서 고맙습니다."
TO = "meehoo4u@gmail.com"

# Set True only once the 30 minutes are actually on the account.
GRANTED_MINUTES = 30

BODY = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "우선 나와나를 사용해주셔서 너무 고맙습니다.",
    "아쉽게도 체험을 취소하신 소식을 받았고, 혹시 체험을 취소하신 이유를 조금 들어볼 수 있을지 궁금해서 메일을 보냅니다. "
    "나와나는 이제 시작이라 실제 사용해 주신 분의 솔직한 피드백이 더 좋은 서비스를 만드는 데 큰 도움이 됩니다.",
    "체험 중에 과대 사용을 방지하기 위해 시간 제한을 뒀었는데, 그 시간이 초과해서 결제 창이 떴던 것입니다. "
    "메시지가 잘 전달되지 못한 것 같아 아쉽네요.",
    "통화 30분을 더 넣어 두었으니, 혹시 체험을 다시 이어가고 싶으시다면 쓰실 수 있습니다.",
    "혹시 계속해서 쓰시고 싶으시다면, 아직은 체험 기간이 끝나지 않았습니다. 체험은 한국 시간으로 9월 28일 오후 3시경에 끝나는데, "
    "그 전에 아이폰 설정 앱을 열고 맨 위의 본인 이름(Apple 계정)을 누른 뒤 구독 → nawana 에서 '구독 갱신'을 선택하시면 그대로 이어집니다. "
    "앱에서는 오른쪽 위 프로필 → 구독 → '구독 관리'를 누르시면 같은 화면으로 가실 수 있습니다. "
    "계신 곳과 시차가 있으니 9월 27일 안에 해 두시는 편이 안전합니다. "
    "구독이 시작되면 그때부터는 매달 통화 150분을 쓰실 수 있습니다.",
    "체험 기간이 끝난 후에도 물론 언제든 다시 찾아주셔서 사용하셔도 좋습니다.",
    "처음 시작을 같이 해주셔서 제겐 큰 의미가 있습니다. 외국에서 힘내시구요!",
    "연락 주신다면 더 좋은 서비스 만들어서 꼭 돌아오시도록 해볼게요!",
    "그럼 좋은 하루 되세요.",
    "이응규 드림.",
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


def balance() -> int | None:
    rows = L.sql(f"select balance from user_credits where user_id = "
                 f"'2bda6067-5324-4ad2-ae9b-adbca2592800'")
    return rows[0]["balance"] if rows else None


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
    bal = balance()
    print(f"\n--- balance on the account: {bal}s "
          f"(the mail claims {GRANTED_MINUTES} min = {GRANTED_MINUTES * 60}s)")
    if "--send" not in sys.argv:
        print("dry run.")
        return
    if (bal or 0) < GRANTED_MINUTES * 60:
        print("REFUSED: the minutes the mail promises are not on the account yet.")
        return
    print(f"sent: {send(L.resend_key())}")


if __name__ == "__main__":
    main()

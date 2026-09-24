#!/usr/bin/env python3
"""One mail to the Plus trialer whose trial was walled on day one (2026-09-24).

d48b0216 bought a 3-day Plus trial in the morning and hit DAILY_CAP_REACHED
that evening: the trial pool (2,100 s) had the same day's free call (607 s)
counted into it. 20260924190000_trial_topup_d48b0216.sql put 1,800 s on the
balance; this mail says so. It is sent only if that ledger row exists.

Dry run by default. `--send` sends. Idempotent per recipient via Resend.
Styling and plumbing come from waitlist-launch-mail.py.
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

CAMPAIGN = "trial-topup-2026-09-25"
SUBJECT = "체험 중에 쓰실 통화 30분을 더 넣어 드렸습니다"
USER_ID = "d48b0216-9438-482d-87c1-4947063c6ff1"

BODY = [
    "안녕하세요, 나와나(nawana)입니다.",
    "마지막 통화 뒤에 '이번 달 통화 시간을 다 썼다'는 안내가 나왔을 텐데, 저희 계산 실수였습니다.",
    "체험 기간 동안 쓰실 수 있게 통화 30분을 추가로 넣어 드렸습니다. 앱을 열고 통화 버튼을 누르시면 바로 이어서 쓰실 수 있습니다. "
    "체험이 끝나면 구독하신 대로 마음껏 쓰실 수 있습니다.",
    "쓰시면서 어떠셨는지 궁금합니다. 어떤 피드백도 좋고, 제가 도와드릴 수 있는 게 있다면 너무 좋을 것 같습니다. "
    "이 메일에 답장하셔도 되고, 스레드로 메시지를 보내주셔도 좋습니다.",
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


def recipient() -> tuple[str, int] | None:
    rows = L.sql(f"""
        select u.email, c.balance
          from auth.users u join user_credits c on c.user_id = u.id
         where u.id = '{USER_ID}'
           and exists (select 1 from usage_ledger l
                        where l.user_id = u.id and l.action = 'trial_topup')""")
    return (rows[0]["email"], rows[0]["balance"]) if rows else None


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
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    # SENT ONCE on 2026-09-24 (Resend 01a0d569-cf01-76d3-998e-0861def057e3).
    # The founder said not to send again. This stays a dry run.
    really = False
    r = recipient()
    print(f"subject: {SUBJECT}\n")
    print(text_body())
    print("\n--- recipient")
    if not r:
        print("  ✗ no trial_topup ledger row, nothing sent")
        return
    to, balance = r
    print(f"  ✓ {to}  (balance {balance}s)")
    if not really:
        print("\ndry run. add --send to send.")
        return
    print(f"sent {to}: {send(L.resend_key(), to)}")


if __name__ == "__main__":
    main()

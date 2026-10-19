#!/usr/bin/env python3
"""Ask the three learners who signed up on 2026-10-18 (KST) and made their
first call how it felt.

Picked from the ledger: signed up that day, at least one `talk_time` tick.
All three are learning German and still hold most of the free 20 minutes,
which is why the mail can point them back to a second call. The balance is
re-read before a send and anyone under 5 minutes is skipped, so the line
about time left is never untrue.

Dry run by default: prints who would get it and the text. `--send` sends.
Resend's Idempotency-Key is per recipient, so a re-run never sends twice.
Styling and plumbing come from waitlist-launch-mail.py, the contact buttons
from release-mail.py.
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

CAMPAIGN = "first-impression-2026-10-18"
SUBJECT = "미래의 나와의 첫 통화, 어떠셨나요?"
SIGN = "nawana 드림"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
MIN_LEFT_S = 300
STORE_LOOKUP = "https://itunes.apple.com/lookup?bundleId=com.roro.futurevoice&country=kr"

# Shown as the second paragraph (update button first, see release-mail.py)
# only to someone whose last app event came from a version older than the
# App Store's current one.
UPDATE = "지금 쓰시는 앱이 이전 버전입니다. 아래 버튼으로 최신 버전으로 업데이트하시면 통화가 훨씬 매끄럽습니다."
UPDATE_BUTTON = "App Store에서 업데이트"

RECIPIENTS = [
    "haeji0211@gmail.com",
    "bbbsonja27@gmail.com",
    "meeja96@gmail.com",
]

BODY = [
    "안녕하세요, 나와나(nawana)입니다.",
    "오늘 가입하시고 미래의 나와 첫 통화까지 해 주셔서 고맙습니다. "
    "내 목소리로 독일어를 하는 나를 처음 만나 보신 느낌, 어떠셨나요?",
    "제가 직접 읽고 다음 업데이트에 반영하겠습니다.",
    "처음 드린 무료 시간이 아직 넉넉하게 남아 있습니다. 오늘 나눈 이야기를 이어서 한 번 더 통화해 보셔도 좋습니다.",
    "답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
]


def body(outdated: bool) -> list[str]:
    return BODY[:1] + [UPDATE] + BODY[1:] if outdated else BODY


def text_body(outdated: bool = False) -> str:
    update = [f"{UPDATE_BUTTON}: {L.APP_STORE_URL}"] if outdated else []
    return "\n\n".join(body(outdated)[:2] + update + body(outdated)[2:] + [f"Threads: {THREADS_URL}\nInstagram DM: {INSTAGRAM_URL}",
                               SIGN, L.SITE_URL])


def html_body(outdated: bool = False) -> str:
    def p(s, top=14):
        return (f'<p style="font-size:16px;line-height:1.7;color:{L.INK};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def b(label, url):
        return (f'<a href="{url}" style="display:inline-block;color:{L.INK};border:1px solid #D9D6CE;'
                f'text-decoration:none;font-size:14px;font-weight:600;padding:9px 16px;'
                f'border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    contact = ('<div style="margin:14px 0 0;">' + b("답장하기", f"mailto:{L.REPLY_TO}")
               + b("Threads", THREADS_URL) + b("인스타그램 DM", INSTAGRAM_URL) + '</div>')
    lines = body(outdated)
    paras = [p(lines[0], top=0)] + [p(s) for s in lines[1:]]
    if outdated:
        paras.insert(2, f'<p style="margin:14px 0 0;"><a href="{L.APP_STORE_URL}" '
                        f'style="display:inline-block;background:{L.BLUE};color:#ffffff;text-decoration:none;'
                        f'font-size:16px;font-weight:600;padding:14px 24px;border-radius:999px;">'
                        f'{html.escape(UPDATE_BUTTON)}</a></p>')
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{L.FONT_FACE}</style></head><body style="margin:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};word-break:keep-all;">
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
          {contact}
          <p style="font-size:15px;color:{L.DIM};margin:28px 0 0;">{html.escape(SIGN)}</p>
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a>
            &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(L.FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def balances() -> dict[str, int]:
    emails = ",".join(L.q(e) for e in RECIPIENTS)
    rows = L.sql(f"""
        select u.email, c.balance
          from auth.users u join user_credits c on c.user_id = u.id
         where u.email in ({emails})""")
    return {r["email"]: r["balance"] for r in rows}


def vtuple(v: str) -> tuple:
    return tuple(int(x) for x in v.split(".") if x.isdigit())


def store_version() -> str:
    with urllib.request.urlopen(STORE_LOOKUP, timeout=20) as resp:
        return json.load(resp)["results"][0]["version"]


def app_versions() -> dict[str, str]:
    """email → version on the learner's most recent client event."""
    emails = ",".join(L.q(e) for e in RECIPIENTS)
    rows = L.sql(f"""
        select distinct on (u.email) u.email, e.properties->>'version' as version
          from auth.users u join client_events e on e.user_id = u.id
         where u.email in ({emails}) and e.properties ? 'version'
         order by u.email, e.created_at desc""")
    return {r["email"]: r["version"] for r in rows}


def send(key: str, to: str, outdated: bool) -> str:
    idem = f"{CAMPAIGN}:{to}"
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO, "subject": SUBJECT,
        "text": text_body(outdated), "html": html_body(outdated),
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
    left = balances()
    ok = {e for e, s in left.items() if s >= MIN_LEFT_S}
    store = store_version()
    seen = app_versions()
    outdated = {e for e, v in seen.items() if vtuple(v) < vtuple(store)}
    print(f"subject: {SUBJECT}\n")
    print(text_body())
    if outdated:
        print("\n--- body for an outdated app\n")
        print(text_body(True))
    print(f"\n--- recipients (App Store {store})")
    for to in RECIPIENTS:
        s = left.get(to)
        v = seen.get(to, "?")
        tag = "  + update button" if to in outdated else ""
        print(f"  {'✓' if to in ok else '✗'} {to}  ({s}s left, app {v}){tag}" if s is not None
              else f"  ✗ {to}  (no credit row)")
    if "--html" in sys.argv:
        for flag in (False, True):
            path = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                f"{CAMPAIGN}{'-update' if flag else ''}.html")
            with open(path, "w") as f:
                f.write(html_body(flag))
            print(f"html preview: {path}")
    if not really:
        print("\ndry run. add --send to send to the ✓ rows.")
        return
    key = L.resend_key()
    for to in RECIPIENTS:
        if to not in ok:
            continue
        print(f"sent {to}: {send(key, to, to in outdated)}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

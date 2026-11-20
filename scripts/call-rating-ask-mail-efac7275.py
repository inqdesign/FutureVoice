#!/usr/bin/env python3
"""Asking a German learner why the calls got three stars (2026-11-17).

Who: efac7275, signed up 2026-11-16, build 1.3.5. In-app review: app 5,
calls 3 ("Mir gefällt die App sehr gut, man hat viel Auswahl um zu lernen").
14 calls over two days, coach mode on, voice slowed to the slowest rung,
spent the 20 free minutes on 11-17 and took the free recharge. No plan.

Copy approved by the founder 2026-11-17 (German, du, no em dash), plus the
question how she found nawana, asked the same day.

  python3 scripts/call-rating-ask-mail-efac7275.py --preview out.html
  python3 scripts/call-rating-ask-mail-efac7275.py            # dry run
  python3 scripts/call-rating-ask-mail-efac7275.py --send     # one try
  python3 scripts/call-rating-ask-mail-efac7275.py --send --wait
      # retries every 30 min while Resend says the daily quota is spent
"""

import argparse
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

CAMPAIGN = "call-rating-ask-efac7275-2026-11-17"
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
USER_ID = "efac7275-fb94-49c6-a4e1-ecfb07227802"

SUBJECT = "Danke für deine Bewertung, kurze Frage zu den Gesprächen"

OPEN = [
    "Hallo Andrea,",
    "ich bin Eunggyu, der Gründer von nawana. Vielen Dank für deine Bewertung! "
    "Es freut mich sehr, dass dir die App gefällt.",
    "Bei den Gesprächen hast du drei Sterne gegeben, und genau da möchte ich besser werden. "
    "Darf ich dich kurz fragen, was dir gefehlt hat?",
]

QUESTIONS = [
    "Was hat dich in den Gesprächen am meisten gestört? Zum Beispiel: wie die Stimme klingt, "
    "das Tempo, die Themen, die Antworten oder dass du nicht richtig verstanden wurdest.",
    "Was müsste anders sein, damit du den Gesprächen fünf Sterne gibst?",
]

MORE = [
    "Und noch eine Frage: Könntest du dir vorstellen, nawana zu abonnieren? "
    "Wenn nicht oder noch nicht, was hält dich davon ab?",
    "Und wie bist du eigentlich auf nawana aufmerksam geworden?",
]

OFFER = ("Ein oder zwei Sätze reichen völlig, antworte einfach auf diese Mail. "
         "Wenn dir das lieber ist, geht auch Threads oder eine Instagram-DM.")

SIGN = ["Viele Grüße", "Eunggyu"]
UNSUB = "Wenn du keine Mails mehr von uns möchtest, antworte einfach kurz darauf."


def text_body() -> str:
    parts = list(OPEN)
    parts.append("\n\n".join(f"{i}. {q}" for i, q in enumerate(QUESTIONS, 1)))
    parts += MORE
    parts.append(f"{OFFER}\n\nAntworten: {L.REPLY_TO}\nThreads: {THREADS_URL}\nInstagram: {INSTAGRAM_URL}")
    parts.append("\n".join(SIGN))
    parts.append(UNSUB)
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, color=L.INK, top=16):
        return (f'<p style="font-size:16px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(OPEN[0], top=0) + "".join(p(s) for s in OPEN[1:])
        + "".join(p(f"{i + 1}. {q}", top=(18 if i == 0 else 12)) for i, q in enumerate(QUESTIONS))
        + "".join(p(s, top=18) for s in MORE)
        + p(OFFER, top=20)
        + '<div style="margin:16px 0 0;">'
        + button("Antworten", f"mailto:{L.REPLY_TO}", True)
        + button("Threads", THREADS_URL, False)
        + button("Instagram-DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(SIGN[0], top=22) + p(SIGN[1], color=L.DIM, top=4)
    )
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;">
            <tr>
              <td style="vertical-align:middle;padding-right:10px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                       style="display:block;width:36px;height:36px;border-radius:9px;">
                </a>
              </td>
              <td style="vertical-align:middle;font-size:17px;font-weight:700;color:{L.INK};">nawana</td>
            </tr>
          </table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def recipient() -> str:
    rows = L.sql(f"""
      select case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
       where u.id = '{USER_ID}' and u.deleted_at is null""")
    if not rows or not L.EMAIL_RE.match(rows[0]["email"] or ""):
        sys.exit("no address")
    return rows[0]["email"]


class Quota(Exception):
    pass


def send(key: str, to: str, idem: str) -> str:
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
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
        body = e.read().decode()[:300]
        if e.code == 429:
            raise Quota(body) from None
        raise RuntimeError(f"{e.code} {body}") from None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    ap.add_argument("--wait", action="store_true", help="retry every 30 min on quota")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"--- subject ---\n{SUBJECT}\n\n--- text ---\n{text_body()}")
        return

    to = recipient()
    print(f"  send  {USER_ID[:8]}  {to}" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return
    key = L.resend_key()
    idem = f"{CAMPAIGN}:{to.lower()}"
    tries = 0
    while True:
        tries += 1
        try:
            print(time.strftime("%F %T"), "sent", send(key, to, idem), flush=True)
            return
        except Quota as e:
            print(time.strftime("%F %T"), f"quota (try {tries}): {e}", flush=True)
            if not args.wait or tries >= 150:
                sys.exit(1)
            time.sleep(1800)


if __name__ == "__main__":
    main()

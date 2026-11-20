#!/usr/bin/env python3
"""Thanking Andrea (efac7275) for subscribing (2026-11-19).

Who: andrea.huber11@gmail.com, German, learning English at A1. Plus monthly
(Apple, EUR) since 2026-11-18, right after the call-rating and slow-speed
mails. Same thread language as those: German, du.

Copy is the founder's to approve (no em dash).

  python3 scripts/thanks-subscriber-mail-efac7275.py --preview out.html
  python3 scripts/thanks-subscriber-mail-efac7275.py            # dry run
  python3 scripts/thanks-subscriber-mail-efac7275.py --send     # after approval
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

CAMPAIGN = "thanks-subscriber-efac7275-2026-11-19"
TO = "andrea.huber11@gmail.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "Danke, Andrea!"

PARAS = [
    "Hallo Andrea,",
    "ich habe gesehen, dass du nawana gestern abonniert hast. Vielen, vielen Dank dafür! "
    "Ich baue nawana fast allein, und deine Unterstützung bedeutet mir wirklich sehr viel.",
    "Ich gebe mein Bestes, damit nawana richtig gut wird und dir beim Englischüben "
    "jeden Tag ein Stück weiterhilft.",
    "Wenn dir etwas auffällt, egal ob gut oder nervig, schreib mir jederzeit. "
    "Antworte einfach auf diese Mail.",
    "Danke noch mal und viel Spaß beim Üben!",
]
SIGN = "Eunggyu"
UNSUB = "Wenn du keine Mails mehr von uns möchtest, antworte einfach kurz darauf."


def text_body() -> str:
    return "\n\n".join(PARAS[:-1] + [
        f"Antworten: {L.REPLY_TO}",
        PARAS[-1], SIGN, UNSUB])


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
        p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:-1])
        + '<div style="margin:16px 0 0;">'
        + button("Antworten", f"mailto:{L.REPLY_TO}", True)
        + '</div>'
        + p(PARAS[-1], top=18) + p(SIGN, color=L.DIM, top=6)
    )
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;"><tr>
            <td style="vertical-align:middle;padding-right:10px;"><a href="{L.SITE_URL}">
              <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                   style="display:block;width:36px;height:36px;border-radius:9px;"></a></td>
            <td style="vertical-align:middle;font-size:17px;font-weight:700;color:{L.INK};">nawana</td>
          </tr></table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a> &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a> &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a> &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO,
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
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    if args.preview:
        open(args.preview, "w").write(html_body())
    print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key()))


if __name__ == "__main__":
    main()

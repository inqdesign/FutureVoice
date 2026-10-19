#!/usr/bin/env python3
"""Thanking a learner who invited two friends, and asking how it's going (2026-10-13).

Who: 622135cd (Apple relay 5t8p7h75nj@privaterelay.appleid.com, English
native, learning German, ~15 min talked). Invited whitney426 (10-08) and
yoon951028 (10-12). No subscription. The same person wrote about shadowing
from a Hide My Email address (scripts/shadowing-help-mail-622135cd.py); this
continues that thread at the same address (2026-10-13 founder: "대화를
이어간다는 느낌으로"). Shadow coach calls on 10-12 suggest it now works.

Copy is the founder's to approve (English, no em dash).

  python3 scripts/thanks-inviter-mail-622135cd.py --preview out.html
  python3 scripts/thanks-inviter-mail-622135cd.py            # dry run
  python3 scripts/thanks-inviter-mail-622135cd.py --send     # after approval
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

CAMPAIGN = "thanks-inviter-622135cd-2026-10-13"
TO = "uses.lever-23@icloud.com"   # the address they wrote from: same thread

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "Re: Shadowing attempts not being saved"

PARAS = [
    "Hi,",
    "Just following up on shadowing. Did the video help, and are your attempts "
    "being saved now? If it's still acting up, tell me what you see and I'll keep digging.",
    "Also, thank you for inviting your friends. Two of them have joined, and a "
    "recommendation from someone who actually uses the app means a lot to me.",
    "How is the rest of it going? If anything feels awkward, gets in your way, or you "
    "wish worked differently, I'd love to hear it. nawana is less than a month old and "
    "I'm building it on my own, so anything you tell me, big or small, I'll put to use right away.",
    "Just reply here, or reach me on Threads or Instagram DM if that's easier. "
    "I'm really glad we're in touch.",
    "Thanks again.",
]
SIGN = "Eunggyu"
UNSUB = "If you'd rather not get mail from me, just reply and let me know."


def text_body() -> str:
    return "\n\n".join(PARAS[:-1] + [
        f"Reply: {L.REPLY_TO}\nThreads: {THREADS_URL}\nInstagram DM: {INSTAGRAM_URL}",
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
        + button("Reply", f"mailto:{L.REPLY_TO}", True)
        + button("Threads", THREADS_URL, False)
        + button("Instagram DM", INSTAGRAM_URL, False)
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

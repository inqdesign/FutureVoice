#!/usr/bin/env python3
"""Shadowing attempts not saving: reply with a how-to video (2026-10-12).

Who: 622135cd (German learner, Hide My Email; wrote from
uses.lever-23@icloud.com). 40 takes started since 10-07, 36 cancelled by the
✕ mid-take, so nothing past the first line was ever scored. The founder's
screen recording (~/Desktop/IMG_2730.mp4) shows the take finishing on its own.

Copy is the founder's to approve (English, no em dash).

  python3 scripts/shadowing-help-mail-622135cd.py            # dry run
  python3 scripts/shadowing-help-mail-622135cd.py --send     # after approval
"""

import argparse
import base64
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

CAMPAIGN = "shadowing-help-622135cd-2026-10-12"
TO = "uses.lever-23@icloud.com"
VIDEO = os.path.expanduser("~/Desktop/IMG_2730.mp4")

SUBJECT = "Re: Shadowing attempts not being saved"

PARAS = [
    "Hi,",
    "Thank you so much for writing to us. Your email address is hidden, so we can "
    "guess which account might be yours but can't know for sure. Either way, it means "
    "a lot that you took the time to tell us, and that you're learning German with nawana.",
    "I'm sorry, we haven't been able to pin down exactly what's going wrong yet. "
    "I recorded a quick video showing how shadowing is meant to work, so please take a look.",
    "Tap the microphone button to start, wait for the countdown, and then start speaking. "
    "When you've finished the sentence, don't tap anything. Just wait a moment and the app "
    "will score your attempt by itself.",
    "Only tap the ✕ button if you want to stop partway through. It cancels the attempt, "
    "so nothing gets saved.",
    "If it still doesn't work, could you send us a screenshot of what you see? "
    "That would help us a lot.",
    "And if anything else feels awkward or could be better, please don't hesitate "
    "to write to us anytime. Every note like yours helps us make nawana better.",
    "Thank you!",
]
SIGN = "Eunggyu, nawana"


def attachments() -> list[dict]:
    with open(VIDEO, "rb") as f:
        return [{"filename": "nawana-shadowing.mp4",
                 "content": base64.b64encode(f.read()).decode()}]


def text_body() -> str:
    return "\n\n".join(PARAS + [SIGN])


def html_body() -> str:
    ps = "".join(
        f'<p style="font-size:16px;line-height:1.7;color:#111;margin:{0 if i == 0 else 16}px 0 0;">'
        f'{html.escape(s).replace(chr(10), "<br>")}</p>'
        for i, s in enumerate(PARAS + [SIGN]))
    return f'<div style="font-family:-apple-system,sans-serif;max-width:560px;">{ps}</div>'


def send(key: str, files: list[dict]) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
        "attachments": files,
        "headers": {"X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    files = attachments()
    size = sum(len(f["content"]) for f in files) * 3 // 4
    print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\nattach   "
          + ", ".join(f["filename"] for f in files) + f"  ({size / 1e6:.1f} MB)\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key(), files))


if __name__ == "__main__":
    main()

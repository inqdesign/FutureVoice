#!/usr/bin/env python3
"""E or S: which voice is Olivia (2026-10-12).

Who: 1f5c04ca (Olivia Ha, forsgappstore@gmail.com, app language ko). Six
takes of her voice in ~/Downloads/Olivia_Test — three E, three S — attached,
asking which she likes and which sounds like the self she wants to be.

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/olivia-voice-ab-mail.py            # dry run
  python3 scripts/olivia-voice-ab-mail.py --send     # after approval
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

CAMPAIGN = "olivia-voice-ab-2026-10-12"
TO = "forsgappstore@gmail.com"
FOLDER = os.path.expanduser("~/Downloads/Olivia_Test")

SUBJECT = "올리비아님 목소리, 두 가지 버전을 들어봐 주세요"

PARAS = [
    "안녕하세요, 올리비아님.",
    "올리비아님 목소리로 두 가지 버전을 만들어 보았습니다.\n"
    "E 버전과 S 버전, 각각 세 개씩 파일을 첨부했습니다.",
    "들어 보시고 어느 쪽이 더 좋은지 알려 주세요.\n"
    "· 듣기에 어떤 느낌인지\n"
    "· 어느 쪽이 되고 싶은 내 모습에 더 가까운지\n"
    "· 어느 쪽이 더 나 같은 목소리인지\n"
    "· 어느 쪽이 더 듣기 좋은지",
    "짧게라도 답장 주시면 큰 도움이 됩니다. 고맙습니다.",
]
SIGN = "이응규 드림"


def attachments() -> list[dict]:
    out = []
    for name in sorted(os.listdir(FOLDER)):
        if name.startswith(".") or not name.lower().endswith((".mp3", ".wav")):
            continue
        with open(os.path.join(FOLDER, name), "rb") as f:
            out.append({"filename": name, "content": base64.b64encode(f.read()).decode()})
    return out


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
    print(f"to       {TO}\nsubject  {SUBJECT}\nattach   "
          + ", ".join(f["filename"] for f in files) + f"  ({size / 1e6:.1f} MB)\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key(), files))


if __name__ == "__main__":
    main()

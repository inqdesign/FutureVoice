#!/usr/bin/env python3
"""The update she was waiting for is out (2026-10-11).

Who: 8b6bb9c6 (the first Japanese learner), who replied from
moeka.1224@ezweb.ne.jp. The founder's earlier reply promised 20 more minutes
(granted: balance 1200 s) and a mail once the next version shipped (1.1.6).
Copy approved by the founder in this session.

  python3 scripts/japanese-user-update-mail.py --preview out.html
  python3 scripts/japanese-user-update-mail.py            # dry run
  python3 scripts/japanese-user-update-mail.py --send     # after approval
"""

import argparse
import html
import importlib.util
import os

_here = os.path.dirname(os.path.abspath(__file__))


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_here, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


L = _load("launch_mail", "waitlist-launch-mail.py")
J = _load("first_ja", "first-japanese-user-mail.py")

CAMPAIGN = "japanese-user-update-2026-10-11"
TO = "moeka.1224@ezweb.ne.jp"

SUBJECT = "新しいバージョンが出ました"

PARAS = [
    "こんにちは😊",
    "お待たせしました！\n前回お話しした新しいバージョンがリリースされました。\n"
    "App Storeでアップデートしていただければ、すぐに使えます。",
    "・話すスピードは、設定から自分に合う速さに変えられます\n"
    "・コーチモードをオンにすると、次に何を言えばいいか例を出してくれるので、"
    "それを真似するところから始めてみてください",
    "プレゼントした20分も、もう使えるようになっています。\n"
    "時間は気にせず、思いきりたくさん話してみてくださいね。",
    "声の仕上がりが気になる場合は、静かな場所で録音し直すとかなり変わるので、"
    "よかったら試してみてください。",
    "使ってみて気づいたことがあれば、またいつでも教えてください。\n"
    "楽しんでもらえたら嬉しいです！",
]


def text_body() -> str:
    return "\n\n".join(PARAS + [J.SIGN, L.APP_STORE_URL, J.UNSUB])


def html_body() -> str:
    full = J.html_body()
    def p(s, top=16, color=L.INK):
        return (f'<p style="font-size:16px;font-weight:400;line-height:1.7;color:{color};'
                f'margin:{top}px 0 0;">{html.escape(s).replace(chr(10), "<br>")}</p>')
    body = "".join(p(s, top=(0 if i == 0 else 16)) for i, s in enumerate(PARAS)) + p(J.SIGN, 18, L.DIM)
    # Reuse the earlier letter's frame: swap its body for this one.
    start = full.index(J.html_body.__globals__["html"].escape(J.OPEN[0])[:20])
    start = full.rfind("<p", 0, start)
    end = full.index('<div style="margin-top:32px')
    return full[:start] + body + "\n          " + full[end:]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    J.SUBJECT = SUBJECT
    J.text_body = text_body
    J.html_body_orig = J.html_body
    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"wrote {args.preview}\n\n{SUBJECT}\n\n{text_body()}")
        return
    print(f"  send  {TO}" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return
    hb = html_body()
    J.html_body = lambda: hb
    print("  sent ", J.send(L.resend_key(), TO, f"{CAMPAIGN}:{TO}"))


if __name__ == "__main__":
    main()

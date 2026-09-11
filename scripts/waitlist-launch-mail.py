#!/usr/bin/env python3
"""Tell the waitlist that nawana is on the App Store — once each, via Resend.

Run from the repo root:

  python3 scripts/waitlist-launch-mail.py --dry-run           # who would get it
  python3 scripts/waitlist-launch-mail.py --preview out.html  # render the mail
  python3 scripts/waitlist-launch-mail.py --test me@x.com     # one real send, no DB stamp
  python3 scripts/waitlist-launch-mail.py                     # send to everyone unnotified
  python3 scripts/waitlist-launch-mail.py --limit 5           # …a few at a time

Who: every `public.waitlist` row with `notified_at IS NULL`, oldest first.
`notified_at` is stamped per row right after Resend accepts the message, so a
re-run only reaches the people the last run didn't — never the same person
twice. Resend's idempotency key is the waitlist row id for the same reason.

How: Resend REST API, from hello@nawana.app (the domain must be Verified in
Resend first — receiving stays on Cloudflare Email Routing, sending is
Resend's, the two don't touch the same DNS names). Key from the environment
(RESEND_API_KEY) or the keychain (`security add-generic-password -s "Resend
nawana" -a resend -w`). Supabase Management API token from the keychain, same
as scripts/apple-web-signin.py.

Copy is bilingual — Korean first (the list came mostly from Threads), then
English — because the row carries no language and guessing from the mail
domain is wrong often enough to embarrass. Rows that asked for the beta get one
extra line owning up to the invite that never went out.
"""

import argparse
import base64
import html
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
FROM = "nawana <hello@nawana.app>"
REPLY_TO = "hello@nawana.app"
APP_STORE_URL = "https://apps.apple.com/app/id6792794655"
SITE_URL = "https://nawana.app"
CAMPAIGN = "waitlist-launch-2026-09"
SUBJECT = "nawana is on the App Store · App Store에 나왔어요"
PER_SEND_PAUSE = 0.6  # Resend allows 2 req/s

# --------------------------------------------------------------------------
# Copy. Korean is written, not translated (해요체, no 당신); English follows.
# --------------------------------------------------------------------------

KO_PARAS = [
    "안녕하세요, nawana예요.",
    "기다려 주셔서 고마워요. nawana가 App Store에 나왔어요.",
    "목소리를 한 번 복제하면, 그 목소리로 유창하게 말하는 미래의 나와 통화하면서 언어를 배워요. "
    "매일 정해 둔 시간에 전화가 걸려와요.",
]
KO_BETA = "베타 초대를 먼저 보내드리기로 했는데 결국 못 보냈어요. 미안해요. 출시 버전으로 바로 만나요."
KO_CTA = "App Store에서 받기"
KO_TAIL = "써 보고 한마디 남기고 싶으면 이 메일에 답장하면 돼요. 직접 읽어요."
KO_UNSUB = "더 받고 싶지 않으면 답장으로 알려 주세요."

EN_PARAS = [
    "Hi, this is nawana.",
    "Thanks for waiting — nawana is on the App Store.",
    "Clone your voice once, then learn a language by talking with your fluent self, "
    "in your own voice. It calls you every day at a time you pick.",
]
EN_BETA = "We promised a beta invite first and never sent one. Sorry about that — here's the real thing instead."
EN_CTA = "Get it on the App Store"
EN_TAIL = "Try it, and if you have a thought, just reply to this email. A person reads it."
EN_UNSUB = "Don't want more mail from us? Reply and say so."

SIGN = "— nawana"
FOOTER = "Dear RoRo · Munich"


def text_body(beta: bool) -> str:
    ko = list(KO_PARAS) + ([KO_BETA] if beta else []) + [f"{KO_CTA}: {APP_STORE_URL}", KO_TAIL, KO_UNSUB]
    en = list(EN_PARAS) + ([EN_BETA] if beta else []) + [f"{EN_CTA}: {APP_STORE_URL}", EN_TAIL, EN_UNSUB]
    return "\n\n".join(ko + ["— · —"] + en + [SIGN, SITE_URL])


def html_body(beta: bool) -> str:
    def p(s, color="#3a332e", top=14):
        return (f'<p style="font-size:15.5px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def cta(label):
        return (f'<p style="margin:26px 0 0;"><a href="{APP_STORE_URL}" '
                f'style="display:inline-block;background:#1c1814;color:#ffffff;text-decoration:none;'
                f'font-size:15px;font-weight:600;padding:12px 20px;border-radius:8px;">'
                f'{html.escape(label)} &rarr;</a></p>')

    def block(paras, beta_line, cta_label, tail, unsub):
        out = [p(paras[0], top=0)] + [p(s) for s in paras[1:]]
        if beta:
            out.append(p(beta_line))
        out.append(cta(cta_label))
        out.append(p(tail, top=26))
        out.append(p(unsub, color="#8a7c6d", top=10))
        return "".join(out)

    divider = '<div style="margin:34px 0 30px;border-top:1px solid #ececE6;"></div>'
    return f"""<!doctype html><html><body style="margin:0;background:#f4f3ef;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f3ef;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px;background:#ffffff;border:1px solid #e6e4dd;">
        <tr><td style="padding:36px 34px;font-family:Helvetica,Arial,sans-serif;color:#1c1814;">
          <div style="font-size:22px;font-weight:700;letter-spacing:-.01em;">nawana</div>
          <div style="font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#8a7c6d;margin:6px 0 26px;">Now on the App Store</div>
          {block(KO_PARAS, KO_BETA, KO_CTA, KO_TAIL, KO_UNSUB)}
          {divider}
          {block(EN_PARAS, EN_BETA, EN_CTA, EN_TAIL, EN_UNSUB)}
          <div style="margin-top:30px;padding-top:20px;border-top:1px solid #ececE6;">
            <div style="font-size:14px;color:#3a332e;">{html.escape(SIGN)}</div>
            <a href="{SITE_URL}" style="font-size:13px;color:#1c1814;text-decoration:none;">nawana.app &rarr;</a>
          </div>
        </td></tr>
      </table>
      <div style="font-family:Helvetica,Arial,sans-serif;font-size:11px;color:#a89f92;margin-top:16px;">{html.escape(FOOTER)}</div>
    </td></tr>
  </table></body></html>"""


# --------------------------------------------------------------------------
# Plumbing.
# --------------------------------------------------------------------------

def keychain(service: str, account: str | None = None) -> str | None:
    cmd = ["security", "find-generic-password", "-s", service, "-w"]
    if account:
        cmd[3:3] = ["-a", account]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    raw = r.stdout.strip()
    if raw.startswith("go-keyring-base64:"):
        raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
    return raw or None


def supabase_token() -> str:
    tok = keychain("Supabase CLI")
    if not tok:
        sys.exit("no Supabase CLI token in the keychain — run `supabase login` first")
    return tok


def sql(query: str) -> list[dict]:
    body = json.dumps({"query": query}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/database/query",
        data=body, method="POST")
    req.add_header("Authorization", f"Bearer {supabase_token()}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # urllib's default UA is 403'd
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def resend_key() -> str:
    import os
    key = os.environ.get("RESEND_API_KEY") or keychain("Resend nawana")
    if not key:
        sys.exit("no Resend key: export RESEND_API_KEY=… or "
                 "`security add-generic-password -s \"Resend nawana\" -a resend -w`")
    return key


def send(key: str, to: str, beta: bool, idem: str) -> str:
    payload = {
        "from": FROM,
        "to": [to],
        "reply_to": REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(beta),
        "html": html_body(beta),
        "headers": {
            "List-Unsubscribe": f"<mailto:{REPLY_TO}?subject=unsubscribe>",
            "X-Entity-Ref-ID": idem,
        },
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")  # api.resend.com's WAF 1010s urllib's default
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def pending(limit: int | None) -> list[dict]:
    q = ("select id, email, wants_beta, created_at::date as joined from public.waitlist "
         "where notified_at is null order by created_at")
    if limit:
        q += f" limit {int(limit)}"
    return sql(q)


def stamp(row_id: str) -> None:
    sql(f"update public.waitlist set notified_at = now() where id = '{row_id}' and notified_at is null")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="list recipients, send nothing")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML (beta variant) to FILE and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL; touches no DB row")
    ap.add_argument("--limit", type=int, help="send to at most N unnotified rows")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body(beta=True))
        print(f"wrote {args.preview}\n\n--- text variant ---\n{text_body(beta=True)}")
        return

    if args.test:
        mid = send(resend_key(), args.test, beta=True, idem=f"{CAMPAIGN}:test:{int(time.time())}")
        print(f"sent test to {args.test}: {mid}")
        return

    rows = pending(args.limit)
    print(f"{len(rows)} unnotified" + (f" (limit {args.limit})" if args.limit else ""))
    for r in rows:
        print(f"  {r['joined']}  {'beta ' if r['wants_beta'] else '     '} {r['email']}")
    if args.dry_run or not rows:
        return

    key = resend_key()
    ok = failed = 0
    for r in rows:
        try:
            mid = send(key, r["email"], bool(r["wants_beta"]), idem=f"{CAMPAIGN}:{r['id']}")
        except Exception as e:  # keep going — one bad address must not stop the rest
            failed += 1
            print(f"  FAIL {r['email']}: {e}")
            continue
        stamp(r["id"])
        ok += 1
        print(f"  sent {r['email']}  {mid}")
        time.sleep(PER_SEND_PAUSE)
    print(f"\n{ok} sent, {failed} failed; re-run to retry the failures")


if __name__ == "__main__":
    main()

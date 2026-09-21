#!/usr/bin/env python3
"""Update mail: please move to the current App Store build.

Run from the repo root:

  python3 scripts/update-mail.py --dry-run             # who gets it
  python3 scripts/update-mail.py --preview out.html    # render
  python3 scripts/update-mail.py --test me@x.com       # one real send, no list
  python3 scripts/update-mail.py --limit 3             # a few at a time
  python3 scripts/update-mail.py                       # everyone
  python3 scripts/update-mail.py --to a@x.com b@y.com  # named people only

Who: every signed-in account with a reachable address — the sign-in email
unless it is an Apple private relay (Resend cannot reach those), in which case
the waitlist address it was mapped to, if any. Our own accounts (founder,
Android dev, the App Review demo login) are left out. `--only-old` narrows it
to accounts whose last client event named a build below the App Store's
`app_release.latest_build`; accounts that have sent no event at all are kept,
since a silent install is exactly the one that is probably old.

Why a mail at all: the in-app update sheet is optional (`min_build` is 0) and
is shown ONCE per build, so someone who tapped past it on the day stays on
the old build for as long as they like. Two days after 1.0.4 (50) most active
testers were still on 44 / 46.

Record: nothing is written to the DB. Resend's Idempotency-Key is
`<campaign>:<email>`, so a re-run inside 24 h cannot mail anyone twice; the
campaign tag makes the send visible in Resend's dashboard afterwards.

Copy is bilingual — Korean first, formal (합니다체: a letter from the founder,
not app chrome), then English. Plumbing (keychain, SQL, Resend) is borrowed
from waitlist-launch-mail.py.
"""

import argparse
import html
import importlib.util
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("launch_mail", os.path.join(HERE, "waitlist-launch-mail.py"))
launch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(launch)

sql, q, resend_key = launch.sql, launch.q, launch.resend_key
FROM, REPLY_TO, SITE_URL = launch.FROM, launch.REPLY_TO, launch.SITE_URL
APP_STORE_URL, RELAY, EMAIL_RE = launch.APP_STORE_URL, launch.RELAY, launch.EMAIL_RE
INK, PAPER, SURF, DIM, FAINT, BLUE = launch.INK, launch.PAPER, launch.SURF, launch.DIM, launch.FAINT, launch.BLUE
FONT, MONO, FONT_FACE, LOGO_URL = launch.FONT, launch.MONO, launch.FONT_FACE, launch.LOGO_URL
SIGN, FOOTER, TAGLINE, PER_SEND_PAUSE = launch.SIGN, launch.FOOTER, launch.TAGLINE, launch.PER_SEND_PAUSE

CAMPAIGN = "update-2026-09-16"
# Accounts that are ours, not learners.
OURS = {"eunggyu.lee@gmail.com", "android-dev-test@dearroro.dev", "forsgappstore@gmail.com"}


# --------------------------------------------------------------------------
# Copy. Edit here. {version} is filled from app_release.
# --------------------------------------------------------------------------

SUBJECT = "나와나 최신 버전({version})으로 업데이트해 주세요 · Please update nawana to {version}"

KO = [
    "안녕하세요, 나와나(nawana)입니다.",
    "지금 쓰고 계신 나와나가 예전 버전일 가능성이 높아 메일을 드립니다. "
    "통화가 중간에 끊기거나 목소리가 나오지 않던 문제를 비롯해 그동안 알려 주신 여러 문제를 고친 "
    "새 버전({version})이 App Store에 올라가 있습니다. 예전 버전에서는 이미 고친 문제를 그대로 겪으시게 됩니다.",
    "아래 버튼을 누르면 App Store의 나와나 페이지가 열립니다. 「업데이트」 버튼이 보이면 눌러 주세요. "
    "「열기」만 보인다면 이미 최신 버전이니 그대로 쓰시면 됩니다.",
]
KO_CTA = "App Store에서 업데이트"
KO_AUTO = (
    "앞으로는 자동으로 받으실 수 있습니다. iPhone의 설정 → App Store → 「앱 업데이트」를 켜 두시면 "
    "새 버전이 나올 때마다 알아서 설치됩니다."
)
KO_TAIL = "불편을 드려 죄송합니다. 업데이트 후에도 이상한 점이 있으면 이 메일에 답장해 주세요. 제가 직접 읽습니다."
KO_UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."

EN = [
    "Hello, this is nawana.",
    "I am writing because the nawana on your phone is most likely an older version. "
    "A new one ({version}) is on the App Store, and it fixes calls that dropped mid-way or went silent, "
    "along with several other problems you reported. On the old version you keep running into things that are already fixed.",
    "Tap the button below to open nawana's page on the App Store. If you see an “Update” button, tap it. "
    "If it only says “Open”, you are already on the latest version.",
]
EN_CTA = "Update on the App Store"
EN_AUTO = (
    "You can also let it happen by itself: on your iPhone, go to Settings → App Store and turn on “App Updates”, "
    "and every new version installs on its own."
)
EN_TAIL = "Sorry for the trouble. If anything still looks wrong after updating, just reply to this email. I read every one myself."
EN_UNSUB = "If you would rather not receive more mail from us, reply and let me know."


def text_body(version: str) -> str:
    ko = [s.format(version=version) for s in KO] + [f"{KO_CTA}\n{APP_STORE_URL}", KO_AUTO, KO_TAIL, KO_UNSUB]
    en = [s.format(version=version) for s in EN] + [f"{EN_CTA}\n{APP_STORE_URL}", EN_AUTO, EN_TAIL, EN_UNSUB]
    return "\n\n".join(ko + ["— · —"] + en + [SIGN, SITE_URL])


def html_body(version: str) -> str:
    def p(s, color=INK, top=14, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def cta(label):
        return (f'<p style="margin:22px 0 0;"><a href="{APP_STORE_URL}" '
                f'style="display:inline-block;background:{BLUE};color:#ffffff;text-decoration:none;'
                f'font-size:15px;font-weight:600;padding:12px 20px;border-radius:999px;">{html.escape(label)}</a></p>')

    def block(paras, cta_label, auto, tail, unsub):
        out = [p(paras[0].format(version=version), top=0)] + [p(s.format(version=version)) for s in paras[1:]]
        out.append(cta(cta_label))
        out.append(p(auto, color=DIM, top=18, size="14px"))
        out.append(p(tail, top=24))
        out.append(p(unsub, color=FAINT, top=10, size="13px"))
        return "".join(out)

    ko = block(KO, KO_CTA, KO_AUTO, KO_TAIL, KO_UNSUB)
    en = block(EN, EN_CTA, EN_AUTO, EN_TAIL, EN_UNSUB)
    divider = f'<div style="margin:36px 0 32px;border-top:1px solid {SURF};"></div>'
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{FONT_FACE}</style></head><body style="margin:0;background:{PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr><td style="font-family:{FONT};color:{INK};">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{SITE_URL}" style="text-decoration:none;">
                  <img src="{LOGO_URL}" width="52" height="52" alt="nawana"
                       style="display:block;width:52px;height:52px;border-radius:13px;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:21px;font-weight:700;letter-spacing:-.01em;color:{INK};">nawana</div>
                <div style="font-size:12px;color:{FAINT};margin-top:3px;font-family:{MONO};">{html.escape(TAGLINE)}</div>
              </td>
            </tr>
          </table>
          {ko}
          {divider}
          {en}
          <p style="font-size:15px;color:{DIM};margin:32px 0 0;">{html.escape(SIGN)}</p>
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {SURF};font-size:12px;line-height:1.7;color:{FAINT};">
            <a href="{SITE_URL}" style="color:{FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{APP_STORE_URL}" style="color:{FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{REPLY_TO}" style="color:{FAINT};text-decoration:none;">{REPLY_TO}</a>
            <br>{html.escape(FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


# --------------------------------------------------------------------------
# Recipients and sending.
# --------------------------------------------------------------------------

RECIPIENTS_SQL = f"""
with last as (
  select user_id,
         max(created_at) as seen,
         (array_agg(properties->>'build' order by created_at desc) filter (where properties ? 'build'))[1] as build
    from client_events
   where created_at > now() - interval '30 days'
   group by user_id
)
select u.id::text as user_id,
       case when u.email like '%{RELAY}' then m.waitlist_email else u.email end as email,
       l.seen::date::text as last_seen,
       l.build
  from auth.users u
  left join user_waitlist_mapping m on m.user_id = u.id
  left join last l on l.user_id = u.id
 where u.deleted_at is null
   and not u.is_anonymous
   and u.email is not null
 order by l.seen desc nulls last, u.created_at
"""


def latest() -> tuple[int, str]:
    row = sql("select latest_build, latest_version from app_release where platform = 'ios'")[0]
    return int(row["latest_build"]), row["latest_version"]


def send(key: str, to: str, version: str, idem: str) -> str:
    payload = {
        "from": FROM,
        "to": [to],
        "reply_to": REPLY_TO,
        "subject": SUBJECT.format(version=version),
        "text": text_body(version),
        "html": html_body(version),
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
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="plan only: nothing sent")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL; touches no list")
    ap.add_argument("--limit", type=int, help="send to at most N people")
    ap.add_argument("--to", nargs="+", metavar="EMAIL", help="only these addresses (must be in the list)")
    ap.add_argument("--only-old", action="store_true",
                    help="skip accounts whose last event already named the current build")
    ap.add_argument("--version", help="override the version printed (default: app_release)")
    args = ap.parse_args()

    if args.preview:
        v = args.version or "1.0.x"
        with open(args.preview, "w") as f:
            f.write(html_body(v))
        print(f"wrote {args.preview}\n\n--- text variant ---\n{text_body(v)}")
        return

    build, version = latest()
    version = args.version or version

    if args.test:
        mid = send(resend_key(), args.test, version, idem=f"{CAMPAIGN}:test:{int(time.time())}")
        print(f"sent test to {args.test}: {mid}")
        return

    plan, skipped = [], []
    wanted = {e.lower() for e in args.to} if args.to else None
    for r in sql(RECIPIENTS_SQL):
        email = r["email"]
        if not email:
            skipped.append((r["user_id"][:8] + "… (relay, no waitlist address)", "unreachable"))
            continue
        if email.lower() in OURS:
            skipped.append((email, "ours"))
            continue
        if not EMAIL_RE.match(email):
            skipped.append((email, "invalid address"))
            continue
        if wanted is not None and email.lower() not in wanted:
            continue
        if args.only_old and r["build"] and int(r["build"]) >= build:
            skipped.append((email, f"already on {r['build']}"))
            continue
        plan.append(r)
    if wanted:
        missing = wanted - {r["email"].lower() for r in plan}
        for e in sorted(missing):
            skipped.append((e, "not in the list"))
    if args.limit:
        plan = plan[:args.limit]

    print(f"App Store: {version} ({build})")
    print(f"{len(plan)} to send" + (f" (limit {args.limit})" if args.limit else "") + f", {len(skipped)} skipped"
          + ("   DRY RUN" if args.dry_run else ""))
    for who, why in skipped:
        print(f"  skip  {who:45} {why}")
    for r in plan:
        print(f"  send  {r['email']:45} last seen {r['last_seen'] or '—':10} build {r['build'] or '?'}")
    if args.dry_run or not plan:
        return

    key = resend_key()
    ok = failed = 0
    for r in plan:
        try:
            mid = send(key, r["email"], version, idem=f"{CAMPAIGN}:{r['email'].lower()}")
        except Exception as e:  # one bad address must not stop the rest
            failed += 1
            print(f"  FAIL {r['email']}: {e}")
            continue
        ok += 1
        print(f"  sent {r['email']}  {mid}")
        time.sleep(PER_SEND_PAUSE)
    print(f"\n{ok} sent, {failed} failed; a re-run within 24 h cannot double-send (Idempotency-Key)")


if __name__ == "__main__":
    main()

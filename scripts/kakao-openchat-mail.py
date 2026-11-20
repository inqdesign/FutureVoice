#!/usr/bin/env python3
"""Invite recent Korean learners to the KakaoTalk open chat (2026-11-05).

Who: accounts that used the app in the last `--days` (30) days, whose app
language is Korean (`device_tokens.app_language`, newest row), at their
sign-in address (an Apple relay is delivered: nawana.app is registered as a
relay sender since 2026-09-21; a mapped waitlist address is preferred). Our own accounts are left out. Android installs register no
device token, so they have no app language; they are all included (the
testers are Korean) except SKIP. `--no-android` leaves them out.

  python3 scripts/kakao-openchat-mail.py                 # dry run: list + text
  python3 scripts/kakao-openchat-mail.py --preview x.html
  python3 scripts/kakao-openchat-mail.py --test me@x.com # one real send
  python3 scripts/kakao-openchat-mail.py --send          # everyone in the list

Resend's Idempotency-Key is `<campaign>:<email>`, so a re-run inside 24 h
cannot mail anyone twice. Sends are logged to ~/.nawana/mail-logs/.
"""

import argparse
import datetime
import html
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("update_mail", os.path.join(HERE, "update-mail.py"))
upd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(upd)

CAMPAIGN = "kakao-openchat-2026-11-05"
OPENCHAT_URL = "https://open.kakao.com/o/gcRTBBVi"
KAKAO_YELLOW = "#FEE500"
# Android installs have no app language. Every Android tester is Korean except
# oathrek (sent the English tester invite); nawana.review is our own account.
SKIP = {"oathrek@gmail.com", "nawana.review@gmail.com"}

SUBJECT = "나와나 카카오톡 오픈채팅방을 열었습니다"

PARAS = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "나와나 유저분들에게 직접적으로, 많은 분들에게 연락을 드릴 방법이 있음 좋겠다는 생각에 "
    "오픈채팅방을 열었습니다.",
    "최신 소식과 제가 하고 있는 작업들, 여러 공지사항들을 받아 보실 수 있답니다. "
    "부담 없이 들르셔서, 소통하면서 더 언어를 공부하실 수 있으셨음 좋겠어요!",
    "열심히 하시는 분들이 많아서, 서로 좋은 영향이 되면 또 의미가 있을 것 같습니다!",
]
CTA = "오픈채팅방 들어가기"
SIGN = "나와나 이응규 드림"


def text_body() -> str:
    return "\n\n".join(PARAS + [f"{CTA}\n{OPENCHAT_URL}", SIGN])


def html_body() -> str:
    def p(s, top=16, color="#111", size="16px"):
        return (f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    cta = (f'<p style="margin:24px 0 0;"><a href="{OPENCHAT_URL}" style="display:inline-block;'
           f'background:{KAKAO_YELLOW};color:#191919;text-decoration:none;font-size:16px;font-weight:700;'
           f'padding:14px 24px;border-radius:999px;">{html.escape(CTA)}</a></p>')
    body = p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:]) + cta + p(SIGN, top=24, color="#666")
    footer = (f'<div style="margin-top:32px;padding-top:14px;border-top:1px solid #eee;'
              f'font-size:12px;line-height:1.7;color:#999;">'
              f'<a href="{upd.SITE_URL}" style="color:#999;text-decoration:none;">nawana.app</a></div>')
    return (f'<div style="font-family:-apple-system,sans-serif;max-width:560px;word-break:keep-all;">'
            f'{body}{footer}</div>')


def recipients(days: int, include_android: bool) -> list:
    lang_clause = "(g.app_language = 'ko'" + (" or l.platform = 'android')" if include_android else ")")
    return upd.sql(f"""
with last as (
  select user_id, max(created_at) as seen,
         (array_agg(coalesce(properties->>'platform', 'ios') order by created_at desc))[1] as platform
    from client_events
   where created_at > now() - interval '{int(days)} days'
   group by user_id
), lang as (
  select distinct on (user_id) user_id, app_language
    from device_tokens order by user_id, updated_at desc
)
select u.id::text as user_id,
       case when u.email like '%{upd.RELAY}' then coalesce(m.waitlist_email, u.email) else u.email end as email,
       l.seen::date::text as last_seen, l.platform, g.app_language
  from last l
  join auth.users u on u.id = l.user_id
  left join lang g on g.user_id = l.user_id
  left join user_waitlist_mapping m on m.user_id = u.id
 where u.deleted_at is null and not u.is_anonymous and u.email is not null
   and {lang_clause}
 order by l.seen desc
""")


def send(key: str, to: str, idem: str) -> str:
    payload = {
        "from": upd.FROM, "to": [to], "reply_to": upd.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
        "headers": {"List-Unsubscribe": f"<mailto:{upd.REPLY_TO}?subject=unsubscribe>",
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
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--send", action="store_true", help="actually send (default: dry run)")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL; touches no list")
    ap.add_argument("--days", type=int, default=30, help="used the app within this many days (default 30)")
    ap.add_argument("--no-android", action="store_true", help="leave out Android users")
    ap.add_argument("--limit", type=int, help="send to at most N people")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"wrote {args.preview}")
        return
    if args.test:
        print("sent test:", send(upd.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}"))
        return

    plan, skipped = [], []
    for r in recipients(args.days, not args.no_android):
        email = r["email"]
        if not email:
            skipped.append((r["user_id"][:8] + "… (relay, no waitlist address)", "unreachable"))
        elif email.lower() in upd.OURS or email.lower() in SKIP:
            skipped.append((email, "ours"))
        elif not upd.EMAIL_RE.match(email):
            skipped.append((email, "invalid address"))
        else:
            plan.append(r)
    if args.limit:
        plan = plan[:args.limit]

    print(f"subject  {SUBJECT}\n\n{text_body()}\n")
    print(f"used the app in the last {args.days} days, app language ko"
          + ("" if args.no_android else " + Android"))
    print(f"{len(plan)} to send, {len(skipped)} skipped" + ("" if args.send else "   DRY RUN"))
    for who, why in skipped:
        print(f"  skip  {who:45} {why}")
    for r in plan:
        print(f"  send  {r['email']:45} last seen {r['last_seen']}  {r['platform']}")
    if not args.send or not plan:
        return

    key = upd.resend_key()
    log_dir = os.path.expanduser("~/.nawana/mail-logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"{CAMPAIGN}.json")
    try:
        log = json.load(open(log_file))
    except FileNotFoundError:
        log = {"campaign": CAMPAIGN, "sent": []}
    ok = failed = 0
    for r in plan:
        try:
            mid = send(key, r["email"], f"{CAMPAIGN}:{r['email'].lower()}")
        except Exception as e:  # one bad address must not stop the rest
            failed += 1
            print(f"  FAIL {r['email']}: {e}")
            continue
        ok += 1
        log["sent"].append({"user_id": r["user_id"], "email": r["email"],
                            "sent_at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
        json.dump(log, open(log_file, "w"), ensure_ascii=False, indent=1)
        print(f"  sent {r['email']}  {mid}")
        time.sleep(upd.PER_SEND_PAUSE)
    print(f"\n{ok} sent, {failed} failed")


if __name__ == "__main__":
    main()

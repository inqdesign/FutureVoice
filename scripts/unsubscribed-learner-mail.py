#!/usr/bin/env python3
"""Learners who used the app well and did not subscribe: what held them back (2026-10-13).

The segment is computed, not listed, so the same letter reaches everyone of
this kind the day they become it:

  - spent the free talk pool (balance under 2 min, at least 15 min talked)
  - no live subscription (not active, not trialing)

First written for hyunss11@naver.com (fcf5b6b1, signed up 10-09, 20 min of
English over three days, shadowing, an accent remix, the daily call on).
No offer: the question is the point. Each learner is sent this campaign at
most once (Resend idempotency key per address).

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/unsubscribed-learner-mail.py                    # who + dry run
  python3 scripts/unsubscribed-learner-mail.py --preview out.html  # first recipient's HTML
  python3 scripts/unsubscribed-learner-mail.py --only hyunss11@naver.com --send
  python3 scripts/unsubscribed-learner-mail.py --send              # everyone listed
"""

import argparse
import glob
import html
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "unsubscribed-learner-2026-10"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

MIN_TALK_SECONDS = 900      # 15 of the 20 free minutes
MAX_BALANCE_SECONDS = 120   # what is left of the pool

LANG_KO = {"en": "영어", "de": "독일어", "ja": "일본어", "fr": "프랑스어", "es": "스페인어", "ko": "한국어"}

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "나와나 20분, 어떠셨나요?"


def open_paras(r: dict) -> list[str]:
    langs = "와 ".join(LANG_KO.get(c, c) for c in r["langs"]) if r["langs"] else ""
    said = f"{langs}로 미래의 나와" if langs else "미래의 나와"
    return [
        "안녕하세요. 나와나를 만든 이응규입니다.",
        f"{said} 무료 통화 시간을 끝까지 채워 이야기해 주셔서 고맙습니다. "
        "이렇게 끝까지 써 주신 분의 이야기가 가장 궁금해서 직접 연락드립니다.",
        "구독을 권하려는 메일이 아닙니다. 써 보신 그대로를 듣고 싶습니다.",
    ]


QUESTIONS = [
    "써 보시니 어떠셨나요? 좋았던 순간이 있었다면 언제였나요?",
    "구독을 망설이게 되시는 이유가 있다면 무엇일까요? 가격, 통화 품질, 목소리, 대화 내용, 아니면 좀 더 써 보고 정하고 싶으신 것도 괜찮습니다.",
    "무엇이 달랐다면 계속 쓰셨을까요?",
]

OFFER = [
    "나와나는 창업한 지 아직 한 달이 채 되지 않았습니다. 여러 분의 의견을 여쭙고, "
    "앞으로 무엇을 보완해야 할지 방향을 잡고 싶어 이렇게 연락드립니다. "
    "어떤 이야기든 편하게 들려주시면, 아직 혼자 사업을 꾸려 가는 저에게 큰 도움이 됩니다.",
    "혹시 불편하셨던 점이 있다면 말씀해 주세요. 바로 고쳐서 반영하겠습니다.",
    "이 메일에 답장하시거나, 스레드 또는 인스타그램 DM 중 편하신 방법으로 보내 주세요.",
]

MIDDLE: list[str] = []

CLOSE = "고맙습니다."
SIGN = "이응규 드림"
UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body(r: dict) -> str:
    parts = list(open_paras(r))
    parts.append("\n".join(f"· {q}" for q in QUESTIONS))
    parts += OFFER[:-1]
    parts.append(f"{OFFER[-1]}\n\n답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}")
    parts += MIDDLE
    parts += [CLOSE, SIGN, L.APP_STORE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body(r: dict) -> str:
    OPEN = open_paras(r)
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(OPEN[0], top=0) + "".join(p(s) for s in OPEN[1:])
        + "".join(p(f"· {q}", top=(14 if i == 0 else 6)) for i, q in enumerate(QUESTIONS))
        + "".join(p(s, top=(20 if i == 0 else 14)) for i, s in enumerate(OFFER))
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + "".join(p(s, top=(22 if i == 0 else 10)) for i, s in enumerate(MIDDLE))
        + p(CLOSE, top=22)
        + p(SIGN, color=L.DIM, top=6)
    )

    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@media only screen and (max-width:480px) {{
  .wrap {{ padding:22px 4px 28px !important; }}
}}
</style></head><body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" class="wrap" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;word-break:keep-all;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;">
            <tr>
              <td style="vertical-align:middle;padding-right:10px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                       style="display:block;width:36px;height:36px;border-radius:9px;">
                </a>
              </td>
              <td style="vertical-align:middle;font-size:17px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</td>
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


def recipients() -> list[dict]:
    rows = L.sql(f"""
      with talk as (
        select user_id, -sum(delta) as secs,
               count(distinct date(created_at at time zone 'Asia/Seoul')) as days,
               max(created_at) as last_talk
          from usage_ledger where action = 'talk_time' group by 1)
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email,
             coalesce(s.status, 'none') as status,
             coalesce(c.balance, 0) as balance, t.secs, t.days,
             to_char(u.created_at, 'YYYY-MM-DD') as signup,
             to_char(t.last_talk, 'YYYY-MM-DD') as last_talk,
             (select string_agg(language, ',' order by sum desc) from
                (select language, sum(seconds) from talk_seconds_by_language l
                  where l.user_id = u.id group by 1) x) as langs,
             (select left(r.inviter_id::text, 8) || ' ' || coalesce(iu.email, '?')
                from referral_redemptions r left join auth.users iu on iu.id = r.inviter_id
               where r.invitee_id = u.id limit 1) as invited_by,
             (select string_agg(left(r.invitee_id::text, 8) || ' ' || coalesce(iu.email, '?'),
                                ', ' order by r.created_at)
                from referral_redemptions r left join auth.users iu on iu.id = r.invitee_id
               where r.inviter_id = u.id) as invited
        from talk t
        join auth.users u on u.id = t.user_id
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
        left join user_credits c on c.user_id = u.id
       where u.deleted_at is null
         and coalesce(s.status, 'none') not in ('active', 'trialing')
         and coalesce(c.balance, 0) < {MAX_BALANCE_SECONDS}
         and t.secs >= {MIN_TALK_SECONDS}
       order by t.last_talk desc""")
    for r in rows:
        r["langs"] = [x for x in (r["langs"] or "").split(",") if x]
    return rows


def earlier_mail(user_id: str) -> str:
    """Other one-off scripts that named this learner, so a second letter is a choice."""
    me = os.path.basename(__file__)
    hits = [os.path.basename(p) for p in glob.glob(os.path.join(_here, "*mail*.py"))
            if os.path.basename(p) != me and user_id[:8] in open(p).read()]
    return ", ".join(sorted(hits))


def send(key: str, r: dict, idem: str, to: str | None = None) -> str:
    payload = {
        "from": L.FROM,
        "to": [to or r["email"]],
        "reply_to": L.REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(r),
        "html": html_body(r),
        "headers": {
            "List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
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
    ap.add_argument("--only", metavar="EMAIL", action="append", help="limit to these addresses")
    ap.add_argument("--skip", metavar="EMAIL", action="append", default=[], help="leave these out")
    ap.add_argument("--preview", metavar="FILE", help="write the first recipient's HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send the first recipient's letter to EMAIL")
    ap.add_argument("--send", action="store_true", help="send (after the copy is approved)")
    args = ap.parse_args()

    only = {e.lower() for e in args.only or []}
    skip = {e.lower() for e in args.skip}
    plan = []
    for r in recipients():
        email = (r["email"] or "").lower()
        if only and email not in only:
            continue
        if email in skip:
            print(f"  skip  {r['user_id'][:8]}  {email}  (--skip)")
            continue
        if not email or not L.EMAIL_RE.match(email):
            print(f"  skip  {r['user_id'][:8]}  no address")
            continue
        plan.append(r)

    for r in plan:
        prior = earlier_mail(r["user_id"])
        print(f"  send  {r['user_id'][:8]}  {r['email']:<40} {r['secs']:>5}s {r['days']}d "
              f"{','.join(r['langs']):<6} signup {r['signup']}  last {r['last_talk']}"
              + (f"  [earlier: {prior}]" if prior else ""))
        if r["invited_by"]:
            print(f"          invited by  {r['invited_by']}")
        if r["invited"]:
            print(f"          invited     {r['invited']}")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not plan:
        return

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body(plan[0]))
        print(f"wrote {args.preview}\n\n--- subject ---\n{SUBJECT}\n\n--- text ---\n{text_body(plan[0])}")
        return

    if args.test:
        print("sent test:", send(L.resend_key(), plan[0], f"{CAMPAIGN}:test:{int(time.time())}", args.test))
        return

    if not args.send:
        print(f"\n--- {plan[0]['email']} ---\n{SUBJECT}\n\n{text_body(plan[0])}")
        return

    key = L.resend_key()
    for r in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, r, f'{CAMPAIGN}:{email.lower()}')}")
        except Exception as e:
            print(f"  FAIL  {email}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

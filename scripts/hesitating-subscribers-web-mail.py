#!/usr/bin/env python3
"""Founder letter to learners who tried nawana and haven't subscribed: the web is 10% cheaper (2026-11-18).

Who (computed, so the letter reaches everyone of this kind):
  - native language Korean (profiles.native_language, setup_at set)
  - talked at least --min-minutes (default 5) of metered talk
  - no live subscription (not active, not trialing), not an admin account
  - not a test account (admin/src/assemble.ts TEST_IDS / TEST_EMAILS)
  - not ssenimida@gmail.com (got the one-person version on 11-17)

The copy is the founder's own draft, spelling fixed. Approve before --send.
Each address gets this campaign at most once (Resend idempotency key).

  python3 scripts/hesitating-subscribers-web-mail.py                     # who + dry run
  python3 scripts/hesitating-subscribers-web-mail.py --preview out.html
  python3 scripts/hesitating-subscribers-web-mail.py --test me@example.com
  python3 scripts/hesitating-subscribers-web-mail.py --send
"""

import argparse
import html
import importlib.util
import json
import os
import re
import time
from datetime import date
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "hesitating-web-discount-2026-11-18"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
WEB_URL = "https://nawana.app/ko.html#pricing"
APP_STORE_REVIEW = "https://apps.apple.com/app/id6792794655?action=write-review"
PLAY_STORE = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

ALREADY_SENT = {"ssenimida@gmail.com"}

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "나와나를 만들고 있는 이응규입니다"

# A block is a paragraph (lines kept as written) or ("buttons", [(label, url, filled), ...]).
BLOCKS = [
    "안녕하세요. 나와나를 만들고 있는 이응규입니다.",
    "나와나를 써 보시고 구독을 고민하고 계신 분들께\n"
    "어떻게 말씀드리면 좋을까 생각하다 이 메일을 씁니다.",
    "아직 개선 사항이 많지만, 나와나는 다른 어떤 AI 전화영어보다 만족스러우실 거라 자신합니다.\n"
    "그리고 이건 제가 앞으로 더 개선해 가면서, 제 스스로가 자신 있게 이 말을 할 수 있을 때까지 더 노력하겠습니다.",
    "솔직히 말씀드리면, 나와나는 유지 비용이 많이 드는 앱입니다.\n"
    "더 많이 무료로 쓰실 수 있게 하고 싶지만,\n"
    "그렇게 하면 서비스를 계속 이어갈 수가 없습니다.\n"
    "그래서 지금은 남는 것이 없더라도\n"
    "가장 좋은 서비스를 만드는 데 투자하는 단계라고 생각하고 있습니다.",
    "그래서 지금 제가 드릴 수 있는 작은 혜택이 하나 있습니다.\n"
    "웹사이트에서 구독하시면 10% 할인된 가격으로 구독하실 수 있습니다.\n"
    "앱스토어 결제에서 빠지는 수수료를 웹에서는 아낄 수 있어서,\n"
    "그만큼을 여러분께 돌려드리려고 합니다.",
    ("buttons", [("웹에서 10% 할인으로 구독하기", WEB_URL, True)]),
    "웹사이트에서 앱과 같은 계정(Apple 또는 Google)으로 로그인하시면\n"
    "구독이 앱에 바로 반영됩니다.",
    "구독은 아니더라도 나와나를 응원해 주고 싶으신 분들은,\n"
    "앱스토어나 구글 플레이에 평가를 남겨 주시면 감사하겠습니다.\n"
    "제 글을 보실 때 그냥 지나치지 않고 응원해 주시는 것도\n"
    "더 많은 분들이 나와나를 알게 되는 데 큰 힘이 됩니다.",
    ("buttons", [("App Store 평가", APP_STORE_REVIEW, False),
                 ("Google Play 평가", PLAY_STORE, False)]),
    "사업은 처음이라 아직 배울 것도, 부족한 것도 많습니다.\n"
    "그래도 제 목표는 하나입니다. 여러분의 언어가 실제로 늘어나는 것입니다.\n"
    "그리고 저는 그 지표가 여러분이 나와나를 열고 쓰는 시간이라고 생각합니다.",
    "혼자 있을 때, 출퇴근길에, 자투리 시간에\n"
    "소셜 미디어 대신 나와나를 먼저 열어 보실 수 있도록.\n"
    "여러분의 스마트폰에서 눈에 띄는 자리에 나와나가 있을 수 있도록.\n"
    "가장 잘 맞는 언어 학습 앱으로 사랑받을 수 있도록.\n"
    "제 하루를 모두 쏟겠다고 약속드립니다.",
    "나와나를 시작한 지 이제 두 달이 되었습니다.\n"
    "조급해지는 날도, 불확실한 미래가 걱정되는 날도 있지만,\n"
    "매일 조금씩 늘어나는 사용자분들,\n"
    "그리고 저를 믿고 구독해 주신 분들을 생각하며 마음을 다잡고 있습니다.",
    "길게는 몇십 년 동안 풀지 못한 외국어 공부,\n"
    "여러분과 함께 꼭 좋은 결과를 만들고 싶습니다.\n"
    "몇 달 뒤, 지금보다 조금 더 유창한 나와 닮아 있기를 진심으로 응원합니다!",
    "이응규 드림",
    "P.S. 오랜만에 오시는 분들은 꼭 앱을 업데이트하신 뒤 사용해 주세요.\n"
    "P.S. 나와나를 더 쓰고 싶은데 이런저런 이유로 구독이 망설여지신다면,\n"
    "이 메일에 답장으로 편하게 말씀해 주세요.",
]

UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."

# --------------------------------------------------------------------------


def text_body() -> str:
    parts = []
    for b in BLOCKS:
        if isinstance(b, tuple):
            parts.append("\n".join(f"{label}: {url}" for label, url, _ in b[1]))
        else:
            parts.append(b)
    parts.append(UNSUB)
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, top=18):
        inner = "<br>".join(html.escape(line) for line in s.split("\n"))
        return (f'<p style="font-size:16px;line-height:1.7;color:{L.INK};margin:{top}px 0 0;">'
                f'{inner}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = ""
    for i, b in enumerate(BLOCKS):
        if isinstance(b, tuple):
            body += '<div style="margin:16px 0 0;">' + "".join(button(*x) for x in b[1]) + "</div>"
        else:
            body += p(b, top=0 if i == 0 else 18)

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
            <a href="{WEB_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def test_accounts() -> tuple[set[str], set[str]]:
    src = open(os.path.join(_here, "..", "admin", "src", "assemble.ts")).read()
    def block(name):
        m = re.search(name + r"\s*=\s*new Set\(\[(.*?)\]\)", src, re.S)
        return set(re.findall(r'"([^"]+)"', re.sub(r"//[^\n]*", "", m.group(1)))) if m else set()
    return block("TEST_IDS"), {e.lower() for e in block("TEST_EMAILS")}


OPENS = os.path.join(_here, "..", "build-capture", f"{CAMPAIGN}.opens.tsv")
RECENT_DAYS = 14       # "opened the app recently"
GAP_DAYS = 14          # away this long before that = "came back after a while"


def open_days() -> dict[str, list[str]]:
    """Days each learner had the app on screen, pulled from PostHog on 2026-11-18
    (Application Opened / screen_viewed, learners seen in the last 21 days)."""
    out = {}
    try:
        for line in open(OPENS):
            if line.startswith("#") or "\t" not in line:
                continue
            uid, days = line.rstrip("\n").split("\t")
            out[uid.lower()] = sorted(days.split(","))
    except FileNotFoundError:
        print(f"  (no {OPENS}: recent opens unknown)")
    return out


def recipients(min_seconds: int, native: str = "ko") -> list[dict]:
    native_sql = ("p.native_language = 'ko'" if native == "ko" else "p.native_language <> 'ko'")
    rows = L.sql(f"""
      with talk as (
        select user_id, -sum(delta) as secs,
               string_agg(distinct to_char(created_at, 'YYYY-MM-DD'), ',') as talk_days
          from usage_ledger where action = 'talk_time' group by 1)
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email,
             coalesce(s.status, 'none') as status, coalesce(s.source, '') as source,
             coalesce(t.secs, 0) as secs, coalesce(t.talk_days, '') as talk_days,
             to_char(u.created_at, 'YYYY-MM-DD') as signup,
             p.target_language as target, p.native_language as native,
             coalesce(c.balance, 0) as balance,
             (select count(*) from client_events e
               where e.user_id = u.id and e.event = 'paywall_purchase_tapped') as tapped,
             (select count(*) from client_events e
               where e.user_id = u.id and e.event = 'paywall_shown') as paywalls
        from auth.users u
        join profiles p on p.id = u.id
        left join talk t on t.user_id = u.id
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
        left join user_credits c on c.user_id = u.id
       where u.deleted_at is null
         and p.setup_at is not null and {native_sql}
         and coalesce(s.status, 'none') not in ('active', 'trialing')
         -- someone who once paid Apple is not who this letter is for; an expired
         -- free code (Android testers, month-free codes) is
         and not (coalesce(s.status, 'none') = 'expired' and s.source <> 'comp')
         and not coalesce(c.unlimited, false)""")
    ids, emails = test_accounts()
    # creators get nawana free through the program, so the offer isn't for them
    emails |= {r["e"] for r in L.sql(
        "select lower(email) as e from creator_applications where kind = 'creator' and email is not null")}
    opens = open_days()
    today = date.today()
    out = []
    for r in rows:
        if r["user_id"] in ids or (r["email"] or "").lower() in emails:
            continue
        talk = sorted(d for d in r["talk_days"].split(",") if d)
        seen = sorted(set(talk) | set(opens.get(r["user_id"], [])))
        last = date.fromisoformat(seen[-1]) if seen else None
        r["days_ago"] = (today - last).days if last else 999
        r["recent"] = r["days_ago"] <= RECENT_DAYS
        before = [d for d in seen if (last - date.fromisoformat(d)).days >= 1] if last else []
        # back after a while: the last visit is recent, and the visit before it
        # (or the signup, for someone who never came back until now) is far behind
        prev = date.fromisoformat(before[-1]) if before else date.fromisoformat(r["signup"])
        r["returning"] = r["recent"] and (last - prev).days >= GAP_DAYS
        if r["secs"] < min_seconds and not r["recent"]:
            continue
        r["score"], r["why"] = priority(r)
        out.append(r)
    out.sort(key=lambda r: (-r["score"], r["days_ago"], -r["secs"]))
    return out


def priority(r: dict) -> tuple[int, str]:
    """Who is closest to subscribing goes first, because a day is ~100 mails."""
    score, why = 0, []
    if r["tapped"]:
        score += 40; why.append("tapped buy")
    if r["returning"]:
        score += 30; why.append("came back")
    if r["balance"] < 120 and r["secs"] > 0:
        score += 20; why.append("free spent")
    if r["recent"]:
        score += 15; why.append("opened lately")
    if r["paywalls"]:
        score += 10; why.append(f"plans x{r['paywalls']}")
    if r["status"] == "expired":
        why.append("free code ended")
    score += max(0, 20 - r["days_ago"] // 3)      # 20 today, 0 after two months
    score += min(r["secs"] // 60, 60) // 3        # up to 20 for an hour of talk
    return score, ", ".join(why)


def send(key: str, to: str, idem: str) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(),
        "html": html_body(),
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
    ap.add_argument("--min-minutes", type=float, default=5, help="talk needed to count as having tried it")
    ap.add_argument("--only", metavar="EMAIL", action="append", help="limit to these addresses")
    ap.add_argument("--skip", metavar="EMAIL", action="append", default=[], help="leave these out")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one copy to EMAIL")
    ap.add_argument("--limit", type=int, default=80,
                    help="send at most this many now (Resend free: 100 a day, shared with Dear RoRo)")
    ap.add_argument("--send", action="store_true", help="send (after the copy is approved)")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"wrote {args.preview}\n\n--- subject ---\n{SUBJECT}\n\n--- text ---\n{text_body()}")
        return
    if args.test:
        print("sent test:", send(L.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}"))
        return

    only = {e.lower() for e in args.only or []}
    sent = load_sent()
    skip = {e.lower() for e in args.skip} | ALREADY_SENT | sent
    plan = []
    for r in recipients(int(args.min_minutes * 60)):
        email = (r["email"] or "").lower()
        if only and email not in only:
            continue
        if email in skip:
            print(f"  skip  {r['user_id'][:8]}  {email}")
            continue
        if not email or not L.EMAIL_RE.match(email):
            print(f"  skip  {r['user_id'][:8]}  no address")
            continue
        plan.append(r)

    print(f"already sent in this campaign: {len(sent)}")
    for i, r in enumerate(plan):
        mark = "send" if i < args.limit else "later"
        print(f"  {mark:<5} {r['score']:>3}  {r['email']:<44} {r['secs'] // 60:>4} min  "
              f"{r['target'] or '?':<3} last {r['days_ago']:>2}d ago  {r['why']}")
    now = plan[:args.limit]
    print(f"{len(now)} now, {len(plan) - len(now)} later" + ("" if args.send else "   DRY RUN"))

    if not args.send or not now:
        return
    key = L.resend_key()
    for r in now:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, f'{CAMPAIGN}:{email.lower()}')}")
            mark_sent(email)
        except Exception as e:
            print(f"  FAIL  {email}: {e}")
            if "429" in str(e) or "quota" in str(e).lower():
                print("  stopped: Resend says today's quota is used. Run again tomorrow.")
                return
        time.sleep(L.PER_SEND_PAUSE)


SENT_LOG = os.path.join(_here, "..", "build-capture", f"{CAMPAIGN}.sent.txt")


def load_sent() -> set[str]:
    """Resend forgets an idempotency key after 24 h, so a second day needs our own list."""
    try:
        return {l.strip().lower() for l in open(SENT_LOG) if l.strip()}
    except FileNotFoundError:
        return set()


def mark_sent(email: str) -> None:
    os.makedirs(os.path.dirname(SENT_LOG), exist_ok=True)
    with open(SENT_LOG, "a") as f:
        f.write(email.lower() + "\n")


if __name__ == "__main__":
    main()

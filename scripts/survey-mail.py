#!/usr/bin/env python3
"""Mail a survey link to a list of learners (2026-10-20). Reusable.

The survey itself is web/survey/<id>.json: its questions drive the page at
nawana.app/s/<id>, and its "mail" block is this letter's copy (ko + en; a
learner whose native language isn't Korean gets en). Each recipient gets an
opaque token in the link, written to survey_invites when the mail is SENT,
so an answer is tied to the learner and the group without asking anything.
Sending twice to the same learner reuses the token (and Resend's idempotency
key stops a second mail).

Recipients come from a CSV with at least `user_id` (and optionally `group`),
or from --users. Subscribers are skipped.

  python3 scripts/survey-mail.py first-weeks-2026-10 --csv list.csv --preview out.html
  python3 scripts/survey-mail.py first-weeks-2026-10 --csv list.csv              # dry run
  python3 scripts/survey-mail.py first-weeks-2026-10 --csv list.csv --group B    # one group
  python3 scripts/survey-mail.py first-weeks-2026-10 --csv list.csv --test me@x  # one real mail
  python3 scripts/survey-mail.py first-weeks-2026-10 --csv list.csv --send       # after approval

Copy is the founder's to approve (합니다체, no em dash). Never --send before.
"""

import argparse
import csv
import html
import importlib.util
import json
import os
import re
import secrets
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def load_survey(survey_id: str) -> dict:
    path = os.path.join(_here, "..", "web", "survey", f"{survey_id}.json")
    with open(path) as f:
        s = json.load(f)
    assert s["id"] == survey_id, "file name and id differ"
    return s


def link(survey_id: str, token: str, lang: str) -> str:
    return f"{L.SITE_URL}/s/{survey_id}?t={token}&l={lang}"


def text_body(m: dict, url: str) -> str:
    parts = list(m["open"])
    parts.append(f"{m['button']}: {url}")
    parts.append(f"{m['or_reply']}\n\n{m['reply_label']}: {L.REPLY_TO}\n"
                 f"{m['threads_label']}: {THREADS_URL}\n{m['instagram_label']}: {INSTAGRAM_URL}")
    parts += [m["close"], m["sign"], m["unsub"]]
    return "\n\n".join(parts)


def html_body(m: dict, url: str) -> str:
    def p(s, color=L.INK, top=16):
        return (f'<p style="font-size:16px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, href, filled, big=False):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        pad = "14px 26px" if big else "11px 18px"
        size = "17px" if big else "15px"
        return (f'<a href="{href}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:{size};font-weight:700;'
                f'padding:{pad};border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(m["open"][0], top=0) + "".join(p(s) for s in m["open"][1:])
        + f'<div style="margin:22px 0 4px;">{button(m["button"], url, True, big=True)}</div>'
        + p(m["or_reply"], top=14)
        + '<div style="margin:14px 0 0;">'
        + button(m["reply_label"], f"mailto:{L.REPLY_TO}", False)
        + button(m["threads_label"], THREADS_URL, False)
        + button(m["instagram_label"], INSTAGRAM_URL, False)
        + '</div>'
        + p(m["close"], top=22)
        + p(m["sign"], color=L.DIM, top=6)
    )
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;word-break:keep-all;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;"><tr>
            <td style="vertical-align:middle;padding-right:10px;"><a href="{L.SITE_URL}" style="text-decoration:none;">
              <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana" style="display:block;width:36px;height:36px;border-radius:9px;"></a></td>
            <td style="vertical-align:middle;font-size:17px;font-weight:700;color:{L.INK};">nawana</td></tr></table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a> &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a> &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a> &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
            <br>{html.escape(m["unsub"])}
          </div>
        </td></tr></table>
    </td></tr></table></body></html>"""


def read_list(args) -> list[dict]:
    rows = []
    if args.csv:
        with open(args.csv) as f:
            for r in csv.DictReader(f):
                g = (r.get("group") or "").strip()
                if args.group and not g.startswith(args.group):
                    continue
                rows.append({"user_id": r["user_id"].strip(), "group": g})
    for u in (args.users or "").split(","):
        if u.strip():
            rows.append({"user_id": u.strip(), "group": args.group or ""})
    for r in rows:
        if not UUID_RE.match(r["user_id"]):
            raise SystemExit(f"not a user id: {r['user_id']}")
    return rows


def recipients(rows: list[dict], survey_id: str) -> list[dict]:
    if not rows:
        return []
    ids = ",".join(f"'{r['user_id']}'" for r in rows)
    sid = survey_id.replace("'", "")
    found = L.sql(f"""
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email,
             coalesce(p.native_language, 'ko') as native,
             s.status, i.token
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
        left join profiles p on p.id = u.id
        left join survey_invites i on i.user_id = u.id and i.survey_id = '{sid}'
       where u.id in ({ids}) and u.deleted_at is null""")
    group = {r["user_id"]: r["group"] for r in rows}
    for f in found:
        f["group"] = group.get(f["user_id"], "")
        f["lang"] = "ko" if f["native"] == "ko" else "en"
    return found


def remember_invite(survey_id: str, r: dict) -> str:
    """The token in this learner's link, written before the mail goes out."""
    if r["token"]:
        return r["token"]
    token = secrets.token_urlsafe(9)
    L.sql(f"""insert into survey_invites (token, survey_id, user_id, grp, email)
              values ({L.q(token)}, {L.q(survey_id)}, '{r['user_id']}', {L.q(r['group'])}, {L.q(r['email'])})
              on conflict (survey_id, user_id) where user_id is not null do nothing""")
    got = L.sql(f"select token from survey_invites where survey_id = {L.q(survey_id)} and user_id = '{r['user_id']}'")
    return got[0]["token"]


def send(key: str, m: dict, to: str, url: str, idem: str, campaign: str) -> str:
    payload = {
        "from": L.FROM, "to": [to], "reply_to": L.REPLY_TO, "subject": m["subject"],
        "text": text_body(m, url), "html": html_body(m, url),
        "headers": {"List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>", "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": campaign}],
    }
    req = urllib.request.Request("https://api.resend.com/emails", data=json.dumps(payload).encode(), method="POST")
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
    ap.add_argument("survey", help="survey id = web/survey/<id>.json")
    ap.add_argument("--csv", help="list with a user_id column (and group)")
    ap.add_argument("--users", help="comma-separated user ids")
    ap.add_argument("--group", help="only rows whose group starts with this")
    ap.add_argument("--preview", metavar="FILE", help="write the Korean HTML with a sample link and exit")
    ap.add_argument("--lang", default="ko", help="language for --preview/--test (ko|en)")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail (anonymous link) to EMAIL")
    ap.add_argument("--send", action="store_true", help="send to the list (after the copy is approved)")
    args = ap.parse_args()

    survey = load_survey(args.survey)
    campaign = f"survey-{args.survey}"

    if args.preview or args.test:
        m = survey["mail"][args.lang]
        url = f"{L.SITE_URL}/s/{args.survey}?l={args.lang}"
        if args.preview:
            with open(args.preview, "w") as f:
                f.write(html_body(m, url))
            print(f"wrote {args.preview}\n\n--- subject ---\n{m['subject']}\n\n--- text ---\n{text_body(m, url)}")
        else:
            print("sent test:", send(L.resend_key(), m, args.test, url, f"{campaign}:test:{int(time.time())}", campaign))
        return

    plan = []
    for r in recipients(read_list(args), args.survey):
        tag = f"{r['user_id'][:8]} {r['group'][:1] or '-'} {r['lang']}"
        if r["status"] in ("active", "trialing"):
            print(f"  skip  {tag}  subscribed")
        elif not r["email"] or not L.EMAIL_RE.match(r["email"]):
            print(f"  skip  {tag}  no address")
        else:
            plan.append(r)
            print(f"  send  {tag}  {r['email']}" + ("  (relay)" if r["email"].endswith(L.RELAY) else ""))
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r in plan:
        try:
            token = remember_invite(args.survey, r)
            mid = send(key, survey["mail"][r["lang"]], r["email"], link(args.survey, token, r["lang"]),
                       f"{campaign}:{r['user_id']}", campaign)
            print(f"  sent  {r['email']}  {mid}")
        except Exception as e:
            print(f"  FAIL  {r['email']}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()

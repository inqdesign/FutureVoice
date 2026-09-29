#!/usr/bin/env python3
"""Run nawana.app/community from the terminal: news posts, chat moderation, staff.

The page itself only READS news and only INSERTS chat messages as the signed-in
user (see supabase/migrations/20260929120000_community.sql). Everything a
moderator does goes through here, with the Supabase CLI's keychain token and
the Management API — the same path scripts/apply-migration.sh uses.

    python3 scripts/community.py news-list
    python3 scripts/community.py news-add --title-ko "…" --title-en "…" \\
        --body-ko-file ko.txt --body-en-file en.txt [--link URL] [--date 2026-09-28] [--publish]
    python3 scripts/community.py news-publish <id>      # or news-unpublish
    python3 scripts/community.py chat [--all]           # recent messages (with --all: hidden too)
    python3 scripts/community.py hide <message id>      # or unhide
    python3 scripts/community.py staff-add <user uuid or email> [--label nawana]
    python3 scripts/community.py visitors [--limit 50]  # signed-in visitors, newest first

A news post is a DRAFT until --publish / news-publish: a page reload shows a
published post at once, no redeploy.
"""
import argparse, json, secrets, subprocess, sys, base64, urllib.request

PROJECT = "chhzjtigzdotacutwcyo"


def token():
    raw = subprocess.check_output(["security", "find-generic-password", "-s", "Supabase CLI", "-w"], text=True).strip()
    return base64.b64decode(raw.removeprefix("go-keyring-base64:")).decode()


def sql(query):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json",
                 "User-Agent": "nawana-community-script"},
        method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"query failed ({e.code}): {e.read().decode()[:400]}")


def lit(s):
    """A SQL string literal that no text can break out of (random dollar tag)."""
    if s is None:
        return "null"
    tag = "t" + secrets.token_hex(6)
    return f"${tag}${s}${tag}$"


def read(path_or_text, is_file):
    return open(path_or_text, encoding="utf-8").read().strip() if is_file else path_or_text


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("news-list")
    a = sub.add_parser("news-add")
    a.add_argument("--title-ko", required=True); a.add_argument("--title-en", required=True)
    a.add_argument("--body-ko", default=""); a.add_argument("--body-en", default="")
    a.add_argument("--body-ko-file"); a.add_argument("--body-en-file")
    a.add_argument("--link"); a.add_argument("--image"); a.add_argument("--date")
    a.add_argument("--publish", action="store_true")
    for c in ("news-publish", "news-unpublish", "hide", "unhide"):
        sub.add_parser(c).add_argument("id")
    c = sub.add_parser("chat"); c.add_argument("--all", action="store_true"); c.add_argument("--limit", type=int, default=30)
    s = sub.add_parser("staff-add"); s.add_argument("who"); s.add_argument("--label", default="nawana")
    v = sub.add_parser("visitors"); v.add_argument("--limit", type=int, default=50)
    x = ap.parse_args()

    if x.cmd == "news-list":
        for r in sql("select id, published_at::date as day, is_published, title_ko, title_en from community_news order by published_at desc limit 50"):
            print(f"{r['id']}  {r['day']}  {'LIVE ' if r['is_published'] else 'draft'}  {r['title_ko']}  /  {r['title_en']}")
    elif x.cmd == "news-add":
        bko = read(x.body_ko_file, True) if x.body_ko_file else x.body_ko
        ben = read(x.body_en_file, True) if x.body_en_file else x.body_en
        when = f"{lit(x.date)}::timestamptz" if x.date else "now()"
        r = sql(f"""insert into community_news (published_at, title_ko, title_en, body_ko, body_en, link_url, image_url, is_published)
                    values ({when}, {lit(x.title_ko)}, {lit(x.title_en)}, {lit(bko)}, {lit(ben)}, {lit(x.link)}, {lit(x.image)}, {str(x.publish).lower()})
                    returning id, is_published""")
        print(("published " if r[0]["is_published"] else "draft saved ") + r[0]["id"])
    elif x.cmd in ("news-publish", "news-unpublish"):
        on = x.cmd == "news-publish"
        r = sql(f"update community_news set is_published = {str(on).lower()} where id = {lit(x.id)}::uuid returning id")
        print(("published " if on else "unpublished ") + (r[0]["id"] if r else "— no such post"))
    elif x.cmd == "chat":
        where = "" if x.all else "where not hidden"
        for r in reversed(sql(f"select id, created_at, display_name, is_staff, hidden, body from community_messages {where} order by created_at desc limit {int(x.limit)}")):
            flag = " [hidden]" if r["hidden"] else ""
            staff = " ★" if r["is_staff"] else ""
            print(f"#{r['id']}  {r['created_at'][:16]}  {r['display_name']}{staff}{flag}: {r['body']}")
    elif x.cmd in ("hide", "unhide"):
        r = sql(f"update community_messages set hidden = {str(x.cmd == 'hide').lower()} where id = {int(x.id)} returning id")
        print(("hidden #" if x.cmd == "hide" else "restored #") + (str(r[0]["id"]) if r else "— no such message"))
    elif x.cmd == "visitors":
        rows = sql(f"""select v.user_id, u.email, v.visits, v.first_seen, v.last_seen,
                             (select count(*) from community_messages m where m.user_id = v.user_id) msgs,
                             (select s.plan_id from user_subscriptions s where s.user_id = v.user_id limit 1) plan
                        from community_visits v join auth.users u on u.id = v.user_id
                       order by v.last_seen desc limit {int(x.limit)}""")
        print(f"{len(rows)} signed-in visitors")
        for r in rows:
            print(f"{r['last_seen'][:16]}  visits {r['visits']:>3}  msgs {r['msgs']:>3}  {r['plan'] or '-':<14} {r['email'] or r['user_id']}")
    elif x.cmd == "staff-add":
        who = x.who
        cond = f"id = {lit(who)}::uuid" if len(who) == 36 and who.count("-") == 4 else f"lower(email) = lower({lit(who)})"
        r = sql(f"""insert into community_staff (user_id, label) select id, {lit(x.label)} from auth.users where {cond}
                    on conflict (user_id) do update set label = excluded.label returning user_id""")
        print("staff: " + (r[0]["user_id"] if r else "— no such user"))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Read a survey's answers (2026-10-20). Reusable for any web/survey/<id>.json.

  python3 scripts/survey-results.py first-weeks-2026-10            # totals + per group
  python3 scripts/survey-results.py first-weeks-2026-10 --notes    # also every free-text answer
  python3 scripts/survey-results.py first-weeks-2026-10 --csv out.csv

Counts are per question, labelled in Korean from the survey file. Sent and
opened come from survey_invites, so the open rate per group is on top.
"""

import argparse
import collections
import csv
import importlib.util
import json
import os

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("survey")
    ap.add_argument("--notes", action="store_true", help="print every free-text answer")
    ap.add_argument("--csv", metavar="FILE", help="write one row per response")
    args = ap.parse_args()

    with open(os.path.join(_here, "..", "web", "survey", f"{args.survey}.json")) as f:
        survey = json.load(f)
    sid = L.q(args.survey)

    invites = L.sql(f"""select coalesce(grp,'') grp, count(*) sent, count(opened_at) opened
                          from survey_invites where survey_id = {sid} group by 1 order by 1""")
    rows = L.sql(f"""select r.answers, r.lang, r.created_at, r.updated_at, coalesce(i.grp, '(link)') grp,
                            i.user_id::text user_id
                       from survey_responses r left join survey_invites i on i.token = r.token
                      where r.survey_id = {sid} order by r.created_at""")
    for r in rows:
        if isinstance(r["answers"], str):
            r["answers"] = json.loads(r["answers"])

    answered = collections.Counter(r["grp"] for r in rows)
    print(f"== {args.survey}: {len(rows)} answers")
    for i in invites:
        print(f"  {i['grp'] or '-':32} sent {i['sent']:>3}  opened {i['opened']:>3}  answered {answered.get(i['grp'], 0):>3}")
    if answered.get("(link)"):
        print(f"  {'(shared link)':32} answered {answered['(link)']:>3}")

    groups = sorted({r["grp"] for r in rows})
    for q in survey["questions"]:
        if q["type"] == "text":
            continue
        print(f"\n-- {q['ko']}")
        label = {o["v"]: o["ko"] for o in q["options"]}
        for scope in [None] + (groups if len(groups) > 1 else []):
            sub = [r for r in rows if scope is None or r["grp"] == scope]
            c = collections.Counter()
            for r in sub:
                a = r["answers"].get(q["id"])
                for v in (a if isinstance(a, list) else [a] if a is not None else []):
                    c[v] += 1
            head = "  전체" if scope is None else f"  {scope}"
            print(f"{head} (n={len(sub)}): " + ", ".join(f"{label.get(v, v)} {n}" for v, n in c.most_common()))

    if args.notes:
        for q in [q for q in survey["questions"] if q["type"] == "text"]:
            print(f"\n-- {q['ko']}")
            for r in rows:
                t = (r["answers"].get(q["id"]) or "").strip()
                if t:
                    print(f"  [{r['grp'][:1] or '-'} {r['created_at'][:10]}] {t}")

    if args.csv:
        ids = [q["id"] for q in survey["questions"]]
        with open(args.csv, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["group", "user_id", "lang", "created_at"] + ids)
            for r in rows:
                w.writerow([r["grp"], r["user_id"] or "", r["lang"], r["created_at"]] +
                           [";".join(a) if isinstance(a := r["answers"].get(i), list) else (a or "") for i in ids])
        print(f"\nwrote {args.csv}")


if __name__ == "__main__":
    main()

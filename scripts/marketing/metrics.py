#!/usr/bin/env python3
"""Collect views and engagement for posted pieces (marketing/AUTOMATION.md §6).

Runs from launchd daily at 09:00 (com.nawana.marketing-metrics). For every
'posted' piece younger than 60 days, one marketing_metrics row per channel per
UTC day (a second run the same day replaces that day's row):

  instagram  /{ig_media_id}/insights   views, reach, likes, comments, saved, shares
  threads    /{threads_media_id}/insights   views, likes, replies, reposts, quotes
             → comments = replies, shares = reposts + quotes

A metric the API refuses for that media type is asked again one by one, so a
single unsupported name never costs the rest. The raw answer rides in `raw`.

    metrics.py             # collect and write
    metrics.py --dry-run   # collect and print; write nothing
"""
import argparse, os, sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db  # noqa: E402
from scheduler import IG_HOST, TH_HOST, PostError, http  # noqa: E402

IG_METRICS = ["views", "reach", "likes", "comments", "saved", "shares"]
TH_METRICS = ["views", "likes", "replies", "reposts", "quotes"]


def log(*a):
    print(datetime.now().strftime("%F %T"), *a, flush=True)


def values(resp):
    out = {}
    for m in resp.get("data", []):
        v = None
        if "total_value" in m:
            v = (m["total_value"] or {}).get("value")
        elif m.get("values"):
            v = m["values"][-1].get("value")
        if isinstance(v, (int, float)):
            out[m["name"]] = int(v)
    return out


def insights(url, token, names):
    try:
        return values(http("GET", url, {"metric": ",".join(names), "access_token": token}))
    except PostError:
        got = {}
        for n in names:
            try:
                got.update(values(http("GET", url, {"metric": n, "access_token": token})))
            except PostError:
                pass
        return got


def instagram(env, media_id):
    v = env.get("IG_API_VERSION") or "v22.0"
    raw = insights(f"{IG_HOST}/{v}/{media_id}/insights", env["IG_ACCESS_TOKEN"], IG_METRICS)
    return {"views": raw.get("views"), "reach": raw.get("reach"), "likes": raw.get("likes"),
            "comments": raw.get("comments"), "saves": raw.get("saved"), "shares": raw.get("shares")}, raw


def threads(env, media_id):
    v = env.get("THREADS_API_VERSION") or "v1.0"
    raw = insights(f"{TH_HOST}/{v}/{media_id}/insights", env["THREADS_ACCESS_TOKEN"], TH_METRICS)
    shares = None
    if raw.get("reposts") is not None or raw.get("quotes") is not None:
        shares = (raw.get("reposts") or 0) + (raw.get("quotes") or 0)
    return {"views": raw.get("views"), "likes": raw.get("likes"), "comments": raw.get("replies"),
            "shares": shares}, raw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    x = ap.parse_args()

    env = db.load_env()
    try:
        pieces = db.sql("""select id, slug, ig_media_id, threads_media_id from marketing_pieces
                            where stage = 'posted' and posted_at > now() - interval '60 days'
                            order by posted_at desc""")
    except db.DBError as e:
        log(f"query failed: {e}")
        sys.exit(1)

    sources = []
    if env.get("IG_ACCESS_TOKEN"):
        sources.append(("instagram", "ig_media_id", instagram))
    if env.get("THREADS_ACCESS_TOKEN"):
        sources.append(("threads", "threads_media_id", threads))

    rows = fails = 0
    for p in pieces:
        for channel, col, fetch in sources:
            if not p.get(col):
                continue
            try:
                vals, raw = fetch(env, p[col])
            except Exception as e:
                fails += 1
                log(f"{p['slug']} {channel}: {e}")
                continue
            if not any(v is not None for v in vals.values()):
                fails += 1
                log(f"{p['slug']} {channel}: no metrics returned")
                continue
            log(f"{p['slug']} {channel}: " + " ".join(f"{k}={v}" for k, v in vals.items() if v is not None))
            if not x.dry_run:
                db.insert_metrics(p["id"], channel, vals, raw, replace_today=True)
            rows += 1

    msg = f"{rows} metric rows for {len(pieces)} posted pieces" + (f", {fails} failed" if fails else "")
    log(("[dry-run] " if x.dry_run else "") + msg)
    if not x.dry_run and pieces:
        try:
            db.add_event(None, "metrics", msg)
        except db.DBError as e:
            log(f"(event not recorded: {e})")


if __name__ == "__main__":
    main()

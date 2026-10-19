#!/usr/bin/env python3
"""The nawana Podcast's daily run: ONE English episode a day, one category
per weekday, numbered across days, appended to the feed the app reads.

    python3 scripts/news-show-daily.py            # today's episode, if not made yet
    python3 scripts/news-show-daily.py --reset    # start the feed over at EP 1

Founder, 2026-10-19: Mon–Sun each its own category, English only while the
reaction is tested. Idempotent: a day already in the feed is never made
again, so running it twice costs nothing. The story comes from the Talk
tab's news pool (`news_topics`, already searched today) when that category
has a row; only otherwise does it search. Made with the same pieces as
news-show-probe.py, uploaded to R2 (`nawana-shows`), latest.json last.

Keys from gateway/.dev.vars (DEV_VARS to point elsewhere); wrangler from
GATEWAY_DIR (default: this checkout's gateway/).
"""
import datetime
import importlib.util
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe", os.path.join(HERE, "news-show-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

LANG = "en"
# Monday first, one of the app's own interests a day, written as the app
# stores them (founder, 2026-10-19: "Monday tech, Tuesday fashion, like that").
CATEGORY_BY_WEEKDAY = ["AI / tech", "fashion", "science", "travel",
                       "music", "sports", "cooking"]
FEED_CAP = 60
BUCKET = "nawana-shows"
TODAY = probe.TODAY
OUT = os.environ.get("OUT_DIR", os.path.expanduser("~/Desktop/beta audio/nawana-podcast"))
GATEWAY_DIR = os.environ.get("GATEWAY_DIR", os.path.join(os.path.dirname(HERE), "gateway"))


def load_feed():
    """The feed as the BUCKET has it. The public URL is cached for five
    minutes, and a stale read is how a day gets made twice or two episodes
    get one number."""
    got = subprocess.run(["npx", "wrangler", "r2", "object", "get",
                          f"{BUCKET}/shows/{LANG}/latest.json", "--remote", "--pipe"],
                         cwd=GATEWAY_DIR, capture_output=True, text=True, env=wrangler_env())
    try:
        feed = json.loads(got.stdout)
    except ValueError:
        if "not found" in (got.stderr + got.stdout).lower():
            return {"episodes": []}
        sys.exit(f"couldn't read the feed: {got.stderr.strip()[-300:]}")
    # The first test day (2026-10-19) was a per-day manifest, not a feed.
    if "feed" not in feed:
        return {"episodes": []}
    return feed


def pooled_topic(category):
    """Today's stories for this category from the Talk tab's news pool, if
    someone has already opened it today. Saves the search."""
    url = probe.VARS["SUPABASE_URL"].strip().strip('"')
    key = probe.VARS["SUPABASE_SERVICE_ROLE_KEY"].strip().strip('"')
    q = urllib.parse.urlencode({"select": "topics", "language": f"eq.{LANG}",
                                "fetched_date": f"eq.{TODAY}",
                                "category": f"eq.{category.lower()}"})
    req = urllib.request.Request(f"{url}/rest/v1/news_topics?{q}",
                                 headers={"apikey": key, "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            rows = json.load(r)
    except Exception:
        return None
    stories = [t for row in rows for t in (row.get("topics") or []) if len(t.get("facts") or []) >= 4]
    if not stories:
        return None
    system = (
        "Pick the ONE story below that people would most enjoy talking about over coffee "
        "today. Not one whose core is deaths, violence or a disaster.\n"
        'Return JSON: { "index": 0, "title": "..." } (title: an English episode title, '
        "8 words or fewer)."
    )
    listing = "\n\n".join(f"[{i}] {t['title']}\n" + "\n".join(f"- {f}" for f in t["facts"])
                          for i, t in enumerate(stories))
    pick = probe.gemini(system, listing)
    story = stories[min(max(int(pick.get("index", 0)), 0), len(stories) - 1)]
    return {"title": pick.get("title") or story["title"], "area": category,
            "facts": story["facts"]}, {"source": "news_topics"}


def searched_topic(category):
    """No pool row today: search for this category alone."""
    probe.EPISODES = 1
    research = (
        f"Search the web now: what are the most talked-about news stories about {category} in "
        f"the US and the UK today, {TODAY} (last 48 hours)? Give 5, each with 6-8 facts: what "
        "happened, who, when, key numbers, reactions."
    )
    for _ in range(3):
        notes, grounding = probe.gemini(None, research, search=True)
        if grounding["sources"]:
            break
    else:
        sys.exit("the model never searched; no episode today")
    system = (
        "From the RESEARCH below, pick the ONE story people would most enjoy talking about "
        "over coffee. Not one whose core is deaths, violence or a disaster. Facts only from "
        "the RESEARCH.\n"
        'Return JSON: { "title": "...", "facts": ["...", "..."] } (title: English, 8 words '
        "or fewer; facts: 6-8, each 25 words or fewer)."
    )
    topic = probe.gemini(system, "RESEARCH:\n" + notes)
    topic["area"] = category
    return topic, {"source": "search", **grounding}


def wrangler_env():
    return {**os.environ, "PATH": "/opt/homebrew/opt/node@22/bin:" + os.environ.get("PATH", "")}


def put(key, path, content_type, cache):
    subprocess.run(["npx", "wrangler", "r2", "object", "put", f"{BUCKET}/{key}", "--file", path,
                    "--content-type", content_type, "--cache-control", cache, "--remote"],
                   cwd=GATEWAY_DIR, check=True, stdout=subprocess.DEVNULL, env=wrangler_env())


def main():
    reset = "--reset" in sys.argv
    feed = {"episodes": []} if reset else load_feed()
    if any(e.get("date") == TODAY for e in feed["episodes"]):
        print(f"{TODAY} is already in the feed; nothing to do")
        return
    category = CATEGORY_BY_WEEKDAY[datetime.date.fromisoformat(TODAY).weekday()]
    number = max([e.get("number", 0) for e in feed["episodes"]], default=0) + 1

    # Checked before anything is spent: a folder for today means a run
    # already made (or half made) it.
    folder = os.path.join(OUT, TODAY)
    if os.path.exists(folder) and os.listdir(folder):
        sys.exit(f"{folder} already has files; move them before making {TODAY} again")
    topic, how = pooled_topic(category) or searched_topic(category)
    r = probe.make_episode(LANG, number, topic, folder)
    sc = r["script"]
    with open(os.path.join(folder, "topic.json"), "w") as f:
        json.dump({"category": category, "topic": topic, **how}, f, ensure_ascii=False, indent=2)

    episode = {
        "id": f"{TODAY}-{LANG}",
        "number": number,
        "date": TODAY,
        "category": category,
        "title": sc.get("title", topic["title"]),
        "seconds": r["seconds"],
        "audio": f"{TODAY}/episode.mp3",
        "lines": [{"speaker": l["speaker"], "text": l["text"], "audio": f"{TODAY}/{l['audio']}",
                   "translations": l.get("translations", {})} for l in sc["lines"]],
        "expressions": [e.get("phrase", "") for e in sc.get("expressions", [])],
    }
    feed = {"feed": True, "language": LANG, "hosts": [h[0] for h in probe.HOSTS[LANG]],
            "episodes": ([episode] + feed["episodes"])[:FEED_CAP]}
    manifest = os.path.join(folder, "latest.json")
    with open(manifest, "w") as f:
        json.dump(feed, f, ensure_ascii=False, indent=2)

    immutable = "public, max-age=31536000, immutable"
    put(f"shows/{LANG}/{TODAY}/episode.mp3", os.path.join(folder, "episode.mp3"), "audio/mpeg", immutable)
    for name in sorted(os.listdir(os.path.join(folder, "lines"))):
        put(f"shows/{LANG}/{TODAY}/lines/{name}", os.path.join(folder, "lines", name),
            "audio/mpeg", immutable)
    put(f"shows/{LANG}/latest.json", manifest, "application/json", "public, max-age=300")
    print(f"EP {number} · {TODAY} · {category} · {episode['title']} · "
          f"{r['seconds'] // 60}:{r['seconds'] % 60:02d} · {r['chars']} chars "
          f"${r['chars'] * probe.USD_PER_CHAR:.2f} · topic from {how['source']}")


if __name__ == "__main__":
    main()

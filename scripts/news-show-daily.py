#!/usr/bin/env python3
"""The nawana Podcast's daily run: ONE episode a day PER LANGUAGE, one
category per weekday, numbered across days, appended to the feed the app reads.

    python3 scripts/news-show-daily.py              # today's episodes, if not made yet
    python3 scripts/news-show-daily.py --lang de    # one language only
    python3 scripts/news-show-daily.py --reset      # start the feed(s) over at EP 1

Which languages run is OUT_DIR/languages.txt (one code a line; "en" if the
file is missing). The app has no list of its own: a language is on in every
build the day its feed is in R2 (founder, 2026-10-20: "no app update").
Adding a language = its hosts in news-show-probe.py's HOSTS/REGION/LANG_NAME,
then a line in languages.txt. English keeps OUT_DIR itself; every other
language works in OUT_DIR/<lang>.

Founder, 2026-10-19: Mon–Sun each its own category, English only while the
reaction is tested. Idempotent: a day already in the feed is never made
again, so running it twice costs nothing. The story comes from the Talk
tab's news pool (`news_topics`, already searched today) when that category
has a row; only otherwise does it search. Made with the same pieces as
news-show-probe.py, uploaded to R2 (`nawana-shows`), latest.json last.

Episodes already made (OUT_DIR/stock.json) go out first, one a day, at no
cost; only when the stock is empty is a new one made.

Audio is deleted from this Mac once it is in R2; script.txt, script.json,
topic.json and latest.json stay in OUT_DIR/<date>.

Keys from gateway/.dev.vars (DEV_VARS to point elsewhere); wrangler from
GATEWAY_DIR (default: this checkout's gateway/).
"""
import datetime
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe", os.path.join(HERE, "news-show-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

# Monday first, one of the app's own interests a day, written as the app
# stores them (founder, 2026-10-19: "Monday tech, Tuesday fashion, like that").
CATEGORY_BY_WEEKDAY = ["AI / tech", "fashion", "science", "travel",
                       "music", "sports", "cooking"]
FEED_CAP = 60
BUCKET = "nawana-shows"
TODAY = probe.TODAY
OUT = os.environ.get("OUT_DIR", os.path.expanduser("~/Desktop/beta audio/nawana-podcast"))
GATEWAY_DIR = os.environ.get("GATEWAY_DIR", os.path.join(os.path.dirname(HERE), "gateway"))


def lang_dir(lang):
    return OUT if lang == "en" else os.path.join(OUT, lang)


def languages():
    try:
        got = [l.strip() for l in open(os.path.join(OUT, "languages.txt")) if l.strip()
               and not l.startswith("#")]
    except OSError:
        got = []
    return got or ["en"]


def load_feed(LANG):
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
        raise RuntimeError(f"couldn't read the {LANG} feed: {got.stderr.strip()[-300:]}")
    # The first test day (2026-10-19) was a per-day manifest, not a feed.
    if "feed" not in feed:
        return {"episodes": []}
    return feed


def no_ai(category):
    """Founder, 2026-10-21: not just AI. Only the tech day may be about AI,
    and even then not by default."""
    if category == "AI / tech":
        return ("Prefer phones, gadgets, apps, games, the internet or space tech; a story "
                "about artificial intelligence only if nothing else is worth talking about. ")
    return "Not a story about artificial intelligence. "


def pooled_topic(LANG, category):
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
        "today. Not one whose core is deaths, violence or a disaster. " + no_ai(category) + "\n"
        f'Return JSON: {{ "index": 0, "title": "..." }} (title: a {probe.LANG_NAME[LANG]} '
        "episode title, 8 words or fewer)."
    )
    listing = "\n\n".join(f"[{i}] {t['title']}\n" + "\n".join(f"- {f}" for f in t["facts"])
                          for i, t in enumerate(stories))
    pick = probe.gemini(system, listing)
    story = stories[min(max(int(pick.get("index", 0)), 0), len(stories) - 1)]
    return {"title": pick.get("title") or story["title"], "area": category,
            "facts": story["facts"]}, {"source": "news_topics"}


def searched_topic(LANG, category):
    """No pool row today: search for this category alone."""
    probe.EPISODES = 1
    research = (
        f"Search the web now: what are the most talked-about news stories about "
        f"{'technology' if category == 'AI / tech' else category} in "
        f"{probe.REGION[LANG]} today, {TODAY} (last 48 hours)? Give 5, each with 6-8 facts: what "
        "happened, who, when, key numbers, reactions. " + no_ai(category)
    )
    for _ in range(3):
        notes, grounding = probe.gemini(None, research, search=True)
        if grounding["sources"]:
            break
    else:
        raise RuntimeError("the model never searched; no episode today")
    system = (
        "From the RESEARCH below, pick the ONE story people would most enjoy talking about "
        "over coffee. Not one whose core is deaths, violence or a disaster. " + no_ai(category) +
        "Facts only from "
        "the RESEARCH.\n"
        f'Return JSON: {{ "title": "...", "facts": ["...", "..."] }} (title: '
        f"{probe.LANG_NAME[LANG]}, 8 words or fewer; facts: 6-8, each 25 words or fewer)."
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


def recent_categories(feed, n=2):
    return {e.get("category") for e in feed["episodes"][:n]}


def todays_category(feed):
    """The weekday's category, unless the feed has just had it: then the
    next one in the week that it hasn't."""
    start = datetime.date.fromisoformat(TODAY).weekday()
    recent = recent_categories(feed)
    for step in range(len(CATEGORY_BY_WEEKDAY)):
        category = CATEGORY_BY_WEEKDAY[(start + step) % len(CATEGORY_BY_WEEKDAY)]
        if category not in recent:
            return category
    return CATEGORY_BY_WEEKDAY[start]


def publish_from_stock(LANG, feed, number):
    """Episodes already made go out first, one a day, before anything new is
    made (founder, 2026-10-19). Their audio is already in R2, so publishing
    one is a feed write and costs nothing. OUT_DIR/stock.json, oldest first."""
    stock_file = os.path.join(lang_dir(LANG), "stock.json")
    try:
        stock = json.load(open(stock_file))
    except (OSError, ValueError):
        return False
    if not stock:
        return False
    # The first one in stock whose category the feed hasn't just had, so
    # the stock's order can't air two of a kind in a row (founder,
    # 2026-10-20: two tech episodes back to back).
    recent = recent_categories(feed)
    pick = next((i for i, e in enumerate(stock) if e.get("category") not in recent), 0)
    chosen = stock.pop(pick)
    episode = {**chosen, "id": f"{TODAY}-{LANG}", "number": number, "date": TODAY}
    folder = os.path.join(lang_dir(LANG), TODAY)
    os.makedirs(folder, exist_ok=True)
    feed = {"feed": True, "language": LANG, "hosts": [h[0] for h in probe.HOSTS[LANG]],
            "episodes": ([episode] + feed["episodes"])[:FEED_CAP]}
    manifest = os.path.join(folder, "latest.json")
    with open(manifest, "w") as f:
        json.dump(feed, f, ensure_ascii=False, indent=2)
    with open(os.path.join(folder, "from-stock.json"), "w") as f:
        json.dump(chosen, f, ensure_ascii=False, indent=2)
    put(f"shows/{LANG}/latest.json", manifest, "application/json", "public, max-age=300")
    with open(stock_file, "w") as f:
        json.dump(stock, f, ensure_ascii=False, indent=2)
    print(f"[{LANG}] EP {number} · {TODAY} · from stock · {episode.get('category')} · "
          f"{episode['title']} · {len(stock)} left in stock")
    return True


def main():
    only = sys.argv[sys.argv.index("--lang") + 1] if "--lang" in sys.argv else None
    failed = False
    for lang in [only] if only else languages():
        # One language failing must not cost the others their day.
        try:
            run(lang, reset="--reset" in sys.argv)
        except Exception as error:
            failed = True
            print(f"[{lang}] failed: {error}")
    if failed:
        sys.exit(1)


def run(LANG, reset):
    feed = {"episodes": []} if reset else load_feed(LANG)
    if any(e.get("date") == TODAY for e in feed["episodes"]):
        print(f"[{LANG}] {TODAY} is already in the feed; nothing to do")
        return
    number = max([e.get("number", 0) for e in feed["episodes"]], default=0) + 1
    if publish_from_stock(LANG, feed, number):
        return
    category = todays_category(feed)

    # Checked before anything is spent: a folder for today means a run
    # already made (or half made) it.
    folder = os.path.join(lang_dir(LANG), TODAY)
    if os.path.exists(folder) and os.listdir(folder):
        raise RuntimeError(f"{folder} already has files; move them before making {TODAY} again")
    topic, how = pooled_topic(LANG, category) or searched_topic(LANG, category)
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
        "study": sc.get("study"),
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

    # The Mac is only where the episode is MADE; R2 is where it lives. Once
    # it is up, the audio here goes (founder, 2026-10-19). The script, the
    # topic and the feed stay: they are what a question about an episode is
    # answered from, and the folder still marks the day as made.
    shutil.rmtree(os.path.join(folder, "lines"))
    os.remove(os.path.join(folder, "episode.mp3"))
    print(f"[{LANG}] EP {number} · {TODAY} · {category} · {episode['title']} · "
          f"{r['seconds'] // 60}:{r['seconds'] % 60:02d} · {r['chars']} chars "
          f"${r['chars'] * probe.USD_PER_CHAR:.2f} · topic from {how['source']}")


if __name__ == "__main__":
    main()

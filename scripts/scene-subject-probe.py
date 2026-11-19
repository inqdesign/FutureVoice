#!/usr/bin/env python3
# Does a scene stay on the situation the learner wrote when the other person
# has interests of their own? (2026-11-19, from a learner's report: a
# dementia-news situation played with a climber came out about climbing.)
# Runs the LIVE scene prompt (dumped by ScenePromptDumpTests) and an OLD
# variant rebuilt from it (the "what they talk about" label + COMMON GROUND
# block), prints every dialogue, and counts turns that mention the person's
# interest. READ the dialogues; the count is only a pointer.
#
#   scripts/scene-subject-probe.py <dump dir>       RUNS=3 LANGS=en,ko
# Reads GEMINI_API_KEY from gateway/.dev.vars.
import json, os, re, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = sys.argv[1]
RUNS = int(os.environ.get("RUNS", "3"))
LANGS = os.environ.get("LANGS", "en,ko").split(",")
MODEL = os.environ.get("MODEL", "gemini-3.6-flash")
KEY = re.search(r"GEMINI_API_KEY=\"?([^\"\n]+)", open(os.path.join(ROOT, "gateway/.dev.vars")).read()).group(1)
HIT = re.compile(r"climb|boulder|클라이밍|볼더링|암장|암벽", re.I)

def read(n): return open(os.path.join(DUMP, n)).read()

def old(user):
    ground = read("scene-ground.txt")
    user = user.replace("their own interests (who they are, NOT the subject of this scene):", "what they talk about:")
    return re.sub(r"THE SUBJECT IS THE SITUATION ABOVE.*?Never turn the scene toward them\.", lambda _: ground, user, flags=re.S)

def call(system, user):
    body = {"systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 3000,
                                 "thinkingConfig": {"thinkingLevel": "low"}}}
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    for _ in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=90))
            return json.loads(r["candidates"][0]["content"]["parts"][-1]["text"])
        except Exception as e:
            err = e
    return {"turns": [], "title": f"FAILED {err}"}

jobs = []
for lang in LANGS:
    system = read(f"scene-{lang}-system.txt")
    for case in ["news-stranger", "news-own", "landlord-stranger", "landlord-own"]:
        new = read(f"scene-{lang}-{case}.txt")
        for label, user in [("old", old(new)), ("new", new)]:
            for i in range(RUNS):
                jobs.append((lang, case, label, i, system, user))

with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(lambda j: (j, call(j[4], j[5])), jobs))

tally = {}
for (lang, case, label, i, _, _), out in results:
    turns = out.get("turns", [])
    hits = sum(1 for t in turns if HIT.search(t.get("text", "")))
    k = (lang, case, label); a = tally.setdefault(k, [0, 0, 0])
    a[0] += hits; a[1] += len(turns); a[2] += 1 if hits else 0
    print(f"\n=== {lang} {case} {label} #{i}  \"{out.get('title')}\"  interest turns {hits}/{len(turns)}")
    for t in turns:
        print(f"  {'*' if HIT.search(t.get('text','')) else ' '} {t.get('speaker','?')[:4]}: {t.get('text')}")
print("\n--- turns mentioning the person's interest / all turns (scenes with any)")
for k in sorted(tally):
    a = tally[k]; print(f"{k[0]} {k[1]:18} {k[2]}: {a[0]}/{a[1]}  ({a[2]}/{RUNS} scenes)")

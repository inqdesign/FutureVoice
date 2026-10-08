#!/usr/bin/env python3
"""Weekly test `translate` items, written by the live prompt from real slips.

Mirrors WeeklyTestEngine.translateItems' system prompt (keep in step) and
checks each item the way `translateItem` does: every required group's first
form in the answer, no avoided form in it. Prints the items for a person to
read — whether a sentence really needs the point is a judgment, not a check.

    python3 scripts/translate-quiz-probe.py [runs] [target] [native] [level]

Reads GEMINI_API_KEY from gateway/.dev.vars.
"""
import json, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"
NAMES = {"en": "English", "ko": "Korean", "de": "German", "ja": "Japanese"}

runs = int(sys.argv[1]) if len(sys.argv) > 1 else 2
target = sys.argv[2] if len(sys.argv) > 2 else "en"
native = sys.argv[3] if len(sys.argv) > 3 else "ko"
level = sys.argv[4] if len(sys.argv) > 4 else "B1"

# Real slips: the fixes a correction call makes on scripts/correction-cases-en.json.
SLIPS = [
    ("checking if that is consistent uh issue or temporal issue", "checking if it's a consistent issue or a temporary issue", "관사, temporary"),
    ("we finish only at midnight", "we only finished at midnight", "지난 일은 과거형"),
    ("I am working in a startup since three years", "I've been working at a startup for three years", "지금까지 이어지는 일은 현재완료 + for"),
    ("I take also some product decisions", "I also make some product decisions", "also 위치, make a decision"),
    ("explain him the situation", "explain the situation to him", "explain A to B"),
]
TOPICS = ["Moving to a new flat", "Work at a small startup"]
MAX = 3

t, n = NAMES[target], NAMES[native]
system = f"""You write a short translation quiz for a {t} learner whose own language is {n}, level {level}. They answer by laying word tiles in order. You get mistakes they really made. Pick up to {MAX} of them, each a DIFFERENT grammar point (skip pure word choice or a slip with no rule behind it), and for each write ONE new everyday sentence that cannot be said right without that grammar point.

Return {{"items":[{{"source":n,"point":"...","native":"...","answer":"...","orders":["..."],"decoys":["..."],"tip":"..."}}]}}
- source: the number of the mistake it is built on.
- native: the sentence in {n}, casual and spoken, the way they'd say it to a friend, 6–12 words, about ordinary life (these were their topics: {"; ".join(TOPICS)}). NOT their original sentence.
- answer: the most natural {t} way to say it, at their level, 5–12 words. Its words are the tiles, so there must be ONE wording: no optional words, nothing a learner could naturally say differently with other words.
- orders: every OTHER order of exactly the same words that is just as correct. Go through each time, place and duration phrase ("for two years", "yesterday", "at midnight") and each adverb, and list the sentence with it at the front too wherever that is natural — a learner who lays a right order and is marked wrong stops trusting the test. [] only if the order is truly fixed.
- decoys: 2–3 single words built from their mistake (e.g. "since", "am" for "I am working here since 2020") that make the sentence WRONG wherever they go, and are not in answer.
- point: the grammar point in {n}, 2–5 words. tip: one line in {n} on when it applies, at most 14 words.
JSON only."""
user = "\n".join(f'{i+1}. said "{w}" → should be "{c}" ({why})' for i, (w, c, why) in enumerate(SLIPS))

def norm(s):
    return " ".join(re.sub(r"[^\w\s']", " ", s.lower()).split())

def has(hay, needle):
    return f" {norm(needle)} " in f" {norm(hay)} "

for r in range(runs):
    body = {"systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 3000,
                                 "thinkingConfig": {"thinkingLevel": "low"}}}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"})
    out = json.load(urllib.request.urlopen(req, timeout=90))
    text = out["candidates"][0]["content"]["parts"][-1]["text"]
    items = json.loads(text)["items"]
    print(f"\n=== run {r+1}: {len(items)} items")
    for it in items:
        words = [norm(w) for w in it["answer"].split()]
        orders = [o for o in it.get("orders") or [] if sorted(norm(w) for w in o.split()) == sorted(words)]
        decoys = [d for d in it.get("decoys") or [] if len(d.split()) == 1 and norm(d) not in words]
        print(f"#{it['source']} {it['point']}")
        print(f"   {it['native']}")
        print(f"   → {it['answer']}")
        print(f"   orders kept={orders} (model gave {len(it.get('orders') or [])})")
        print(f"   decoys kept={decoys} (model gave {it.get('decoys')})")
        print(f"   tip: {it.get('tip')}")

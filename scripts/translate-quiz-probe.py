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
system = f"""You write a short translation quiz for a {t} learner whose own language is {n}, level {level}. You get mistakes they really made. Pick up to {MAX} of them, each a DIFFERENT grammar point (skip pure word choice or a slip with no rule behind it), and for each write ONE new everyday sentence that cannot be said right without that grammar point.

Return {{"items":[{{"source":n,"point":"...","native":"...","answer":"...","must":[["..."]],"avoid":["..."],"tip":"..."}}]}}
- source: the number of the mistake it is built on.
- native: the sentence in {n}, casual and spoken, the way they'd say it to a friend, 6–14 words, about ordinary life (these were their topics: {"; ".join(TOPICS)}). NOT their original sentence, and not a word-for-word copy of it.
- answer: the most natural {t} way to say it, at their level.
- must: the words in `answer` that show the grammar point and nothing else, 1–4 words each, as groups; a group lists the forms that are equally right ("I've been", "I have been"). Every group's first form must appear in `answer` exactly. As specific as the point allows ("explain the problem to", not "to"); never a word the learner could reasonably replace with a synonym.
- avoid: wrong forms of 2+ words this learner would produce, built the way their mistake was (e.g. "since five years"). Each must be wrong in ANY sentence — never a word that is right elsewhere ("since" alone, "finish" alone). Each must NOT be in answer.
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
        ok_must = all(any(has(it["answer"], f) for f in g[:1]) for g in it["must"])
        bad_avoid = [a for a in it.get("avoid") or [] if has(it["answer"], a)]
        flag = "OK " if ok_must and not bad_avoid else "DROP"
        print(f"[{flag}] #{it['source']} {it['point']}")
        print(f"   {it['native']}")
        print(f"   → {it['answer']}")
        print(f"   must={it['must']} avoid={it.get('avoid')}")
        print(f"   tip: {it.get('tip')}")

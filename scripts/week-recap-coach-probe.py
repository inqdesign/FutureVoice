#!/usr/bin/env python3
"""Run the "Your week" coach prompt against the real model on a sample week.

The system prompt is read OUT OF THE SWIFT SOURCE (WeekRecapCoach.write in
FutureVoice/Services/WeekRecap.swift), so what is probed is what ships. The
week is a fixture: a B1 Korean speaker learning English, a week of real-shaped
turns and the corrections they got. Prints the raw answer, then what survives
the same checks the app runs (a quoted example must be in the learner's own
lines, a leaned-on word is counted, a pattern needs two sentences).

Reads GEMINI_API_KEY from gateway/.dev.vars, like correction-probe.py.

    scripts/week-recap-coach-probe.py            # native ko
    NATIVE=ja scripts/week-recap-coach-probe.py
"""
import json, os, re, sys, urllib.request, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = {"ko": "Korean", "ja": "Japanese", "en": "English", "de": "German", "fr": "French",
         "es": "Spanish", "zh-Hant": "Traditional Chinese", "zh-Hans": "Simplified Chinese"}
native = os.environ.get("NATIVE", "ko")

src = open(os.path.join(ROOT, "FutureVoice/Services/WeekRecap.swift")).read()
body = src[src.index("let system = \"\"\"", src.index("enum WeekRecapCoach")):]
body = body[body.index('"""') + 3: body.index('"""', body.index('"""') + 3)]
lines = [l.strip() for l in body.strip("\n").split("\n")]
system = ""
for l in lines:
    system += (l[:-1] if l.endswith("\\") else l + "\n")
system = (system.replace("\\(targetName)", "English").replace("\\(nativeName)", NAMES[native])
          .replace("\\(evidence.level)", "B1"))

said = [
    "Yesterday I went to the new flat and the landlord says it's fine to move in early.",
    "I was very tired after the move, very very tired.",
    "Then she ask me if I want to sign the contract today.",
    "I think it is good, the flat is good for the price.",
    "I end up carrying most boxes myself because my friend was busy.",
    "We went to kitchen first and it was very small.",
    "I called landlord again because the boiler doesn't work.",
    "It's good, I think it's good for me.",
    "Last weekend I meet my friend Jenny and we talk about the rent.",
    "She says the rent in Berlin is very expensive now.",
    "I was very tired so I just stayed home on Sunday.",
    "I think I need to find a good way to save money.",
    "Do you know how can I get the deposit back?",
    "I want to know what should I say to the landlord.",
    "Yes, I think so. It's good idea.",
    "Actually I lived here since two years.",
    "My job is very busy these days, I work until very late.",
]
corrections = [
    ('the landlord says it\'s fine', 'the landlord said it was fine', 'past tense in a past story'),
    ('she ask me', 'she asked me', 'past tense'),
    ('I end up carrying', 'I ended up carrying', 'past tense after end up'),
    ('went to kitchen', 'went to the kitchen', 'article before a known place'),
    ('called landlord', 'called the landlord', 'article'),
    ('I meet my friend', 'I met my friend', 'past tense'),
    ('how can I get', 'how I can get', 'word order in an embedded question'),
    ('what should I say', 'what I should say', 'word order in an embedded question'),
    ("It's good idea", "It's a good idea", 'article'),
    ('I lived here since two years', "I've lived here for two years", 'present perfect with for'),
]
counts = collections.Counter(w for l in said for w in re.findall(r"[a-z']+", l.lower()))
frequent = ", ".join(f"{w} ×{n}" for w, n in counts.most_common(25) if n >= 2 and len(w) > 2)

user = f"""# LEARNER LEVEL (median of this week's per-talk reads, else the level they set)
B1

# EVERYTHING THE LEARNER SAID THIS WEEK (speech-to-text, one line per turn)
{chr(10).join(said)}

# CORRECTIONS THEY GOT THIS WEEK (their words → fixed, with the reason)
{chr(10).join(f'- "{a}" → "{b}" ({c})' for a, b, c in corrections)}

# FREQUENT WORDS (counted in code across their lines, with CEFR grade)
{frequent}

# ALREADY SHOWN ON EARLIER CARDS (don't restate)
used from studies: "end up"
new phrase from the fluent self: "catch up on"
"""

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"
req = {"system_instruction": {"parts": [{"text": system}]},
       "contents": [{"role": "user", "parts": [{"text": user}]}],
       "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 4096,
                            "thinkingConfig": {"thinkingLevel": "low"}}}
r = urllib.request.urlopen(urllib.request.Request(url, json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=120)
text = json.load(r)["candidates"][0]["content"]["parts"][0]["text"]
out = json.loads(text)
print(json.dumps(out, ensure_ascii=False, indent=2))

def norm(s): return re.sub(r"[^\w\s']", "", s.lower()).strip()
def in_lines(q): return bool(q) and any(norm(q) in norm(l) for l in said)
print("\n--- verification ---")
for p in out.get("grammar", []):
    ok = [e for e in p.get("examples", []) if in_lines(e.get("was", ""))]
    print(("KEEP " if len(ok) >= 2 else "DROP ") + p.get("rule", ""), f"({len(ok)}/{len(p.get('examples', []))} examples verified)")
for u in out.get("upgrades", []):
    n = sum(len(re.findall(r"(?<![a-z])" + re.escape(u["instead"].lower()) + r"(?![a-z])", l.lower())) for l in said)
    print(("KEEP " if n >= 2 else "DROP ") + f'{u["instead"]} ×{n} → {u["better"]}', "(line ok)" if in_lines(u.get("original", "")) else "(line NOT found)")
print("insight quote", "ok" if in_lines(out.get("insight_quote", "")) else "NOT found")

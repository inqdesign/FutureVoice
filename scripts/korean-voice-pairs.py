#!/usr/bin/env python3
# Pairwise accent judge for scripts/tts-korean-probe.sh output — the same
# Korean line from a NATIVE voice and a test voice, order shuffled, "which
# one has a foreign accent?". Built because the absolute judge
# (korean-voice-judge.py) rated an English-accented control 4.4/5: on a scale
# with no reference it calls everything native.
#
# Calibration rows come first and decide whether the rest means anything:
#   accent-control vs native   must be caught (the control IS accented)
#   native vs native           must come out "neither" / a coin flip
#
#   scripts/korean-voice-pairs.py <probe_dir> [runs=2]
import base64, csv, json, os, random, sys, urllib.request
import concurrent.futures as cf
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = sys.argv[1]
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 2
key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"

PROMPT = """Two recordings of the SAME Korean sentence, by two different speakers:
clip A first, then clip B. You are a Korean phonetics teacher. Ignore voice
timbre, gender and recording quality — judge only pronunciation: consonants
(평음/경음/격음, 받침, 연음), vowels, intonation and rhythm.
Does either speaker have a NON-NATIVE (foreign) accent?
Return JSON: {"accented": "A" | "B" | "both" | "neither",
              "evidence": "<the Korean word(s) and what was off, ≤ 20 words>"}"""

rows = list(csv.DictReader(open(os.path.join(DIR, "manifest.tsv")), delimiter="\t"))
by = {(r["voice"], r["line"], r["variant"]): r["file"] for r in rows}
lines = sorted({r["line"] for r in rows})

def b64(f): return base64.b64encode(open(os.path.join(DIR, f), "rb").read()).decode()

def ask(a, b):
    body = {"contents": [{"role": "user", "parts": [
                {"text": "Clip A:"}, {"inlineData": {"mimeType": "audio/mpeg", "data": b64(a)}},
                {"text": "Clip B:"}, {"inlineData": {"mimeType": "audio/mpeg", "data": b64(b)}},
                {"text": PROMPT}]}],
            "generationConfig": {"responseMimeType": "application/json",
                                 "thinkingConfig": {"thinkingLevel": "high"}}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    for _ in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=120))
            out = json.loads(r["candidates"][0]["content"]["parts"][0]["text"])
            return out[0] if isinstance(out, list) else out
        except Exception as e:
            err = e
    return {"accented": "error", "evidence": str(err)}

# (group, test voice, test variant, native reference voice) — same gender.
PAIRS = [("CAL accent-control vs native", "accent-control", "romanized", "ko-joon"),
         ("CAL native vs native",         "ko-sian",        "turbo",     "ko-joon")]
for v, ref in (("en-mark", "ko-joon"), ("en-emma", "ko-sian")):
    for variant in ("turbo", "turbo-ko", "multi"):
        PAIRS.append((f"{v} / {variant}", v, variant, ref))

jobs = []
for group, v, variant, ref in PAIRS:
    for line in lines:
        test, native = by.get((v, line, variant)), by.get((ref, line, "turbo"))
        if not test or not native: continue
        for run in range(RUNS):
            test_first = (run % 2 == 0) ^ (random.random() < 0.5)
            jobs.append((group, line, test_first, test, native))

def run(job):
    group, line, test_first, test, native = job
    a, b = (test, native) if test_first else (native, test)
    res = ask(a, b)
    verdict = res.get("accented")
    test_slot, native_slot = ("A", "B") if test_first else ("B", "A")
    return group, line, {
        "test_accented": verdict in (test_slot, "both"),
        "native_accented": verdict in (native_slot, "both"),
        "error": verdict == "error",
        "evidence": res.get("evidence", ""), "verdict": verdict}

with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(run, jobs))
json.dump([{"group": g, "line": l, **r} for g, l, r in results],
          open(os.path.join(DIR, "pairs.json"), "w"), ensure_ascii=False, indent=1)

agg = defaultdict(list)
for g, l, r in results:
    if not r["error"]: agg[g].append(r)
print(f"{'pair (test vs native)':<32} {'test accented':>14} {'native accented':>16}  n")
for group, *_ in PAIRS:
    rs = agg.get(group, [])
    if not rs: continue
    t = 100 * sum(r["test_accented"] for r in rs) / len(rs)
    n = 100 * sum(r["native_accented"] for r in rs) / len(rs)
    print(f"{group:<32} {t:>13.0f}% {n:>15.0f}%  {len(rs)}")

print("\nevidence quoted against the English voices (shipping turbo):")
for g, l, r in results:
    if g.endswith("/ turbo") and r["test_accented"]:
        print(f"  {g:<18} {l:<9} {r['evidence']}")

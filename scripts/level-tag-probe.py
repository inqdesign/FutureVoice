#!/usr/bin/env python3
# Measures the LEVEL TAGGING call (docs/personal-report-plan.md, step 1):
# given one talk, which level-map items did the LEARNER produce, right or
# wrong? Runs hand-labelled talks through Gemini with the app's settings and
# prints recall, verdict accuracy, trap hits (an item tagged that must not
# be — the AI's structure, a look-alike) and unlabelled extras to review.
#
#   scripts/level-tag-probe.py en scripts/level-tag-cases-en.json [runs]
#   MODEL=gemini-3.1-flash-lite … · THINKING=low … · --show (print prompt)
#
# The prompt is `LevelTagger.systemPrompt` (+ its grammarLine / functionLine
# templates), rebuilt from FutureVoice/Services/LevelTagger.swift so it cannot
# drift from what the app sends; thinking defaults to the app's level.
# Every quote the model returns is checked against the learner's own turns,
# as the app does (`LevelTagger.isTheirs` mirrors `theirs` below); an item
# whose quote isn't theirs is dropped before scoring. GEMINI_API_KEY from the
# environment, else gateway/.dev.vars.
import json, os, re, sys, time, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}
lang = sys.argv[1]
cases_path = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else None
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 1
level_map = json.load(open(os.path.join(ROOT, f"FutureVoice/Resources/LevelMap/level_map_{lang}.json")))


SRC = open(os.path.join(ROOT, "FutureVoice/Services/LevelTagger.swift")).read()


def swift_literal(fn):
    """The one-line string `static func <fn>(…)` returns, its `\\(x.field)`
    interpolations left in place for `fill`."""
    body = SRC[SRC.index("static func %s(" % fn):]
    return re.search(r'\{\s*"((?:[^"\\]|\\.)*)"\s*\}', body).group(1)


def fill(template, item):
    out = re.sub(r"\\\(\w+\.(\w+)\)", lambda m: str(item[m.group(1)]), template)
    return out.replace('\\"', '"')


def prompt(m, target):
    """`LevelTagger.systemPrompt`, rebuilt from the Swift source so the probe
    measures exactly what the app sends (the way correction-probe.py does)."""
    body = re.search(r'static func systemPrompt\(.*?return """\n(.*?)\n        """', SRC, re.S).group(1)
    text = "\n".join(l[8:] if l.startswith("        ") else l for l in body.splitlines())
    g = "\n".join(fill(swift_literal("grammarLine"), x) for x in m["grammar"])
    f = "\n".join(fill(swift_literal("functionLine"), x) for x in m["functions"])
    text = text.replace("\\(targetName)", target).replace("\\(grammarLines)", g).replace("\\(functionLines)", f)
    assert "\\(" not in text, text
    return text


SYSTEM = prompt(level_map, NAMES[lang])
if "--show" in sys.argv:
    print(SYSTEM)
    sys.exit()

# A worktree has no gateway/.dev.vars (gitignored): pass the key in the env.
key = os.environ.get("GEMINI_API_KEY") or next(
    l.split("=", 1)[1].strip().strip('"') for l in open(os.path.join(ROOT, "gateway/.dev.vars"))
    if l.startswith("GEMINI_API_KEY"))
# The app's own level (`LevelTagger.thinkingLevel`) unless THINKING says otherwise.
THINKING = os.environ.get("THINKING") or re.search(r'static let thinkingLevel = "(\w+)"', SRC).group(1)
MODEL = os.environ.get("MODEL", "gemini-3.6-flash")
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={key}"


def call(transcript):
    body = {"systemInstruction": {"parts": [{"text": SYSTEM}]},
            "contents": [{"role": "user", "parts": [{"text": transcript}]}],
            "generationConfig": {"maxOutputTokens": 4096, "responseMimeType": "application/json",
                                 "thinkingConfig": {"thinkingLevel": THINKING}}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    for attempt in range(4):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=90))
            text = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"] if not p.get("thought"))
            return json.loads(text)
        except Exception as e:
            if attempt == 3:
                return {"error": str(e)}
            time.sleep(2 + attempt * 3)


FILLERS = {"uh", "um", "er", "erm", "ah", "hmm", "mm", "eh"}


def norm(s):
    """Lowercase words, punctuation, fillers and stutters ("I am I am")
    removed — the transcriber's noise, which a quote may fairly leave out."""
    s = s.lower().replace("\u2019", "'")   # as LevelTagger.normalized: I’m == I'm
    words = [w for w in re.sub(r"[^\w\s']", " ", s).split() if w not in FILLERS]
    changed = True
    while changed:
        changed = False
        for n in (3, 2, 1):
            for i in range(len(words) - 2 * n + 1):
                if words[i:i + n] == words[i + n:i + 2 * n]:
                    del words[i + n:i + 2 * n]
                    changed = True
                    break
            if changed:
                break
    return " ".join(words)


def theirs(quote, user_lines):
    q = norm(quote)
    return bool(q) and any(q in norm(l) for l in user_lines)


cases = json.load(open(cases_path))
jobs = [(c, r) for c in cases for r in range(runs)]


def run(job):
    c, _ = job
    transcript = "\n".join(f"{who}: {text}" for who, text in c["turns"])
    return c, call(transcript)


tot = {"expected": 0, "found": 0, "verdict": 0, "direction": 0, "traps": 0, "extras": 0,
       "unverified": 0, "fexp": 0, "ffound": 0, "fextra": 0, "errors": 0}
extras_log = []
with cf.ThreadPoolExecutor(6) as ex:
    for c, out in ex.map(run, jobs):
        if "error" in out:
            tot["errors"] += 1
            print(f"!! {c['name']}: {out['error']}")
            continue
        users = [t for w, t in c["turns"] if w == "USER"]
        got = {}
        for item in out.get("grammar", []):
            if not isinstance(item, dict) or "id" not in item:
                tot["unverified"] += 1
                continue
            ok_q = item.get("right", 0) == 0 or theirs(item.get("right_quote", ""), users)
            bad_q = item.get("wrong", 0) == 0 or theirs(item.get("wrong_quote", ""), users)
            if not (ok_q and bad_q):
                tot["unverified"] += 1
                print(f"   {c['name']}: unverified quote for {item.get('id')}: {item.get('right_quote')!r} / {item.get('wrong_quote')!r}")
                continue
            got[item["id"]] = (item.get("right", 0), item.get("wrong", 0), item.get("right_quote", ""), item.get("wrong_quote", ""))
        lines = []
        for iid, want in c["expect"].items():
            tot["expected"] += 1
            if iid not in got:
                lines.append(f"   MISSED {iid} ({want})")
                continue
            tot["found"] += 1
            r, w = got[iid][0], got[iid][1]
            verdict = "ok" if w == 0 else ("wrong" if r == 0 else "mixed")
            if verdict == want:
                tot["verdict"] += 1
            else:
                lines.append(f"   VERDICT {iid}: want {want}, got right={r} wrong={w}  {got[iid][2]!r} / {got[iid][3]!r}")
            if (want in ("ok", "mixed") and r > 0) or (want == "wrong" and w > 0):
                tot["direction"] += 1
        for iid, v in got.items():
            if iid in c["expect"]:
                continue
            if iid in c["not"]:
                tot["traps"] += 1
                lines.append(f"   TRAP {iid}: right={v[0]} wrong={v[1]}  {v[2]!r} / {v[3]!r}")
            else:
                tot["extras"] += 1
                extras_log.append(f"{c['name']}: {iid} right={v[0]} wrong={v[1]}  {v[2]!r} / {v[3]!r}")
        fgot = {f["id"] for f in out.get("functions", []) if isinstance(f, dict) and "id" in f and theirs(f.get("quote", ""), users)}
        for fid in c["functions"]:
            tot["fexp"] += 1
            if fid in fgot:
                tot["ffound"] += 1
            else:
                lines.append(f"   MISSED function {fid}")
        tot["fextra"] += len(fgot - set(c["functions"]))
        print(f"{c['name']}" + ("" if lines else "  ✓"))
        for l in lines:
            print(l)

print("\nUNLABELLED EXTRAS (review — a label may be missing):")
for l in extras_log:
    print("  " + l)
e = max(1, tot["expected"])
print(f"""
{MODEL} thinking={THINKING} runs={runs}
grammar recall      {tot['found']}/{tot['expected']} ({100*tot['found']//e}%)
verdict exact       {tot['verdict']}/{tot['expected']}   direction right {tot['direction']}/{tot['expected']}
TRAPS tagged        {tot['traps']}
unlabelled extras   {tot['extras']}   unverified quotes dropped {tot['unverified']}
function recall     {tot['ffound']}/{tot['fexp']}   function extras {tot['fextra']}
errors              {tot['errors']}""")

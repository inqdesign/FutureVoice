#!/usr/bin/env python3
# Runs the app's LIVE correction prompt (`correctionOnlyPrompt`, rebuilt from
# ConversationEngine.swift so it cannot drift) through Gemini 3.6 Flash with
# the app's own generation settings, over spoken lines that are fine as
# speech ("ok") and lines with a real learner error ("err"). Prints every
# unnecessary correction and every missed error.
#
#   scripts/correction-probe.py ko scripts/correction-cases-ko.json 2
#   LEVEL=B2 EXTRA='...appended prompt text...' scripts/correction-probe.py ja cases.json
#   scripts/correction-probe.py de --show      # print the reconstructed prompt
#   NO_REGISTER=1 …                            # run without the speech-level guard
# Every run's full output lands in $OUT_DIR (default /tmp) as <cases>.out.json.
#
# Reads GEMINI_API_KEY from gateway/.dev.vars. Baselines (2026-09-25): see
# CLAUDE.md "The SPEECH LEVEL is the learner's".
import json, os, re, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FutureVoice/Services/ConversationEngine.swift")
src = open(SRC).read()
NAMES = {"ko": "Korean", "ja": "Japanese", "de": "German", "en": "English", "es": "Spanish", "fr": "French"}
lang = sys.argv[1]
target_name = NAMES[lang]

def literals(text):
    lits = re.findall(r'"((?:[^"\\]|\\.)*)"', text)
    return "".join(l.replace("\\n", "\n").replace('\\"', '"') for l in lits if len(l) > 3)

def swift_guard(fn):
    """Mirror a `xxxGuard(_ targetLanguage:)` function for `lang`: its guard
    line names the languages it applies to, `if base == "xx" {` blocks add
    language-specific text."""
    start = src.index("static func %s(" % fn)
    end = src.index("\n    }\n", start)
    body = src[start:end]
    head, _, rest = body.partition('return ""')
    guard_line = head[head.rindex("guard"):]
    if lang not in re.findall(r'"([a-z]{2})"', guard_line):
        return ""
    parts = re.split(r'if base == "([a-z]{2})" \{', rest)
    out = literals(parts[0])
    for code, block in zip(parts[1::2], parts[2::2]):
        if code == lang:
            out += literals(block.split("\n        }", 1)[0])
    return out

m = re.search(r'static func correctionOnlyPrompt\(.*?return """\n(.*?)\n        """', src, re.S)
prompt = "\n".join(l[8:] if l.startswith("        ") else l for l in m.group(1).splitlines())
prompt = (prompt.replace("\\(targetName)", target_name).replace("\\(nativeName)", "English")
  .replace("\\(level.rawValue)", os.environ.get("LEVEL", "A2"))
  .replace("\\(scriptGuard(targetLanguage))", swift_guard("scriptGuard"))
  .replace("\\(spacingGuard(targetLanguage))", swift_guard("spacingGuard"))
  .replace("\\(registerGuard(targetLanguage))", "" if os.environ.get("NO_REGISTER") else swift_guard("registerGuard")))
assert "\\(" not in prompt, prompt
prompt += os.environ.get("EXTRA", "")
if "--show" in sys.argv: print(prompt); sys.exit()

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"

def ask(line):
    body = {"systemInstruction": {"parts": [{"text": prompt}]},
            "contents": [{"role": "user", "parts": [{"text": line}]}],
            "generationConfig": {"maxOutputTokens": 512, "thinkingConfig": {"thinkingLevel": "low"},
                                  "responseMimeType": "application/json"}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    err = None
    for _ in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=60))
            return json.loads(r["candidates"][0]["content"]["parts"][0]["text"]).get("suggestion")
        except Exception as e:
            err = e
    return {"alternative": f"ERR {err}", "reason": ""}

cases = json.load(open(sys.argv[2]))
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 2
jobs = [(c, i) for c in cases for i in range(runs)]
with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(lambda ci: ask(ci[0]["line"]), jobs))
json.dump([{**c, "run": i, "suggestion": s} for (c, i), s in zip(jobs, results)],
          open(os.path.join(os.environ.get("OUT_DIR", "/tmp"),
                            os.path.basename(sys.argv[2]).replace(".json", ".out.json")), "w"),
          ensure_ascii=False, indent=1)
fp = fn = 0
for (c, i), s in zip(jobs, results):
    flagged = s is not None
    if c["expect"] == "ok" and flagged: fp += 1
    if c["expect"] == "err" and not flagged: fn += 1
    mark = "  " if (flagged == (c["expect"] == "err")) else "!!"
    print(f"{mark} [{c['expect']}] {c['line']}")
    if s: print(f"      -> {s.get('alternative')}\n         {s.get('reason')}")
n_ok = sum(1 for j in jobs if j[0]["expect"] == "ok"); n_err = len(jobs) - n_ok
print(f"\nfalse corrections on natural lines: {fp}/{n_ok}   missed real errors: {fn}/{n_err}")

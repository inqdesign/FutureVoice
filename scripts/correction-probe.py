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
# A case with "scene": true runs the prompt as a practice SCENE call
# (`politeSettingLine` with no counterpart, Korean only); every other case is
# a talk with the future self, where both per-call lines are empty.
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

def scene_line():
    """Mirror `politeSettingLine(_, counterpart: nil, inScene: true)`."""
    csrc = open(os.path.join(ROOT, "FutureVoice/Services/ConversationEngine+Character.swift")).read()
    start = csrc.index("static func politeSettingLine(")
    end = csrc.index("\n    }\n", start)
    body = csrc[start:end]
    guard_line = body[body.index("guard LanguageCatalog.base"):].split("\n", 1)[0]
    if lang not in re.findall(r'"([a-z]{2})"', guard_line):
        return ""
    who = re.search(r'who = "(a character in a practice scene[^"]*)"', body).group(1)
    text = body[body.index("var text ="):]
    return literals(text).replace("\\(who)", who)

REL = "\\(relationshipRegisterLine(targetLanguage, counterpart: counterpart))"
POLITE = "\\(politeSettingLine(targetLanguage, counterpart: counterpart, inScene: inScene))"
base_prompt = prompt.replace(REL, "")
prompt = base_prompt.replace(POLITE, "")
scene_prompt = base_prompt.replace(POLITE, scene_line())
assert "\\(" not in prompt, prompt
prompt += os.environ.get("EXTRA", "")
scene_prompt += os.environ.get("EXTRA", "")
if "--show" in sys.argv: print(scene_prompt if "--scene" in sys.argv else prompt); sys.exit()

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"

def content(case):
    """What the app sends (`requestRealtimeSuggestion`): the line said TO them
    as context, then their own line."""
    heard = case.get("heard", "")
    said = case["line"]
    return f'They were just told: "{heard}"\nThey said: "{said}"' if heard else f'They said: "{said}"'

def ask(line, system=None):
    body = {"systemInstruction": {"parts": [{"text": system or prompt}]},
            "contents": [{"role": "user", "parts": [{"text": line}]}],
            "generationConfig": {"maxOutputTokens": 900, "thinkingConfig": {"thinkingLevel": "low"},
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
    results = list(ex.map(lambda ci: ask(content(ci[0]), scene_prompt if ci[0].get("scene") else prompt), jobs))
json.dump([{**c, "run": i, "suggestion": s} for (c, i), s in zip(jobs, results)],
          open(os.path.join(os.environ.get("OUT_DIR", "/tmp"),
                            os.path.basename(sys.argv[2]).replace(".json", ".out.json")), "w"),
          ensure_ascii=False, indent=1)
# Since 2026-09-27 the suggestion answers TWO questions, so "was it flagged"
# is no longer the measure. A line that is grammatically perfect can still get
# a rewrite — that is the feature. What must hold:
#   - "ok" lines carry NO fixes (never accuse someone of a mistake they
#     didn't make). A rewrite on them is fine.
#   - "err" lines carry at least one fix (the mistake is named).
#   - every "alternative" covers the WHOLE line, not a fragment of it. This
#     is the reported bug: a 40-word turn answered by a 12-word clause, read
#     back by the teleprompter in place of the turn.
def words(t): return len([w for w in re.split(r"\s+", (t or "").strip()) if w])
SHORT, RATIO = 6, 0.6
def whole(alt, said):
    n = words(said)
    return True if n <= SHORT else words(alt) >= n * RATIO

# Two more things a fix must be, because a fix becomes a drill card and a
# card is credited by `CarryoverDetector.firstMatch`, which never matches
# under 3 tokens in a spaced language (1 in Japanese) — a two-word fix is a
# card that can never be marked used (Korean: 3 syllables, since
# 2026-10-04). And "was" has to be the learner's own
# words: a fix quoting something they didn't say accuses them of it.
MIN_TOK = 1 if lang == "ja" else 3
def norm(t): return re.sub(r"[^\w\s]", "", (t or "").lower()).strip()
def quoted(was, line):
    a, b = norm(was), norm(line)
    if a and a in b: return True
    if a.replace(" ", "") and a.replace(" ", "") in b.replace(" ", ""): return True
    aw = set(a.split()); bw = set(b.split())
    return len(aw) >= 3 and len(aw & bw) / len(aw) >= 0.75
short = unq = nfix = 0

fp = fn = frag = 0
for (c, i), s in zip(jobs, results):
    fixes = (s or {}).get("fixes") or []
    alt = (s or {}).get("alternative") or ""
    # "either": a line where a fix and no fix are both defensible (a usage
    # natives split on) — printed, never counted.
    bad_fix = c["expect"] == "ok" and fixes
    miss = c["expect"] == "err" and not fixes
    fragment = bool(alt) and not whole(alt, c["line"])
    if bad_fix: fp += 1
    if miss: fn += 1
    if fragment: frag += 1
    mark = "!!" if (bad_fix or miss or fragment) else "  "
    print(f"{mark} [{c['expect']}] {c['line']}")
    if alt: print(f"      -> {alt}   [{words(c['line'])}w -> {words(alt)}w]"
                  + ("  FRAGMENT" if fragment else ""))
    for f in fixes:
        nfix += 1
        # Korean credits by syllables, spaces ignored (`minKoreanSyllables`).
        is_short = (len(re.sub(r"[^가-힣]", "", f.get("now") or "")) < 3 if lang == "ko"
                    else words(f.get("now")) < MIN_TOK)
        is_unq = not quoted(f.get("was"), c["line"])
        short += is_short; unq += is_unq
        tag = ("  SHORT" if is_short else "") + ("  NOT-THEIRS" if is_unq else "")
        print(f"      fix: {f.get('was')} -> {f.get('now')}  ({f.get('why')}){tag}")
n_ok = sum(1 for j in jobs if j[0]["expect"] == "ok"); n_err = len(jobs) - n_ok
print(f"\nfalse grammar accusations: {fp}/{n_ok}   missed real errors: {fn}/{n_err}"
      f"   fragment rewrites: {frag}/{len(jobs)}"
      f"\nfixes too short to credit: {short}/{nfix}   fixes not quoting the learner: {unq}/{nfix}")

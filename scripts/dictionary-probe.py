#!/usr/bin/env python3
# The shared dictionary (supabase/functions/word-entry) on 3.6-flash vs Claude
# Haiku (2026-10-21). The prompts are read out of word-entry/index.ts, so the
# probe runs exactly what the function sends. Every entry is read twice: code
# checks (valid JSON, the fields the app decodes, examples in the target
# language and meanings in the native one, an expression's examples
# containing it verbatim) and a blind pairwise judge (Claude Sonnet).
# A dictionary entry is cached for EVERY learner, so a slip is permanent —
# read the losses, not only the tally.
#
#   scripts/dictionary-probe.py
#   RUNS=2 HAIKU_EFFORT=low scripts/dictionary-probe.py
import json, os, random, re, sys, time, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("OUT_DIR", "/tmp")
RUNS = int(os.environ.get("RUNS", "1"))
HAIKU = os.environ.get("HAIKU_MODEL", "claude-haiku-5-5")
HAIKU_EFFORT = os.environ.get("HAIKU_EFFORT", "")
JUDGE = os.environ.get("JUDGE_MODEL", "claude-sonnet-5-5")
GKEY = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
AKEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
SRC = open(os.path.join(ROOT, "supabase/functions/word-entry/index.ts")).read()
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}

def template(fn):
    body = SRC[SRC.index(f"function {fn}("):]
    body = body[body.index("return `") + 8:]
    return body[:body.index("`\n}")].replace("\\\n", "")

def prompt(kind, target, native):
    t = template("expressionPrompt" if kind == "expression" else "wordPrompt")
    return t.replace("${t}", NAMES[target]).replace("${n}", NAMES[native])

# (target, native, kind, text)
CASES = [
 ("en", "ko", "word", "deadline"), ("en", "ko", "word", "cover"), ("en", "ko", "word", "exhausted"),
 ("en", "ko", "word", "landlord"), ("en", "ko", "word", "pick"), ("en", "ko", "expression", "that covers everything"),
 ("en", "ko", "expression", "I'm swamped"), ("en", "ko", "expression", "on the same page"),
 ("en", "ja", "word", "awkward"), ("en", "ja", "expression", "it's not a big deal"),
 ("ko", "en", "word", "마감"), ("ko", "en", "word", "눈치"), ("ko", "en", "word", "피곤하다"),
 ("ko", "en", "expression", "말이 그렇지"), ("ko", "en", "expression", "그럴 만하다"),
 ("ja", "ko", "word", "締め切り"), ("ja", "ko", "word", "気まずい"), ("ja", "ko", "expression", "よろしくお願いします"),
 ("de", "ko", "word", "Frist"), ("de", "ko", "word", "erschöpft"), ("de", "ko", "expression", "Das ist mir Wurst"),
 ("de", "ko", "expression", "Ich bin gespannt"),
 ("es", "ko", "word", "plazo"), ("es", "ko", "word", "agotado"), ("es", "ko", "expression", "me da igual"),
]

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    err = None
    for attempt in range(4):
        try:
            return json.load(urllib.request.urlopen(req, timeout=90))
        except Exception as e:
            err = e; time.sleep(2 * (attempt + 1))
    raise err

def flash(system, text):
    t0 = time.time()
    j = post(f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={GKEY}", {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": text}]}],
        "generationConfig": {"maxOutputTokens": 900, "thinkingConfig": {"thinkingLevel": "low"},
                             "responseMimeType": "application/json"}}, {})
    raw = "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"] if not p.get("thought"))
    return raw, time.time() - t0, j.get("candidates", [{}])[0].get("finishReason")

def haiku(system, text):
    t0 = time.time()
    body = {"model": HAIKU, "max_tokens": 2000, "system": system + "\n\nAnswer with the JSON object only.",
            "messages": [{"role": "user", "content": text}]}
    if HAIKU_EFFORT: body["output_config"] = {"effort": HAIKU_EFFORT}
    j = post("https://api.anthropic.com/v1/messages", body, {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    return raw, time.time() - t0, j.get("stop_reason")

SCRIPT = {"ko": r"[가-힣]", "ja": r"[ぁ-んァ-ン一-龯]"}
def in_script(s, lang):
    if lang in SCRIPT: return bool(re.search(SCRIPT[lang], s or ""))
    return not re.search(r"[가-힣ぁ-んァ-ン]", s or "") and bool(re.search(r"[A-Za-zÀ-ÿ]", s or ""))

def checks(target, native, kind, text, raw):
    a, b = raw.find("{"), raw.rfind("}")
    try:
        d = json.loads(raw[a:b + 1])
    except Exception:
        return None, ["bad-json"]
    flags = []
    for k in ("pos", "senses", "examples", "phrases"):
        if k not in d: flags.append(f"missing-{k}")
    for s in d.get("senses") or []:
        if not in_script(s.get("meaning", ""), native): flags.append("meaning-not-native")
    for e in d.get("examples") or []:
        if not in_script(e.get("text", ""), target): flags.append("example-not-target")
        if not in_script(e.get("meaning", ""), native): flags.append("example-meaning-not-native")
        if kind == "expression" and text.lower().rstrip(".!?") not in (e.get("text") or "").lower():
            flags.append("example-missing-chunk")
    for p in d.get("phrases") or []:
        if not in_script(p.get("phrase", ""), target): flags.append("phrase-not-target")
    return d, sorted(set(flags))

JUDGE_PROMPT = """Two learner's-dictionary entries for the {kind} "{text}" ({target}), written for a native {native} speaker. Meanings and notes must be in {native}; examples and phrases in {target}; examples must be natural SPOKEN {target}; an expression's examples must contain it verbatim; cover the distinct common senses without padding; be accurate.

Entry A:
{a}

Entry B:
{b}

Which entry is better for the learner? Accuracy first (a wrong meaning or an unnatural example is worse than a missing nuance), then naturalness, then concision. Return JSON only:
{{"better": "A" | "B" | "tie", "problems_A": "short, or empty", "problems_B": "short, or empty"}}"""

def judge(c, a, b):
    target, native, kind, text = c
    j = post("https://api.anthropic.com/v1/messages", {
        "model": JUDGE, "max_tokens": 700, "output_config": {"effort": "low"},
        "messages": [{"role": "user", "content": JUDGE_PROMPT.format(kind=kind, text=text, target=NAMES[target],
                                                                    native=NAMES[native], a=a, b=b)}]},
        {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(x.get("text", "") for x in j["content"] if x.get("type") == "text")
    try: return json.loads(raw[raw.find("{"):raw.rfind("}") + 1])
    except Exception: return {"better": "?", "problems_A": raw[:120], "problems_B": ""}

def run(job):
    c, run_i = job
    target, native, kind, text = c
    system = prompt(kind, target, native)
    fr, fs, fstop = flash(system, text)
    hr, hs, hstop = haiku(system, text)
    fd, ff = checks(target, native, kind, text, fr)
    hd, hf = checks(target, native, kind, text, hr)
    v = None
    if fd and hd:
        swap = random.random() < 0.5
        a, b = (hd, fd) if swap else (fd, hd)
        r = judge(c, json.dumps(a, ensure_ascii=False, indent=1), json.dumps(b, ensure_ascii=False, indent=1))
        v = {"better": {"A": "haiku" if swap else "flash", "B": "flash" if swap else "haiku"}.get(r.get("better"), r.get("better")),
             "flash_problems": r.get("problems_B" if swap else "problems_A", ""),
             "haiku_problems": r.get("problems_A" if swap else "problems_B", "")}
    return {"case": c, "run": run_i, "flash": fr, "flash_s": fs, "flash_stop": fstop, "flash_flags": ff,
            "haiku": hr, "haiku_s": hs, "haiku_stop": hstop, "haiku_flags": hf, "verdict": v}

jobs = [(c, r) for c in CASES for r in range(RUNS)]
with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "6"))) as pool:
    results = list(pool.map(run, jobs))

print(f"haiku={HAIKU} effort={HAIKU_EFFORT or 'default'}  {len(results)} entries")
for m in ("flash", "haiku"):
    fl = {}
    for r in results:
        for f in r[f"{m}_flags"]: fl[f] = fl.get(f, 0) + 1
    stops = {}
    for r in results: stops[r[f"{m}_stop"]] = stops.get(r[f"{m}_stop"], 0) + 1
    ts = sorted(r[f"{m}_s"] for r in results)
    print(f"  {m:6} median {ts[len(ts)//2]:.1f}s  flags {fl or '-'}  stops {stops}")
vs = [r["verdict"]["better"] for r in results if r["verdict"]]
print(f"  judge: haiku better {vs.count('haiku')} · flash better {vs.count('flash')} · tie {vs.count('tie')}")
print("\n--- every loss for haiku and every flag (read them) ---")
for r in results:
    v = r["verdict"] or {}
    if v.get("better") == "flash" or r["haiku_flags"] or r["flash_flags"]:
        print(f"[{'/'.join(r['case'][:3])} {r['case'][3]}] {v.get('better')}  flash{r['flash_flags']} haiku{r['haiku_flags']}\n"
              f"      haiku problems: {v.get('haiku_problems', '')}\n      flash problems: {v.get('flash_problems', '')}")
out = os.path.join(OUT, "dictionary-probe.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("→", out)

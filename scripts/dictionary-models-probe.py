#!/usr/bin/env python3
# Which model should write the shared dictionary (supabase/functions/word-entry)?
# (2026-11-19: 3.6-flash doubles in price on 2027-01-01, and it wrote
# "해깔리게" into a cached entry.) Runs the function's own prompts, read out of
# word-entry/index.ts, on several candidates. Every entry is read by a blind
# reader (Claude Opus) who lists what is WRONG in it: meaning, example,
# spelling of the native-language text, wrong language. An entry is cached for
# every learner, so read the serious problems, not only the tally.
#
#   scripts/dictionary-models-probe.py            RUNS=2 PAR=8 MODELS=flash,haiku
import json, os, re, sys, time, urllib.request, urllib.error, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("OUT_DIR", "/tmp")
RUNS = int(os.environ.get("RUNS", "2"))
READER = os.environ.get("READER_MODEL", "claude-opus-5-5")
GKEY = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
AKEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
OKEY = open(os.path.expanduser("~/keys/openai.txt")).read().strip()
SRC = open(os.path.join(ROOT, "supabase/functions/word-entry/index.ts")).read()
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish", "fr": "French"}

# name: (kind, model id, $ per 1M input, $ per 1M output incl. thinking) — list prices 2026-11-19
MODELS = {
    "flash-3.6":      ("gemini", "gemini-3.6-flash",      0.75, 3.75),   # doubles 2027-01-01
    "flash-lite-3.1": ("gemini", "gemini-3.1-flash-lite", 0.25, 1.50),
    "flash-lite-3.5": ("gemini", "gemini-3.5-flash-lite", 0.30, 2.50),
    "haiku-5.5":      ("claude", "claude-haiku-5-5",      0.10, 0.50),
    "haiku-5.5-low":  ("claude", "claude-haiku-5-5",      0.10, 0.50),
    "gpt-6-luna":     ("openai", "gpt-6-luna",            0.10, 0.50),
    "gpt-6.1-terra":  ("openai", "gpt-6.1-terra",         1.00, 5.00),
}
PICK = [m for m in os.environ.get("MODELS", ",".join(MODELS)).split(",") if m in MODELS]

def template(fn):
    body = SRC[SRC.index(f"function {fn}("):]
    body = body[body.index("return `") + 8:]
    return body[:body.index("`\n}")].replace("\\\n", "")

def prompt(kind, target, native):
    t = template("expressionPrompt" if kind == "expression" else "wordPrompt")
    return t.replace("${t}", NAMES[target]).replace("${n}", NAMES[native])

# (target, native, kind, text). Mostly English for Korean speakers: that is most learners.
CASES = [
 ("en", "ko", "word", "deadline"), ("en", "ko", "word", "cover"), ("en", "ko", "word", "exhausted"),
 ("en", "ko", "word", "landlord"), ("en", "ko", "word", "pick"), ("en", "ko", "word", "confusing"),
 ("en", "ko", "word", "awkward"), ("en", "ko", "word", "reluctant"), ("en", "ko", "word", "chore"),
 ("en", "ko", "expression", "string us along"), ("en", "ko", "expression", "that covers everything"),
 ("en", "ko", "expression", "I'm swamped"), ("en", "ko", "expression", "on the same page"),
 ("en", "ko", "expression", "it slipped my mind"), ("en", "ko", "expression", "I can't wrap my head around it"),
 ("en", "ko", "expression", "push back"), ("en", "ko", "expression", "end up doing"),
 ("en", "ko", "expression", "a hundred active users"), ("en", "ko", "expression", "mix them up"),
 ("en", "ja", "word", "awkward"), ("en", "ja", "expression", "it's not a big deal"),
 ("ko", "en", "word", "마감"), ("ko", "en", "word", "눈치"), ("ko", "en", "expression", "말이 그렇지"),
 ("ko", "en", "expression", "그럴 만하다"),
 ("ja", "ko", "word", "気まずい"), ("ja", "ko", "expression", "よろしくお願いします"),
 ("de", "ko", "word", "erschöpft"), ("de", "ko", "expression", "Das ist mir Wurst"),
 ("de", "ko", "expression", "Ich bin gespannt"),
 ("es", "ko", "word", "agotado"), ("es", "ko", "expression", "me da igual"),
 ("fr", "ko", "word", "épuisé"), ("fr", "ko", "expression", "ça marche"),
]

if os.environ.get("ONLY"):   # ONLY=9,10: case indexes, for a quick run
    CASES = [CASES[int(i)] for i in os.environ["ONLY"].split(",")]

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    err = None
    for attempt in range(4):
        try:
            return json.load(urllib.request.urlopen(req, timeout=120))
        except urllib.error.HTTPError as e:
            err = RuntimeError(f"{e.code} {e.read()[:300]!r}")
            if e.code in (400, 401, 403, 404): raise err
            time.sleep(3 * (attempt + 1))
        except Exception as e:
            err = e; time.sleep(3 * (attempt + 1))
    raise err

def write(name, system, text):
    kind, model, _, _ = MODELS[name]
    t0 = time.time()
    if kind == "gemini":
        j = post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GKEY}", {
            "system_instruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": text}]}],
            "generationConfig": {"maxOutputTokens": 900, "thinkingConfig": {"thinkingLevel": "low"},
                                 "responseMimeType": "application/json"}}, {})
        raw = "".join(p.get("text", "") for p in j["candidates"][0]["content"].get("parts", []) if not p.get("thought"))
        u = j.get("usageMetadata", {})
        tin, tout = u.get("promptTokenCount", 0), u.get("candidatesTokenCount", 0) + u.get("thoughtsTokenCount", 0)
    elif kind == "claude":
        body = {"model": model, "max_tokens": 2500, "system": system + "\n\nAnswer with the JSON object only.",
                "messages": [{"role": "user", "content": text}]}
        if name.endswith("-low"): body["output_config"] = {"effort": "low"}
        j = post("https://api.anthropic.com/v1/messages", body, {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
        raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
        tin, tout = j["usage"]["input_tokens"], j["usage"]["output_tokens"]
    else:
        j = post("https://api.openai.com/v1/chat/completions", {
            "model": model, "max_completion_tokens": 2500, "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": text}]},
            {"authorization": f"Bearer {OKEY}"})
        raw = j["choices"][0]["message"].get("content") or ""
        tin, tout = j["usage"]["prompt_tokens"], j["usage"]["completion_tokens"]
    return raw, time.time() - t0, tin, tout

SCRIPT = {"ko": r"[가-힣]", "ja": r"[ぁ-んァ-ン一-龯]"}
def in_script(s, lang):
    if lang in SCRIPT: return bool(re.search(SCRIPT[lang], s or ""))
    return not re.search(r"[가-힣ぁ-んァ-ン]", s or "") and bool(re.search(r"[A-Za-zÀ-ÿ]", s or ""))

def checks(target, native, kind, text, raw):
    a, b = raw.find("{"), raw.rfind("}")
    try: d = json.loads(raw[a:b + 1])
    except Exception: return None, ["bad-json"]
    flags = []
    for k in ("pos", "senses", "examples", "phrases"):
        if k not in d: flags.append(f"missing-{k}")
    if not d.get("senses"): flags.append("no-senses")
    for s in d.get("senses") or []:
        if not in_script(s.get("meaning", ""), native): flags.append("meaning-not-native")
    for e in d.get("examples") or []:
        if not in_script(e.get("text", ""), target): flags.append("example-not-target")
        if kind == "expression" and text.lower().rstrip(".!?") not in (e.get("text") or "").lower():
            flags.append("example-missing-chunk")
    for p in d.get("phrases") or []:
        if not in_script(p.get("phrase", ""), target): flags.append("phrase-not-target")
    return d, sorted(set(flags))

READ = """You are proofreading one entry of a learner's dictionary before it is published to every learner. It explains the {target} {kind} "{text}" to a native {native} speaker. Meanings, notes and translations must be in {native}; examples and variant phrases in {target}.

{entry}

List every real problem. Be strict about facts, not about style:
- "meaning": a meaning or note that is wrong, misleading, or explains a word inside the expression instead of the whole.
- "example": an example or variant in {target} that a native speaker would not say, misuses the {kind}, or whose translation is wrong.
- "spelling": a misspelling, non-word or wrong spacing in the {native} text (quote it), or in the {target} text.
- "language": text in the wrong language.
severity "serious" = a learner would learn something false or see an obvious error; "minor" = a blemish.
An entry with nothing wrong gets an empty list. Do not invent problems. Return JSON only:
{{"problems": [{{"type": "meaning|example|spelling|language", "severity": "serious|minor", "quote": "...", "why": "short"}}]}}"""

def read(c, d):
    target, native, kind, text = c
    j = post("https://api.anthropic.com/v1/messages", {
        "model": READER, "max_tokens": 4000,
        "messages": [{"role": "user", "content": READ.format(
            kind=kind, text=text, target=NAMES[target], native=NAMES[native],
            entry=json.dumps(d, ensure_ascii=False, indent=1))}]},
        {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(x.get("text", "") for x in j["content"] if x.get("type") == "text")
    try: return json.loads(raw[raw.find("{"):raw.rfind("}") + 1]).get("problems", [])
    except Exception: return [{"type": "reader", "severity": "minor", "quote": "", "why": "reader answer unreadable"}]

def run(job):
    name, c, i = job
    target, native, kind, text = c
    try:
        raw, secs, tin, tout = write(name, prompt(kind, target, native), text)
    except Exception as e:
        return {"model": name, "case": c, "run": i, "error": str(e)[:300]}
    d, flags = checks(target, native, kind, text, raw)
    problems = read(c, d) if d else []
    return {"model": name, "case": c, "run": i, "entry": d, "raw": None if d else raw[:400], "flags": flags,
            "problems": problems, "secs": secs, "tin": tin, "tout": tout}

jobs = [(m, c, r) for m in PICK for c in CASES for r in range(RUNS)]
with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "8"))) as pool:
    results = list(pool.map(run, jobs))
out = os.path.join(OUT, "dictionary-models-probe.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)

print(f"{len(CASES)} cases x {RUNS} runs, reader {READER}\n")
print(f"{'model':16} {'ok':>5} {'serious':>8} {'entries w/ serious':>19} {'spelling':>9} {'minor':>6} {'flags':>6} {'median s':>9} {'$ / 1000 entries':>17}")
for m in PICK:
    rs = [r for r in results if r["model"] == m]
    ok = [r for r in rs if r.get("entry")]
    errs = [r for r in rs if "error" in r]
    ser = [p for r in ok for p in r["problems"] if p.get("severity") == "serious"]
    with_ser = sum(1 for r in ok if any(p.get("severity") == "serious" for p in r["problems"]))
    spell = sum(1 for r in ok for p in r["problems"] if p.get("type") == "spelling")
    minor = sum(1 for r in ok for p in r["problems"] if p.get("severity") == "minor")
    flags = sum(1 for r in rs if r.get("flags"))
    ts = sorted(r["secs"] for r in ok) or [0]
    _, _, pin, pout = MODELS[m]
    cost = sum(r["tin"] * pin + r["tout"] * pout for r in rs if "tin" in r) / 1e6 / max(1, len(rs) - len(errs)) * 1000
    print(f"{m:16} {len(ok):>2}/{len(rs):<2} {len(ser):>8} {with_ser:>19} {spell:>9} {minor:>6} {flags:>6} {ts[len(ts)//2]:>9.1f} {cost:>17.2f}"
          + (f"   errors: {errs[0]['error'][:90]}" if errs else ""))
print("\n--- every serious problem, spelling problem and code flag (read them) ---")
for r in results:
    if r.get("flags") or any(p.get("severity") == "serious" or p.get("type") == "spelling" for p in r.get("problems", [])):
        print(f"[{r['model']}] {'/'.join(r['case'][:3])} \"{r['case'][3]}\"  flags {r['flags']}")
        for p in r["problems"]:
            if p.get("severity") == "serious" or p.get("type") == "spelling":
                print(f"     {p.get('severity')} {p.get('type')}: {p.get('quote')}  — {p.get('why')}")
print("→", out)

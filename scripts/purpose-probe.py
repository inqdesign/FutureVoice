#!/usr/bin/env python3
# One app purpose on 3.6-flash vs Claude Haiku, from requests the APP built
# (2026-10-21). A capture test (e.g. SummaryCaptureTests) calls the real
# engine with GeminiClient's DEBUG capture on, so every file under
# /tmp/fv-capture/<purpose>/ is the exact body the edge function would get.
# Each request goes to Gemini as written and to Claude the way the edge
# function translates it (_shared/claude-correction.ts: system + "Answer with
# the JSON object only.", JSON cut out of the text). Every answer is read:
# code checks per purpose, and a blind pairwise judge (Claude Sonnet) with
# that purpose's rubric. Read the losses, not only the tally.
#
#   TEST_RUNNER_CAPTURE_DIR=/tmp/fv-capture xcodebuild test … -only-testing:FutureVoiceTests/SummaryCaptureTests
#   scripts/purpose-probe.py summary
#   RUNS=2 HAIKU_EFFORT=low scripts/purpose-probe.py summary
import glob, json, os, random, re, sys, time, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PURPOSE = sys.argv[1]
CAPTURE = os.environ.get("CAPTURE_DIR", "/tmp/fv-capture")
OUT = os.environ.get("OUT_DIR", "/tmp")
RUNS = int(os.environ.get("RUNS", "1"))
HAIKU = os.environ.get("HAIKU_MODEL", "claude-haiku-5-5")
HAIKU_EFFORT = os.environ.get("HAIKU_EFFORT", "")
JUDGE = os.environ.get("JUDGE_MODEL", "claude-sonnet-5-5")
GKEY = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
AKEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()

RUBRICS = {
 "summary": """This is an end-of-talk summary for a language learner: corrections of what THEY said (each quoting their words), expressions they used, expressions the fluent self offered, a scorecard with a CEFR estimate, and durable facts about their life ("about_user"). Judge, in order:
1. Corrections: no false accusations (a line that is fine as casual speech flagged as an error), no missed real errors, each correction's quote is the learner's own words and the fix is natural.
2. Scorecard: plausible CEFR level and scores for what was actually said; notes in the learner's NATIVE language.
3. about_user: only facts the learner actually said, nothing invented.
4. Everything else: expressions are reusable, accurate, in the right language.""",
}

def strip_json(raw):
    a, b = raw.find("{"), raw.rfind("}")
    return raw[a:b + 1] if a >= 0 and b > a else raw

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    err = None
    for attempt in range(4):
        try:
            return json.load(urllib.request.urlopen(req, timeout=240))
        except Exception as e:
            err = e; time.sleep(3 * (attempt + 1))
    raise err

def gemini(req):
    body = {k: v for k, v in req.items() if k not in ("model", "purpose", "stream")}
    t0 = time.time()
    j = post(f"https://generativelanguage.googleapis.com/v1beta/models/{req['model']}:generateContent?key={GKEY}", body, {})
    raw = "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"] if not p.get("thought"))
    u = j.get("usageMetadata", {})
    return raw, time.time() - t0, {"in": u.get("promptTokenCount", 0), "out": u.get("candidatesTokenCount", 0) + u.get("thoughtsTokenCount", 0)}

def claude(req):
    system = "".join(p.get("text", "") for p in req["system_instruction"]["parts"])
    msgs = []
    for c in req["contents"]:
        role = "assistant" if c["role"] == "model" else "user"
        text = "".join(p.get("text", "") for p in c["parts"])
        if msgs and msgs[-1]["role"] == role: msgs[-1]["content"] += "\n" + text
        else: msgs.append({"role": role, "content": text})
    json_mode = req.get("generationConfig", {}).get("responseMimeType") == "application/json"
    body = {"model": HAIKU, "max_tokens": req.get("generationConfig", {}).get("maxOutputTokens", 4096),
            "system": system + ("\n\nAnswer with the JSON object only." if json_mode else ""), "messages": msgs}
    if HAIKU_EFFORT: body["output_config"] = {"effort": HAIKU_EFFORT}
    t0 = time.time()
    j = post("https://api.anthropic.com/v1/messages", body, {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    u = j.get("usage", {})
    return (strip_json(raw) if json_mode else raw), time.time() - t0, {"in": u.get("input_tokens", 0), "out": u.get("output_tokens", 0), "stop": j.get("stop_reason")}

def learner_lines(req):
    text = "".join(p.get("text", "") for c in req["contents"] for p in c["parts"])
    return [l[len("[USER] "):] for l in text.splitlines() if l.startswith("[USER] ")]

def quotes(obj):
    """Every string a summary claims the learner said."""
    out = []
    def walk(x, key=""):
        if isinstance(x, dict):
            for k, v in x.items(): walk(v, k)
        elif isinstance(x, list):
            for v in x: walk(v, key)
        elif isinstance(x, str) and key in ("quote", "user_said"):
            out.append(x)
    walk(obj)
    return out

def norm(s):
    return re.sub(r"[\s\.,!?。、！？…\"'“”‘’]", "", s.lower())

def checks(req, raw):
    flags = []
    try:
        d = json.loads(raw)
    except Exception:
        return None, ["bad-json"], []
    keys = list(d.keys()) if isinstance(d, dict) else []
    if PURPOSE == "summary":
        said = [norm(l) for l in learner_lines(req)]
        bad = [q for q in quotes(d) if q and not any(norm(q) in s for s in said)]
        if bad: flags.append(f"quote-not-said:{len(bad)}")
    return d, flags, keys

JUDGE_PROMPT = """{rubric}

The request the model answered (system prompt omitted; this is the input it was given):
<<<
{user}
>>>

Answer A:
{a}

Answer B:
{b}

Which answer is better? Return JSON only:
{{"better": "A" | "B" | "tie", "problems_A": "short, or empty", "problems_B": "short, or empty"}}"""

def judge(req, a, b):
    user = "".join(p.get("text", "") for c in req["contents"] for p in c["parts"])
    j = post("https://api.anthropic.com/v1/messages", {
        "model": JUDGE, "max_tokens": 1500, "output_config": {"effort": "low"},
        "messages": [{"role": "user", "content": JUDGE_PROMPT.format(rubric=RUBRICS.get(PURPOSE, "Judge correctness first, then usefulness to a language learner."), user=user[:20000], a=a, b=b)}]},
        {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(x.get("text", "") for x in j["content"] if x.get("type") == "text")
    try: return json.loads(strip_json(raw))
    except Exception: return {"better": "?", "problems_A": raw[:150], "problems_B": ""}

files = sorted(glob.glob(os.path.join(CAPTURE, PURPOSE, "*.json")))
if not files: sys.exit(f"no captures in {CAPTURE}/{PURPOSE}")

def run(job):
    f, run_i = job
    req = json.load(open(f))
    try: gr, gs, gu = gemini(req)
    except Exception as e: gr, gs, gu = f"<error {e}>", 0, {}
    try: cr, cs, cu = claude(req)
    except Exception as e: cr, cs, cu = f"<error {e}>", 0, {}
    gd, gf, gk = checks(req, gr)
    cd, cfl, ck = checks(req, cr)
    if gk and ck and gk != ck: cfl.append("key-order" if set(gk) == set(ck) else "keys-differ")
    v = None
    if gd is not None and cd is not None:
        swap = random.random() < 0.5
        a, b = (cd, gd) if swap else (gd, cd)
        r = judge(req, json.dumps(a, ensure_ascii=False, indent=1), json.dumps(b, ensure_ascii=False, indent=1))
        v = {"better": {"A": "haiku" if swap else "flash", "B": "flash" if swap else "haiku"}.get(r.get("better"), r.get("better")),
             "flash_problems": r.get("problems_B" if swap else "problems_A", ""),
             "haiku_problems": r.get("problems_A" if swap else "problems_B", "")}
    return {"file": os.path.basename(f), "run": run_i, "flash": gr, "flash_s": gs, "flash_usage": gu, "flash_flags": gf,
            "flash_keys": gk, "haiku": cr, "haiku_s": cs, "haiku_usage": cu, "haiku_flags": cfl, "haiku_keys": ck, "verdict": v}

with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "4"))) as pool:
    results = list(pool.map(run, [(f, r) for f in files for r in range(RUNS)]))

print(f"{PURPOSE}: {len(results)} answers · haiku={HAIKU} effort={HAIKU_EFFORT or 'default'}")
for m in ("flash", "haiku"):
    fl = {}
    for r in results:
        for x in r[f"{m}_flags"]: fl[x.split(":")[0]] = fl.get(x.split(":")[0], 0) + 1
    ts = sorted(r[f"{m}_s"] for r in results)
    ins = sum(r[f"{m}_usage"].get("in", 0) for r in results); outs = sum(r[f"{m}_usage"].get("out", 0) for r in results)
    price = (0.75, 3.75) if m == "flash" else (0.10, 0.50)
    usd = (ins * price[0] + outs * price[1]) / 1e6
    print(f"  {m:6} median {ts[len(ts)//2]:.1f}s  flags {fl or '-'}  tokens in {ins} out {outs}  ≈ ${usd:.4f}")
vs = [r["verdict"]["better"] for r in results if r["verdict"]]
print(f"  judge: haiku better {vs.count('haiku')} · flash better {vs.count('flash')} · tie {vs.count('tie')}")
print("\n--- every answer haiku lost, and every flag ---")
for r in results:
    v = r["verdict"] or {}
    if v.get("better") != "haiku" or r["haiku_flags"] or r["flash_flags"]:
        print(f"[{r['file']} #{r['run']}] {v.get('better')}  flash{r['flash_flags']} haiku{r['haiku_flags']}\n"
              f"      haiku problems: {v.get('haiku_problems', '')}\n      flash problems: {v.get('flash_problems', '')}")
out = os.path.join(OUT, f"{PURPOSE}-probe.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("→", out)

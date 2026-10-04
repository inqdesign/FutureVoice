#!/usr/bin/env python3
# Blind Gemini judge for scripts/tts-korean-probe.sh output.
#
# Two separate calls per file, so neither can lean on the other:
#   1. TRANSCRIBE — the audio only, no text. Character error rate against
#      the line that was synthesized (spaces and punctuation ignored, since
#      띄어쓰기 is a writer's choice) = how intelligible it is.
#   2. ACCENT — the audio only: 1–5 native-likeness, whether there is a
#      foreign accent, the likely first language, and the words that gave
#      it away.
# The native Korean voices (ko-*) are the control: if they don't come out on
# top, the judge can't hear what we're asking and ears decide.
#
#   scripts/korean-voice-judge.py <probe_dir> [runs=2]
# Reads GEMINI_API_KEY from gateway/.dev.vars. Writes <probe_dir>/judge.json.
import base64, csv, json, os, re, statistics, sys, urllib.request
import concurrent.futures as cf
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = sys.argv[1]
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 2
key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"

TRANSCRIBE = ("Transcribe this Korean speech exactly as spoken, in Hangul. "
              "Write what you hear, not what would make sense. "
              'Return JSON: {"text": "..."}')
ACCENT = """You are a Korean phonetics teacher who trains voice actors. Listen to
this one Korean utterance. Judge ONLY pronunciation and prosody, never the
content or the voice's timbre.
Return JSON:
{"native_likeness": 1-5,  // 5 = indistinguishable from a native Seoul speaker,
                          // 4 = native but slightly off / synthetic,
                          // 3 = clearly a fluent non-native,
                          // 2 = strong foreign accent, effort to follow,
                          // 1 = hard to understand
 "foreign_accent": true|false,
 "likely_first_language": "Korean" | "English" | "...",
 "problems": ["<the Korean word> — <what was wrong, in English, ≤ 10 words>", ...]}"""

def ask(audio_b64, prompt):
    body = {"contents": [{"role": "user", "parts": [
                {"inlineData": {"mimeType": "audio/mpeg", "data": audio_b64}},
                {"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json",
                                 "thinkingConfig": {"thinkingLevel": "low"}}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    for _ in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=90))
            return json.loads(r["candidates"][0]["content"]["parts"][0]["text"])
        except Exception as e:
            err = e
    return {"error": str(err)}

def hangul(t): return re.sub(r"[^가-힣0-9]", "", t or "")

def cer(ref, hyp):
    a, b = hangul(ref), hangul(hyp)
    if not a: return 0.0
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[-1] / len(a)

rows = list(csv.DictReader(open(os.path.join(DIR, "manifest.tsv")), delimiter="\t"))
def judge(row):
    audio = base64.b64encode(open(os.path.join(DIR, row["file"]), "rb").read()).decode()
    out = dict(row)
    out["runs"] = []
    for _ in range(RUNS):
        t = ask(audio, TRANSCRIBE)
        a = ask(audio, ACCENT)
        if isinstance(a, list): a = a[0] if a and isinstance(a[0], dict) else {"error": "list"}
        out["runs"].append({"heard": t.get("text"), "cer": cer(row["text"], t.get("text")), "accent": a})
    return out

with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(judge, rows))
json.dump(results, open(os.path.join(DIR, "judge.json"), "w"), ensure_ascii=False, indent=1)

def summarize(key_fn, title):
    groups = defaultdict(list)
    for r in results:
        groups[key_fn(r)].extend(r["runs"])
    print(f"\n{title:<22} {'native 1-5':>10} {'accent%':>8} {'CER%':>6}  first language heard")
    for k in sorted(groups):
        runs = [x for x in groups[k] if "error" not in x["accent"]]
        if not runs: continue
        nl = statistics.mean(x["accent"].get("native_likeness", 0) for x in runs)
        fa = 100 * statistics.mean(1 if x["accent"].get("foreign_accent") else 0 for x in runs)
        c = 100 * statistics.mean(x["cer"] for x in runs)
        l1 = defaultdict(int)
        for x in runs: l1[str(x["accent"].get("likely_first_language"))] += 1
        print(f"{k:<22} {nl:>10.2f} {fa:>7.0f}% {c:>5.1f}%  " + ", ".join(f"{a}×{n}" for a, n in sorted(l1.items(), key=lambda p: -p[1])))

summarize(lambda r: r["voice"], "voice")
summarize(lambda r: f'{r["voice"]} / {r["variant"]}', "voice / variant")
summarize(lambda r: r["line"] if not r["voice"].startswith("ko-") else "~control", "line (non-native)")

print("\nmost-cited problems (non-native voices, shipping variant):")
probs = defaultdict(int)
for r in results:
    if r["voice"].startswith("ko-") or r["variant"] != "turbo": continue
    for x in r["runs"]:
        for p in x["accent"].get("problems") or []:
            probs[p.split("—")[0].strip()] += 1
for p, n in sorted(probs.items(), key=lambda p: -p[1])[:15]:
    print(f"  {n:>2}  {p}")

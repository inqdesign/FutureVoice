#!/usr/bin/env python3
# Does the call's reply ever carry something that must not be SPOKEN?
# (2026-10-21.) Claude Haiku 5.5 wrote its planning into the reply on the
# founder's Korean A2 call — "the reply must be Korean only, ≤3 sentences, one
# question at end… Per the notes, I can bring up… Let's answer: …" — and the
# call read it aloud. The probes that cleared it only counted questions; two
# of ~430 replies already carried the same thing and nobody read them. This
# one reads EVERY reply, twice: a code check (meta words, brackets, Latin
# text inside a non-Latin reply, runaway length) and a judge model asked one
# thing — is all of this meant to be said to the caller?
#
# Runs the gateway's own request: the live prompt (ConversationPromptDumpTests
# dump), the realtime style rules, CLAUDE_ADDENDUM from claude-reply.ts, the
# same message shaping. Three situations per case, because the leak came from
# a call with a notebook and coach mode: plain · notes (an "About the user"
# block with remembered lines) · notes + steer (coach mode's note on the
# learner's last line, steer-turn.ts).
#
#   scripts/reply-leak-probe.py                       # Haiku, as the gateway sends it
#   THINKING=disabled EFFORT=low scripts/reply-leak-probe.py
#   ADDENDUM_FILE=x.txt …                             # replace CLAUDE_ADDENDUM
#   LANGS=ko,ja LEVELS=a2 RUNS=3 …
#
# THINKING: omit (default — the API's adaptive) · adaptive · disabled.
# EFFORT: "" (default — the model's own) · low · medium · high.
# Key from ~/keys/anthropic.txt. Output → $OUT_DIR/reply-leak.out.json.
import json, os, re, sys, time, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ.get("DUMP_DIR", "/tmp/fv-prompt-dump")
OUT = os.environ.get("OUT_DIR", "/tmp")
MODEL = os.environ.get("MODEL", "claude-haiku-5-5")
THINKING = os.environ.get("THINKING", "omit")
EFFORT = os.environ.get("EFFORT", "")
LEVELS = os.environ.get("LEVELS", "a2,b1").split(",")
LANGS = os.environ.get("LANGS", "en,ko,ja,de,es").split(",")
RUNS = int(os.environ.get("RUNS", "2"))
KEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()

# The beginner probe's conversations, so both probes ask the same things.
src = open(os.path.join(ROOT, "scripts/beginner-probe.py")).read()
data = {}
exec(src[src.index("FIRST = {"):src.index("OPEN = {")], data)
FIRST, CASES = data["FIRST"], data["CASES"]

view = open(os.path.join(ROOT, "FutureVoice/Views/ConversationView.swift")).read()
style = re.search(r'static let realtimeStyleRules = """\n(.*?)\n        """', view, re.S).group(1)
style = re.sub(r"\\\n\s*", "", "\n".join(l.strip() for l in style.splitlines()))
gw = open(os.path.join(ROOT, "gateway/src/claude-reply.ts")).read()
ADDENDUM = (open(os.environ["ADDENDUM_FILE"]).read() if os.environ.get("ADDENDUM_FILE")
            else re.search(r"CLAUDE_ADDENDUM = `(.*?)`", gw, re.S).group(1))

# What a real notebook looks like on the founder's own account: occupation,
# family, and dated lines heard on calls — the "notes" the leaked reasoning
# was arguing with.
NOTES = """About the user (use these naturally, don't list them):
- Name: Minji
- Lives in: Munich, Germany (3 years)
- Does: founder, building a language app
- Household: wife and a 4-year-old daughter
- Interests: running, product design, coffee
- Needs the language most for: work calls, small talk with other parents
What you remember from earlier calls (newest first; a later line wins):
- today: started an Android test with 12 people
- 2 days ago: the app is called nawana, it lets you talk to a fluent future self
- last week: daughter started at a new Kita, mornings are rushed
- 3 weeks ago: training for a half marathon in spring"""
STEER = ('COACH MODE. The learner is studying: "launch", "feedback", "exhausted". If — and only if — '
         "one of them fits what you are ALREADY talking about, you may end this reply with a question "
         "whose most natural answer would use it. Do not say that word yourself, do not mention practice, "
         "words or coaching, and never steer the topic toward a word. Most replies should simply continue "
         "the conversation as they would have.")

def steered(text):
    return f"{text}\n\n[Note for you, not part of what they said:\n{STEER}]"

def messages(history, steer):
    out = []
    for i, (r, t) in enumerate(history):
        role = "assistant" if r == "m" else "user"
        if steer and i == len(history) - 1 and role == "user":
            t = steered(t)
        if out and out[-1]["role"] == role:
            out[-1]["content"] += "\n" + t
        else:
            out.append({"role": role, "content": t})
    if out[0]["role"] == "assistant":
        out.insert(0, {"role": "user", "content": "(call connected)"})
    if out[-1]["role"] == "assistant":
        out.append({"role": "user", "content": "(go on)"})
    return out

def post(body):
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", json.dumps(body).encode(), {
        "content-type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": KEY})
    err = None
    for attempt in range(5):
        try:
            return json.load(urllib.request.urlopen(req, timeout=90))
        except Exception as e:
            err = e
            time.sleep(2 * (attempt + 1))
    raise err

def reply(system, history, steer):
    body = {"model": MODEL, "max_tokens": 1024, "system": system + ADDENDUM,
            "messages": messages(history, steer)}
    if THINKING != "omit":
        body["thinking"] = {"type": THINKING}
    if EFFORT:
        body["output_config"] = {"effort": EFFORT}
    try:
        j = post(body)
    except Exception as e:
        return None, f"<error {e}>", {}
    text = "".join(b.get("text", "") for b in j.get("content", []) if b.get("type") == "text").strip()
    return j.get("stop_reason"), text, j.get("usage", {})

NAMES = {"Eunggyu", "Minji", "Munich", "München", "Kita", "Android", "nawana", "Nawana"}
META = re.compile(r"\b(the user|the learner|the reply|my reply|the prompt|system prompt|the notes|per the|"
                  r"sentences?|let me|let's answer|wait\b|actually,? (no|wait)|reasoning|instructions?|"
                  r"A1|A2|B1|B2|word count|coach mode|note for you|oops)\b", re.I)
LATIN_WORD = re.compile(r"[A-Za-z]{3,}")

def code_flags(lang, text):
    flags = []
    if META.search(text): flags.append("meta")
    if re.search(r"[\[\]{}<>]|\(\d\)", text): flags.append("bracket")
    if len(text) > 420: flags.append("long")
    if lang in ("ko", "ja"):
        latin = [w for w in LATIN_WORD.findall(text) if w not in NAMES]
        if len(latin) >= 3: flags.append("latin")
    if lang in ("de", "es"):
        en = re.findall(r"\b(the|and|should|would|which|what|this|that|with|reply|user)\b", text)
        if len(en) >= 3: flags.append("english")
    return flags

JUDGE = """A voice assistant on a phone call is about to say the line below OUT LOUD, word for word, to the person on the call. The call is in {language}.

Does the line contain ANYTHING that is not meant to be said to that person? For example: notes or plans about what to say, reasoning about rules or instructions, a draft followed by the real line, a self-correction like "let me say that properly", remarks in brackets, word counts, or talk about "the user", "the learner", "the notes" or "the prompt".

A normal reply — even one that mixes in a word of another language, or is long, or is a bit odd — is CLEAN. Only text that is not part of talking to the person is a LEAK.

Line:
<<<
{line}
>>>

Answer with one word: LEAK or CLEAN."""

LANG_NAME = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}

def judge(lang, text):
    try:
        j = post({"model": "claude-haiku-5-5", "max_tokens": 600, "output_config": {"effort": "low"},
                  "messages": [{"role": "user", "content": JUDGE.format(language=LANG_NAME[lang], line=text)}]})
        out = "".join(b.get("text", "") for b in j.get("content", []) if b.get("type") == "text").upper()
        return "LEAK" in out
    except Exception:
        return None

jobs = []
for level in LEVELS:
    for lang in LANGS:
        for first in (False, True):
            base = open(os.path.join(DUMP, f"{lang}-{level}{'-first' if first else ''}.txt")).read()
            with_notes = re.sub(r"About the user[^\n]*\n", NOTES + "\n", base, count=1)
            for situation, system, steer in (("plain", base, False), ("notes", with_notes, False),
                                             ("notes+steer", with_notes, True)):
                if first and steer:
                    continue          # coach mode never steers the first meeting
                for i, case in enumerate(FIRST[lang] if first else CASES[lang]):
                    for run in range(RUNS):
                        jobs.append((level, lang, situation, f"f{i}" if first else str(i), run,
                                     system + "\n" + style, case, steer))

def run(job):
    level, lang, situation, case_id, run_i, system, case, steer = job
    stop, text, usage = reply(system, case, steer)
    flags = code_flags(lang, text) if not text.startswith("<error") else ["error"]
    leak = judge(lang, text) if text and not text.startswith("<error") else None
    return {"level": level, "lang": lang, "situation": situation, "case": case_id, "run": run_i,
            "stop": stop, "reply": text, "flags": flags, "judge_leak": leak,
            "out_tokens": usage.get("output_tokens", 0)}

t0 = time.time()
with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "8"))) as pool:
    results = list(pool.map(run, jobs))

errors = [r for r in results if "error" in r["flags"]]
judged = [r for r in results if r["judge_leak"] is not None]
leaks = [r for r in results if r["judge_leak"] or set(r["flags"]) & {"meta", "bracket", "latin", "english"}]
print(f"model {MODEL}  thinking={THINKING}  effort={EFFORT or 'default'}  "
      f"addendum={'file' if os.environ.get('ADDENDUM_FILE') else 'CLAUDE_ADDENDUM'}  "
      f"{len(results)} replies, {len(errors)} errors, {time.time() - t0:.0f}s")
print(f"judge LEAK: {sum(1 for r in judged if r['judge_leak'])}/{len(judged)}   "
      f"code flags: " + ", ".join(f"{f} {sum(f in r['flags'] for r in results)}"
                                  for f in ("meta", "bracket", "latin", "english", "long")))
for s in ("plain", "notes", "notes+steer"):
    rs = [r for r in judged if r["situation"] == s]
    print(f"  {s:12} judge LEAK {sum(r['judge_leak'] for r in rs)}/{len(rs)}")
print(f"output tokens/reply: {sum(r['out_tokens'] for r in results) / max(1, len(results)):.0f}")
print("\n--- every reply flagged by either check (read them) ---")
for r in leaks:
    print(f"[{r['level']} {r['lang']} {r['situation']} {r['case']}] judge={r['judge_leak']} "
          f"flags={r['flags']}\n    {r['reply'][:400]!r}")
out = os.path.join(OUT, "reply-leak.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("→", out)

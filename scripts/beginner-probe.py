#!/usr/bin/env python3
# How the fluent self ASKS at a learner's level (2026-10-03). Runs the app's
# LIVE conversation prompt — dumped by ConversationPromptDumpTests, so it
# cannot drift from the Swift — through Gemini with the GATEWAY's own reply
# settings (thinking "minimal", the realtime style rules appended), over
# short calls where a beginner gives short answers, and counts in code:
#
#   multi   turns asking two or more questions
#   open    turns whose question is open-ended ("tell me about", "how was",
#           "why", "what do you think") — hard to answer with a few words
#   noq     turns with no question at all (the ball isn't handed back)
#   q/turn  questions per turn
#
#   scripts/beginner-probe.py                 # dumps prompts, runs a2 + b1
#   LEVELS=a1,a2 RUNS=3 scripts/beginner-probe.py
#   MODEL=gemini-3.1-flash-lite scripts/beginner-probe.py   # the hedge model
#   NO_DUMP=1 …                               # reuse the last dump
#
# Reads GEMINI_API_KEY from gateway/.dev.vars. Full output → $OUT_DIR
# (default the scratch dir below) as beginner-probe.out.json.
import json, os, re, subprocess, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ.get("DUMP_DIR", "/tmp/fv-prompt-dump")
OUT = os.environ.get("OUT_DIR", "/tmp")
MODEL = os.environ.get("MODEL", "gemini-3.6-flash")
LEVELS = os.environ.get("LEVELS", "a2,b1").split(",")
RUNS = int(os.environ.get("RUNS", "2"))
LANGS = os.environ.get("LANGS", "en,ko,ja,de").split(",")

if not os.environ.get("NO_DUMP"):
    sim = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"], capture_output=True, text=True).stdout
    udid = re.search(r"\(([0-9A-F-]{36})\) \(Booted\)", sim)
    dest = f"id={udid.group(1)}" if udid else "platform=iOS Simulator,name=iPhone 17"
    r = subprocess.run(
        ["xcodebuild", "test", "-project", "FutureVoice.xcodeproj", "-scheme", "FutureVoice",
         "-destination", dest, "-derivedDataPath", "build",
         "-only-testing:FutureVoiceTests/ConversationPromptDumpTests"],
        cwd=ROOT, capture_output=True, text=True,
        env={**os.environ, "TEST_RUNNER_PROMPT_DUMP_DIR": DUMP})
    if "TEST SUCCEEDED" not in r.stdout and "Test Succeeded" not in r.stdout:
        print(r.stdout[-3000:]); sys.exit("prompt dump failed")

# The realtime path appends this to the system prompt (ConversationView).
view = open(os.path.join(ROOT, "FutureVoice/Views/ConversationView.swift")).read()
style = re.search(r'static let realtimeStyleRules = """\n(.*?)\n        """', view, re.S).group(1)
style = re.sub(r"\\\n\s*", "", "\n".join(l.strip() for l in style.splitlines()))

# The FIRST call (the -first prompt): the bundled intro opener, then a
# beginner's short first answer. The user's own example: introducing
# yourself is "what's your name / where do you live / what do you do", never
# "tell me about yourself".
FIRST = {
 "en": [[("m", "Hi. I'm the future you — the one who speaks English fluently. So — what are you up to these days?"), ("u", "Hello. Um... I am Minji.")],
        [("m", "Hi. I'm the future you — the one who speaks English fluently. So — what are you up to these days?"), ("u", "Nice to meet you.")]],
 "ko": [[("m", "안녕. 나는 유창하게 말하는 미래의 너야. 그래서 말인데, 요즘 어떻게 지내?"), ("u", "안녕. 음... 나는 민지.")],
        [("m", "안녕. 나는 유창하게 말하는 미래의 너야. 그래서 말인데, 요즘 어떻게 지내?"), ("u", "반가워.")]],
 "ja": [[("m", "やあ、未来のきみだよ。日本語、もうすらすら話せるようになったんだ。で、最近どうしてる？"), ("u", "こんにちは。えっと…ミンジです。")],
        [("m", "やあ、未来のきみだよ。日本語、もうすらすら話せるようになったんだ。で、最近どうしてる？"), ("u", "はじめまして。")]],
 "de": [[("m", "Hallo. Ich bin das zukünftige Du — das, das fließend Deutsch spricht. Also — was machst du gerade so?"), ("u", "Hallo. Äh... ich bin Minji.")],
        [("m", "Hallo. Ich bin das zukünftige Du — das, das fließend Deutsch spricht. Also — was machst du gerade so?"), ("u", "Freut mich.")]],
}

# Short-answer beginner calls. "m" = fluent self, "u" = learner.
CASES = {
 "en": [
  [("m", "Hey! It's good to talk. What are you up to these days?"), ("u", "Um... work. I am busy.")],
  [("m", "Hi! How's your day going?"), ("u", "Good. I am tired.")],
  [("m", "So, what did you do today?"), ("u", "I go to work. Then home.")],
  [("m", "Hey, what's new with you?"), ("u", "I like coffee.")],
  [("m", "How was your weekend?"), ("u", "음... 잘 모르겠어.")],
 ],
 "ko": [
  [("m", "안녕! 요즘 뭐 하고 지내?"), ("u", "음... 일. 바빠.")],
  [("m", "오늘 하루 어땠어?"), ("u", "좋아. 피곤해.")],
  [("m", "오늘 뭐 했어?"), ("u", "회사 가. 그리고 집.")],
  [("m", "요즘 새로운 일 있어?"), ("u", "커피 좋아.")],
  [("m", "주말 어땠어?"), ("u", "Um... I don't know.")],
 ],
 "ja": [
  [("m", "やあ！最近どうしてる？"), ("u", "えっと…仕事。忙しい。")],
  [("m", "今日はどうだった？"), ("u", "いい。疲れた。")],
  [("m", "今日は何したの？"), ("u", "会社に行く。それから家。")],
  [("m", "最近何か新しいことあった？"), ("u", "コーヒー好き。")],
  [("m", "週末はどうだった？"), ("u", "음... 잘 모르겠어.")],
 ],
 "de": [
  [("m", "Hey! Schön, dich zu hören. Was machst du so in letzter Zeit?"), ("u", "Äh... Arbeit. Viel.")],
  [("m", "Hi! Wie läuft dein Tag?"), ("u", "Gut. Ich bin müde.")],
  [("m", "Was hast du heute gemacht?"), ("u", "Ich gehe Arbeit. Dann Hause.")],
  [("m", "Was gibt's Neues bei dir?"), ("u", "Ich mag Kaffee.")],
  [("m", "Wie war dein Wochenende?"), ("u", "음... 잘 모르겠어.")],
 ],
}

OPEN = {
 "en": r"tell me (about|more)|how was|how's it|how is it|what do you think|\bwhy\b|how come|what('s| is) it like|what have you been|anything (new|else|fun)|what's new|how do you feel|what kind of",
 "ko": r"얘기해|이야기해|어땠|어떻게 생각|왜|어떤 느낌|뭐 하고 지냈|무슨 일 있|어떤 거|어떤 게",
 "ja": r"教えて|どうだった|どう思う|なんで|どうして|どんな感じ|何かあった|どんな",
 "de": r"erzähl|wie war|warum|was denkst|wie findest|wie fühlst|was gibt's neues|was für",
}

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={key}"

def reply(system, history):
    body = json.dumps({
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "model" if r == "m" else "user", "parts": [{"text": t}]} for r, t in history],
        "generationConfig": {"maxOutputTokens": 1024, "thinkingConfig": {"thinkingLevel": "minimal"}},
    }).encode()
    for _ in range(3):
        try:
            req = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
            data = json.load(urllib.request.urlopen(req, timeout=60))
            return "".join(p.get("text", "") for p in data["candidates"][0]["content"]["parts"]).strip()
        except Exception as e:
            err = e
    return f"<error {err}>"

def measure(lang, text):
    qs = len(re.findall(r"[?？]", text))
    sentences = [s for s in re.split(r"(?<=[.!?。！？])\s*", text) if s.strip()]
    questions = [s for s in sentences if s.rstrip().endswith(("?", "？"))]
    opened = any(re.search(OPEN[lang], q, re.I) for q in questions)
    last = questions[-1] if questions else ""
    size = len(last.split()) if lang in ("en", "de") else len(re.sub(r"\s", "", last))
    return {"q": qs, "multi": qs >= 2, "open": opened, "noq": qs == 0, "qsize": size if questions else None}

jobs = []
for level in LEVELS:
    for lang in LANGS:
        for first in (False, True):
            system = open(os.path.join(DUMP, f"{lang}-{level}{'-first' if first else ''}.txt")).read() + "\n" + style
            for i, case in enumerate(FIRST[lang] if first else CASES[lang]):
                for run in range(RUNS):
                    jobs.append((level, lang, (f"f{i}" if first else i), run, system, case))

results = []
with cf.ThreadPoolExecutor(8) as pool:
    futs = {pool.submit(reply, j[4], j[5]): j for j in jobs}
    for f in cf.as_completed(futs):
        level, lang, i, run, _, case = futs[f]
        text = f.result()
        results.append({"level": level, "lang": lang, "case": i, "run": run,
                        "learner": case[-1][1], "reply": text, **measure(lang, text)})

print(f"model {MODEL}, {RUNS} runs × {len(CASES['en'])} cases")
print(f"{'level':5} {'lang':4} {'multi':>7} {'open':>7} {'noq':>7} {'q/turn':>7} {'q size':>7}   (size: words en/de, chars ko/ja)")
for level in LEVELS:
    for lang in LANGS:
        rs = [r for r in results if r["level"] == level and r["lang"] == lang]
        n = len(rs)
        print(f"{level:5} {lang:4} {sum(r['multi'] for r in rs):>3}/{n:<3} {sum(r['open'] for r in rs):>3}/{n:<3} "
              f"{sum(r['noq'] for r in rs):>3}/{n:<3} {sum(r['q'] for r in rs)/max(n,1):>7.2f} "
              f"{(lambda xs: sum(xs)/len(xs) if xs else 0)([r['qsize'] for r in rs if r['qsize']]):>7.1f}")
if "--show" in sys.argv:
    for r in sorted(results, key=lambda r: (r["level"], r["lang"], str(r["case"]), r["run"])):
        flag = "MULTI " if r["multi"] else ("OPEN  " if r["open"] else ("NOQ   " if r["noq"] else "ok    "))
        print(f"[{r['level']} {r['lang']} {r['case']}] {flag}{r['reply']}")
out = os.path.join(OUT, "beginner-probe.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("→", out)

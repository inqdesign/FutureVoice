#!/usr/bin/env python3
# Tutor mode (2026-10-13): is every turn a lesson step — feedback on the
# line, then a practice question — and is no transcriber artifact taught as
# a mistake? Runs the app's LIVE tutor prompt (dumped by
# ConversationPromptDumpTests, so it can't drift from the Swift) through
# Gemini with the gateway's reply settings, over one-turn exchanges:
#
#   caught   mistake lines whose reply re-says the line correctly
#   teaches  replies that teach something (a fix, a better wording, a new
#            phrase) — the point of the mode, on every kind of line
#   asr      transcriber-artifact lines (expanded "I am", a dropped "I",
#            띄어쓰기, spoken word order) whose reply "fixes" them anyway.
#            Spoken, that is far worse than on a card. Read those by hand —
#            a fix that changes something audible is fine.
#   long     replies over 3 sentences
#   noq      replies that don't carry the conversation on with a question
#
# The verdict (corrected or not) is flash-lite's, reading the reply; the
# full transcript goes to $OUT_DIR/tutor-probe.out.json for a person.
#
#   scripts/tutor-probe.py                       # dumps prompts, a2 + b1, 2 runs
#   LANGS=ko RUNS=3 NO_DUMP=1 scripts/tutor-probe.py
import json, os, re, subprocess, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ.get("DUMP_DIR", "/tmp/fv-prompt-dump")
OUT = os.environ.get("OUT_DIR", "/tmp")
MODEL = os.environ.get("MODEL", "gemini-3.6-flash")
JUDGE = "gemini-3.1-flash-lite"
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

view = open(os.path.join(ROOT, "FutureVoice/Views/ConversationView.swift")).read()
style = re.search(r'static let realtimeStyleRules = """\n(.*?)\n        """', view, re.S).group(1)
style = re.sub(r"\\\n\s*", "", "\n".join(l.strip() for l in style.splitlines()))

# (question, answer, kind): True = a mistake, False = clean, "asr" = clean
# but carrying something the transcriber chose
CASES = {
 "en": [
  ("What's your name?", "My name... is Eunggyu my name.", True),
  ("What did you do yesterday?", "Yesterday I go to the cinema with my friend.", True),
  ("Where do you live?", "I am live in Seoul.", True),
  ("Does your brother like coffee?", "No, he don't like coffee.", True),
  ("How long have you worked there?", "I am working here since three years.", True),
  ("What's your name?", "I'm Eunggyu.", False),
  ("What do you do?", "I am a designer.", "asr"),            # expanded contraction
  ("What did you do this morning?", "went to the park, then work.", "asr"),  # dropped I
  ("Where do you live?", "i live in seoul near the river", "asr"),  # caps/punct
  ("Do you have kids?", "Yeah, 2 kids.", "asr"),               # digits, fragment
 ],
 "ko": [
  ("이름이 뭐야?", "나는 입니다. 이응규.", True),
  ("어제 뭐 했어?", "어제 친구를 만나요.", True),
  ("어디 살아?", "나는 서울에 살아 있어.", True),
  ("커피 좋아해?", "아니, 나는 커피를 좋아 안 해.", True),
  ("이름이 뭐야?", "난 응규라고 해.", False),
  ("아까 뭐 먹었어?", "먹었어 아까 라면.", "asr"),             # spoken word order
  ("내일 올 수 있어?", "응 할수 있어.", "asr"),                 # spacing
  ("부모님은 뭐 하셔?", "아빠는 지금 주무셔.", "asr"),           # subject honorific + 반말
  ("어디 살아?", "서울.", False),
 ],
 "ja": [
  ("名前は？", "私は名前はミンジです名前。", True),
  ("昨日何した？", "昨日、映画を見ます。", True),
  ("どこに住んでる？", "東京に住んでるでした。", True),
  ("名前は？", "ミンジ。よろしく。", False),
  ("昨日何した？", "映画見た、友達と。", "asr"),
  ("どこに住んでる？", "東京に住んでる。", False),
  ("分かった？", "うん、わかった。", "asr"),
 ],
 "de": [
  ("Wie heißt du?", "Ich heiße ist Minji.", True),
  ("Was hast du gestern gemacht?", "Ich habe gestern ins Kino gegangen.", True),
  ("Was machst du gern?", "Gestern ich bin ins Kino gegangen.", True),
  ("Magst du Kaffee?", "Nein, ich mag nicht Kaffee.", True),
  ("Wie heißt du?", "Ich heiße Minji.", False),
  ("Was hast du gestern gemacht?", "Hab gearbeitet, den ganzen Tag.", "asr"),
  ("Wo wohnst du?", "In Seoul, seit drei Jahren.", False),
  ("Wie alt bist du?", "Ich bin 30.", "asr"),
 ],
}

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')

def call(model, body):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
            data = json.load(urllib.request.urlopen(req, timeout=60))
            return "".join(p.get("text", "") for p in data["candidates"][0]["content"]["parts"] if not p.get("thought"))
        except Exception as e:
            if attempt == 3: return f"ERROR {e}"

def reply(system, q, a):
    return call(MODEL, {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "model", "parts": [{"text": q}]}, {"role": "user", "parts": [{"text": a}]}],
        "generationConfig": {"maxOutputTokens": 1024, "thinkingConfig": {"thinkingLevel": "minimal"}},
    })

def judged(said, rep):
    prompt = (f'A language learner said: "{said}"\nTheir tutor replied: "{rep}"\n'
              '"corrected": did the reply say their line (or part of it) back in a different, "right" '
              'form? Merely reacting or repeating a word in agreement is not. '
              '"teaches": did the reply teach anything — a correction, a more natural wording, or a new '
              'word/phrase to use? '
              'Answer JSON {"corrected": true|false, "teaches": true|false}.')
    out = call(JUDGE, {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
                       "generationConfig": {"responseMimeType": "application/json"}})
    try:
        j = json.loads(out); return bool(j["corrected"]), bool(j["teaches"])
    except Exception: return None, None

def sentences(text):
    return len([s for s in re.split(r"(?<=[.!?。！？])\s*", text.strip()) if s.strip()])

jobs = []
for lang in LANGS:
    for level in LEVELS:
        system = open(os.path.join(DUMP, f"{lang}-{level}-tutor.txt")).read() + "\n\n" + style
        for (q, a, bad) in CASES[lang]:
            for run in range(RUNS):
                jobs.append((lang, level, q, a, bad, system))

def run(job):
    lang, level, q, a, bad, system = job
    rep = reply(system, q, a)
    corrected, teaches = judged(a, rep)
    return {"lang": lang, "level": level, "q": q, "said": a, "kind": bad, "mistake": bad is True,
            "reply": rep, "corrected": corrected, "teaches": teaches, "sentences": sentences(rep),
            "question": bool(re.search(r"[?？]", rep))}

with cf.ThreadPoolExecutor(8) as ex:
    rows = list(ex.map(run, jobs))

json.dump(rows, open(os.path.join(OUT, "tutor-probe.out.json"), "w"), ensure_ascii=False, indent=1)
for lang in LANGS:
    for level in LEVELS:
        rs = [r for r in rows if r["lang"] == lang and r["level"] == level]
        bad = [r for r in rs if r["kind"] is True]; asr = [r for r in rs if r["kind"] == "asr"]
        print(f"{lang} {level}: caught {sum(r['corrected'] is True for r in bad)}/{len(bad)} · "
              f"teaches {sum(r['teaches'] is True for r in rs)}/{len(rs)} · "
              f"asr {sum(r['corrected'] is True for r in asr)}/{len(asr)} · "
              f"long {sum(r['sentences'] > 3 for r in rs)}/{len(rs)} · "
              f"noq {sum(not r['question'] for r in rs)}/{len(rs)}")

#!/usr/bin/env python3
"""Tutor mode's lesson, against the live models (2026-10-24).

Three parts, every reply PRINTED so it can be read (a count alone missed
leaks before — see claude-reply-rollout):
  1. planner — TutorPlanner's prompt (lifted from the Swift source) on a few
     topic requests, two of which name no topic and must come back false.
  2. judge   — TutorJudge's prompt on lines that do / don't do a challenge.
  3. tutor   — the live reply model (Claude Haiku, adaptive thinking, the
     gateway's CLAUDE_ADDENDUM) on the dumped tutor prompts
     (ConversationPromptDumpTests → DUMP_DIR): no topic yet, the lesson-ready
     note, a mistake, a right line (must ask once more, NOT move on), and a
     right line after the app's tick (must move on).

  DUMP_DIR=<dir> scripts/tutor-lesson-probe.py [en,ko]
Keys: gateway/.dev.vars GEMINI_API_KEY, ~/keys/anthropic.txt.
"""
import json, os, re, sys, urllib.request, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ["DUMP_DIR"]
LANGS = (sys.argv[1] if len(sys.argv) > 1 else "en,ko").split(",")
LEVEL = os.environ.get("LEVEL", "a2")
GEMINI = re.search(r"GEMINI_API_KEY=(.*)", open(f"{ROOT}/gateway/.dev.vars").read()).group(1).strip()
ANTHROPIC = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
gw = open(f"{ROOT}/gateway/src/claude-reply.ts").read()
ADDENDUM = re.search(r"CLAUDE_ADDENDUM = `(.*?)`", gw, re.S).group(1)
cv = open(f"{ROOT}/FutureVoice/Views/ConversationView.swift").read()
STYLE = re.search(r'realtimeStyleRules = """\n(.*?)"""', cv, re.S).group(1)
STYLE = re.sub(r"\\\n\s*", "", "\n" + re.sub(r"^ {8}", "", STYLE, flags=re.M))
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}

def swift_string(src, after):
    body = re.search(re.escape(after) + r'.*?"""\n(.*?)"""', src, re.S).group(1)
    body = re.sub(r"^ {8}", "", body, flags=re.M)
    return re.sub(r"\\\n\s*", "", body)

tl = open(f"{ROOT}/FutureVoice/Services/TutorLesson.swift").read()
PLAN = swift_string(tl, "static func plan(")
JUDGE = swift_string(tl[tl.index("enum TutorJudge"):], "static func read(")

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    for i in range(4):
        try:
            return json.load(urllib.request.urlopen(req, timeout=90))
        except Exception as e:
            err = e; time.sleep(2 * (i + 1))
    raise err

def gemini(model, system, user, thinking="low"):
    j = post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GEMINI}", {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 2000,
                             "thinkingConfig": {"thinkingLevel": thinking}}}, {})
    return "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"])

def haiku(system, history):
    msgs = []
    for role, text in history:
        r = "assistant" if role == "m" else "user"
        if msgs and msgs[-1]["role"] == r: msgs[-1]["content"] += "\n" + text
        else: msgs.append({"role": r, "content": text})
    if msgs[0]["role"] == "assistant": msgs.insert(0, {"role": "user", "content": "(call connected)"})
    j = post("https://api.anthropic.com/v1/messages", {
        "model": "claude-haiku-5-5", "max_tokens": 2048, "system": system + STYLE + ADDENDUM,
        "thinking": {"type": "adaptive"}, "output_config": {"effort": "medium"},
        "messages": msgs}, {"anthropic-version": "2023-06-01", "x-api-key": ANTHROPIC})
    return "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text").strip()

# ---- 1. planner — (tutor's line or None for an on-screen pick, learner's words, want a lesson?)
ASK_EN = "Oh, nice, let's do some English practice! What do you want to work on today?"
REQ = {
    "en": [(ASK_EN, "I'd like to practice introducing myself.", True),
           # the device case, 2026-10-24: "I'd like" misheard
           (ASK_EN, "I don't like to practice on introducing myself.", False),
           ("Introducing yourself — want to practice that?", "Yes.", True),
           ("Would you like to practice talking about travel, or ordering food at a café?", "The second one.", True),
           (None, "Meeting someone new", True),
           (ASK_EN, "I don't know.", False),
           (ASK_EN, "um hello", False)],
    "ko": [("좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어?", "처음 만난 사람한테 자기소개하는 거 연습하고 싶어.", True),
           ("좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어?", "몰라 아무거나.", False),
           (None, "카페에서 주문하기", True)],
}
for lang in LANGS:
    native = "Korean" if lang != "ko" else "English"
    sysp = (PLAN.replace("\\(target)", NAMES[lang]).replace("\\(native)", native)
            .replace("\\(level.rawValue.uppercased())", LEVEL.upper())
            .replace('\\(about.isEmpty ? "" : "\\nWhat is known about them: \\(about). Context only.")', ""))
    for asked, said, want in REQ.get(lang, []):
        msg = f'The tutor asked: "{asked}"\nThey answered: "{said}"' if asked else f'They picked on screen: "{said}"'
        out = gemini("gemini-3.6-flash", sysp, msg)
        try:
            j = json.loads(out); got = j.get("topic"); title = j.get("title", "")
        except Exception:
            got, title = "?", out[:80]
        flag = "OK " if got == want else "BAD"
        print(f"### PLAN {flag} {lang} want={want} got={got} · {said} → {title} | {[c.get('goal') for c in j.get('challenges', [])] if isinstance(got, bool) and got else ''}")

# ---- 2. judge
CH = ("Say your name and where you're from", "I'm Minji, and I'm from Busan.")
LINES = [("My name is Tom and I'm from Leeds.", True), ("I'm Tom.", False),
         ("I like coffee.", False), ("Hi, I am Tom, I come from Leeds in England.", True)]
ASKED = [("Tell me your name and where you're from.", False),
         ("Nice and clear. Say it once more, just like that.", False),
         ("You got it! Next: what do you do? Say: I work as a nurse — about you.", True)]
for line, want in ([] if os.environ.get("PLAN_ONLY") else LINES):
    sysp = JUDGE.replace("\\(target)", "English")
    for asked, moved in (ASKED if want else ASKED[:1]):
        out = gemini("gemini-3.1-flash-lite", sysp,
                     f"Challenge: {CH[0]}\nExample of a line that does it: {CH[1]}\n"
                     f"The tutor had just said: {asked}\nThe learner said: {line}",
                     thinking="minimal")
        print(f"### JUDGE want done={want} moved={moved} · {asked[:30]} · {line} → {out.strip()}")

# ---- 3. tutor replies
NOTE = "[Note from the app — the learner did not say this: %s]"
CASES = {
    "en": {
        "notopic": ("tutor", [("m", "Okay, lesson time. What do you want to be able to say today? Tell me, or pick a topic from the button."),
                              ("u", "I want to introduce myself when I meet new people.")]),
        "ready": ("lesson", [("m", "Great, introducing yourself it is. Let me set it up."),
                             ("u", NOTE % "Today's lesson is ready (see TUTOR MODE). In a few words say what it is and that you'll go one step at a time, then start the current challenge: say what it is, give its example line, and ask them to say it about themselves.")]),
        "mistake": ("lesson", [("m", "Now, what do you do? Say: I work as a nurse at a hospital — but about you."),
                               ("u", "I am work in company as engineer.")]),
        "right": ("lesson", [("m", "Now, what do you do? Say: I work as a nurse at a hospital — but about you."),
                             ("u", "I work as an engineer at a car company.")]),
        "ticked": ("ticked", [("m", "Now, what do you do? Say: I work as a nurse at a hospital — but about you."),
                              ("u", "I work as an engineer at a car company."),
                              ("m", "Nice, that sounded right. Say it once more, just like that."),
                              ("u", "I work as an engineer at a car company.")]),
        # No app tick: the tutor itself must move on (2026-10-25).
        "again": ("lesson", [("m", "Now, what do you do? Say: I work as a nurse at a hospital — but about you."),
                             ("u", "I work as an engineer at a car company."),
                             ("m", "Nice and clear. Say it once more, just like that."),
                             ("u", "I work as an engineer at a car company.")]),
    },
    "ko": {
        "notopic": ("tutor", [("m", "좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어? 말해 줘도 되고, 버튼에서 주제를 골라도 돼."),
                              ("u", "처음 만난 사람한테 자기소개하는 거.")]),
        "ready": ("lesson", [("m", "좋아, 자기소개로 하자. 잠깐 준비할게."),
                             ("u", NOTE % "Today's lesson is ready (see TUTOR MODE). In a few words say what it is and that you'll go one step at a time, then start the current challenge: say what it is, give its example line, and ask them to say it about themselves.")]),
        "mistake": ("lesson", [("m", "이제 무슨 일 하는지 말해 볼까? 예를 들면, 저는 병원에서 간호사로 일해요. 네 얘기로 해 봐."),
                               ("u", "저는 회사를 엔지니어 일해요.")]),
        "right": ("lesson", [("m", "이제 무슨 일 하는지 말해 볼까? 예를 들면, 저는 병원에서 간호사로 일해요. 네 얘기로 해 봐."),
                             ("u", "저는 자동차 회사에서 엔지니어로 일해요.")]),
        "ticked": ("ticked", [("m", "이제 무슨 일 하는지 말해 볼까? 예를 들면, 저는 병원에서 간호사로 일해요. 네 얘기로 해 봐."),
                              ("u", "저는 자동차 회사에서 엔지니어로 일해요."),
                              ("m", "좋아, 맞게 했어. 한 번만 더 똑같이 말해 봐."),
                              ("u", "저는 자동차 회사에서 엔지니어로 일해요.")]),
        "again": ("lesson", [("m", "이제 무슨 일 하는지 말해 볼까? 예를 들면, 저는 병원에서 간호사로 일해요. 네 얘기로 해 봐."),
                             ("u", "저는 자동차 회사에서 엔지니어로 일해요."),
                             ("m", "좋아, 깔끔해. 한 번만 더 똑같이 말해 봐."),
                             ("u", "저는 자동차 회사에서 엔지니어로 일해요.")]),
    },
}
RUNS = int(os.environ.get("RUNS", "2"))
for lang in LANGS:
    for name, (kind, hist) in ([] if os.environ.get("PLAN_ONLY") else CASES.get(lang, {}).items()):
        suffix = "" if kind == "tutor" else f"-{kind}"
        system = open(f"{DUMP}/{lang}-{LEVEL}-tutor{suffix}.txt").read()
        for i in range(RUNS):
            print(f"\n### TUTOR {lang} · {name} · run {i + 1}\n{haiku(system, hist)}")

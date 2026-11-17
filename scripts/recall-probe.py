#!/usr/bin/env python3
# Does TalkRecall's judge pick the earlier talk a learner's line is about, and
# say none when the line is about today? (2026-11-17.) Lifts the judge's
# system prompt from the Swift source and runs it on flash-lite as the app does.
#   scripts/recall-probe.py        # RUNS=3 by default
# Key: GEMINI_API_KEY in gateway/.dev.vars.
import json, os, re, urllib.request, concurrent.futures as cf
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS = int(os.environ.get("RUNS", "3"))
MODEL = os.environ.get("MODEL", "gemini-3.1-flash-lite")
KEY = re.search(r'^GEMINI_API_KEY\s*=\s*"?([^"\n]+)', open(os.path.join(ROOT, "gateway/.dev.vars")).read(), re.M).group(1)
src = open(os.path.join(ROOT, "FutureVoice/Services/TalkRecall.swift")).read()
raw = re.search(r'static let system = """\n(.*?)\n        """', src, re.S).group(1)
SYSTEM = re.sub(r"\\\n\s*", "", "\n".join(l.strip() for l in raw.splitlines()))

# (when, title, what the learner said in it)
EN = [
  ("yesterday", "Boss complained about the deck", "I worked the whole weekend and my boss still complained about the deck. / He said the numbers slide is confusing."),
  ("2 days ago", "Lunch at the new laksa place", "I had lunch with my partner at a new restaurant, it was pricey but worth it. / I almost lost my AirPod on the MRT."),
  ("4 days ago", "Interview at the bank on Friday", "I have an interview at the bank on Friday and I am nervous. / The salary question, I never know what number to say."),
  ("6 days ago", "Training for the 10k", "I run three times a week now. / My knee hurts a little after long runs."),
  ("9 days ago", "Exam leak in the news", "People have lost trust in this exam. / It is a catch-22 situation."),
  ("12 days ago", "“Good. Hey what does”", "Good. Hey what does catch-22 mean? / I want to practise using it."),
]
KO = [
  ("어제", "주말 부산 여행", "주말에 부산에 갔다 왔어. / 자갈치 시장에서 회 먹었어."),
  ("3일 전", "이사 준비", "다음 달에 이사해야 해서 집을 보고 있어. / 보증금이 너무 비싸."),
  ("일주일 전", "엄마 생신 선물", "엄마 생신이 다음 주인데 뭘 살지 모르겠어."),
]
DE = [
  ("gestern", "Ärger mit dem Vermieter", "Mein Vermieter will die Miete um zehn Prozent erhöhen. / Ich habe ihm einen Brief geschrieben."),
  ("vor 5 Tagen", "Kinofilm am Samstag", "Ich war am Samstag im Kino. / Der Film war zu lang."),
]
# (talks, last reply, newest line, expected number or None)
CASES = [
  (EN, "Hey Olivia! How's your Sunday going?", "Good. Remember the interview I told you about? I got the job!", 3),
  (EN, "Hey Olivia! How's your Sunday going?", "My boss actually liked the new version of the deck.", 1),
  (EN, "What did you do today?", "I went back to that laksa place with my sister.", 2),
  (EN, "How are you feeling?", "My knee is worse today, I had to stop after two kilometres.", 4),
  (EN, "What's on your mind?", "What was that idiom we practised, the one about a situation you cannot win?", None),  # two fit (5, 6): either
  (EN, "So what happened?", "They offered me less than I asked, the salary thing again.", 3),
  (EN, "Hey! What's up?", "Do you remember what I said about the numbers slide?", 1),
  (EN, "Nice. And then?", "I told you last time I was on my way home, do you remember?", None),
  (EN, "Hey Olivia! How's your Sunday going?", "Good, I am cooking pasta for dinner.", None),
  (EN, "What do you think about it?", "I think remote work is better for most people.", None),
  (EN, "How was work?", "Work was fine, nothing special. I had a lot of meetings.", None),
  (EN, "Any plans?", "I want to watch a movie tonight, maybe something funny.", None),
  (EN, "Did you eat?", "Yes, I had a sandwich at my desk again.", None),
  (EN, "What's new?", "I started reading a book about sleep.", None),
  (KO, "오늘 뭐 했어?", "지난번에 말한 집 있잖아, 계약했어.", 2),
  (KO, "잘 지냈어?", "응. 엄마 선물은 결국 스카프로 샀어.", 3),
  (KO, "요즘 어때?", "부산에서 먹은 회가 자꾸 생각나.", 1),
  (KO, "오늘 뭐 했어?", "오늘은 그냥 집에서 넷플릭스 봤어.", None),
  (KO, "점심은?", "회사 근처에서 김치찌개 먹었어.", None),
  (DE, "Wie geht's dir?", "Der Vermieter hat endlich geantwortet, er bleibt bei der Erhöhung.", 1),
  (DE, "Was machst du heute?", "Ich koche heute Abend für Freunde.", None),
  (DE, "Und sonst?", "Weißt du noch, der Film, von dem ich dir erzählt habe? Ich habe ihn noch mal gesehen.", 2),
]
EITHER = {4: {5, 6}}

def content(talks, last, newest):
    lst = "\n".join(f'{i+1}. {w} — "{t}"\n   the learner said: "{g}"' for i, (w, t, g) in enumerate(talks))
    return f'Earlier talks, newest first:\n{lst}\n\nLast line said to the learner: "{last}"\nNewest line from the learner: "{newest}"'

def ask(job):
    i, run = job
    talks, last, newest, _ = CASES[i]
    body = {"systemInstruction": {"parts": [{"text": SYSTEM}]},
            "contents": [{"role": "user", "parts": [{"text": content(talks, last, newest)}]}],
            "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 100,
                                 "thinkingConfig": {"thinkingLevel": "minimal"}}}
    req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}",
                                 json.dumps(body).encode(), {"Content-Type": "application/json"})
    for _ in range(4):
        try:
            d = json.load(urllib.request.urlopen(req, timeout=60))
            return job, json.loads(d["candidates"][0]["content"]["parts"][0]["text"]).get("talk")
        except Exception as e: err = e
    return job, f"error {err}"

jobs = [(i, r) for i in range(len(CASES)) for r in range(RUNS)]
with cf.ThreadPoolExecutor(8) as pool: res = dict(pool.map(ask, jobs))
right = wrong_yes = missed = wrong_talk = 0
for i, (_, _, newest, want) in enumerate(CASES):
    got = [res[(i, r)] for r in range(RUNS)]
    ok = lambda g: g in EITHER[i] if i in EITHER else g == want
    for g in got:
        if ok(g): right += 1
        elif want is None and i not in EITHER: wrong_yes += 1
        elif g is None: missed += 1
        else: wrong_talk += 1
    print(f"{'ok ' if all(ok(g) for g in got) else 'BAD'} want {EITHER.get(i, want)} got {got}  {newest[:80]}")
n = len(jobs)
print(f"\nright {right}/{n} · looked up a talk nobody brought up {wrong_yes} · missed {missed} · wrong talk {wrong_talk}")

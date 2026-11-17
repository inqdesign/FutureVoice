#!/usr/bin/env python3
# Does MisheardJudge pick the right line, and say none when it should?
# (2026-11-17.) Lifts the judge's system prompt from the Swift source and runs
# it on flash-lite as the app does. A wrong YES takes a real line out of a
# learner's score, so the "none" cases matter most.
#   scripts/misheard-probe.py        # RUNS=3 by default
# Key: GEMINI_API_KEY in gateway/.dev.vars.
import json, os, re, sys, urllib.request, concurrent.futures as cf
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS = int(os.environ.get("RUNS", "3"))
MODEL = os.environ.get("MODEL", "gemini-3.1-flash-lite")
KEY = re.search(r'^GEMINI_API_KEY\s*=\s*"?([^"\n]+)', open(os.path.join(ROOT, "gateway/.dev.vars")).read(), re.M).group(1)
src = open(os.path.join(ROOT, "FutureVoice/Services/MisheardJudge.swift")).read()
raw = re.search(r'static let system = """\n(.*?)\n        """', src, re.S).group(1)
SYSTEM = re.sub(r"\\\n\s*", "", "\n".join(l.strip() for l in raw.splitlines()))

LUNCH = [("I had lunch with my partner at a new restaurant, it was pricey but worth it.", "Nice, a new place. What did you two order?"),
         ("We had the laksa. And I almost lost my AirPod on the MRT.", "Oh no. Did you get it back?"),
         ("She is here for six month.", "Oh, your friend is in Singapore for six months? Is she working here?")]
WORK = [("I work as a product manager.", "Oh nice. What kind of product?"),
        ("I hate my boss, he is so stupid.", "Oof. What did he do?"),
        ("We make an app for doctors.", "That sounds useful. Do doctors like it?")]
KO = [("주말에 부산에 갔다 왔어.", "오, 부산! 뭐 했어?"), ("내일 회사 그만둘 거야.", "뭐? 진짜 그만둬?")]
JA = [("週末は京都に行きました。", "いいね、京都。何をしたの？"), ("犬を三匹飼っています。", "三匹も？にぎやかだね。")]
DE = [("Ich war gestern im Kino.", "Schön, was hast du gesehen?"), ("Meine Schwester ist schwanger.", "Oh, Glückwunsch! Wann kommt das Baby?")]
# (candidates, newest line, expected line number or None)
CASES = [
  (LUNCH, "Excuse me, the six month is that you misheard because I was walking outside and then you misheard from the other people's voice.", 3),
  (LUNCH, "That was not me, that was someone on the street.", 3),
  (LUNCH, "No no, I didn't say anything about a friend. That was somebody else talking.", 3),
  (LUNCH, "I never said laksa, I said pasta. You misheard.", 2),
  (LUNCH, "그거 내가 한 말 아니야, 옆에 지나가던 사람 목소리야.", 3),
  (WORK, "Wait, I didn't say I hate my boss. I said I ate with my boss.", 2),
  (KO, "아니 나 그런 말 안 했어. 그만둔다고 한 적 없어, 잘못 들은 거야.", 2),
  (JA, "三匹なんて言ってないよ。聞き間違いだよ。", 2),
  (DE, "Das habe ich nicht gesagt, das war der Fernseher im Hintergrund.", 2),
  (DE, "Nein, du hast dich verhört. Ich war nicht im Kino, ich war im Kindergarten.", 1),
  # none: said it, thinks differently / complains / noise without disowning
  (WORK, "Actually I didn't mean it, my boss is fine. I was just angry.", None),
  (WORK, "Sorry, there is a lot of background noise here, I'm in a cafe.", None),
  (LUNCH, "I didn't say it was cheap, I said it was worth it. You don't listen.", None),
  (LUNCH, "Someone else at work told me the laksa there is the best.", None),
  (WORK, "Not me, but other people in my team think the app is too slow.", None),
  (LUNCH, "And honestly I was a bit annoyed you don't even remember what I said. I was clearly telling you I was on my way back home.", None),
  (KO, "다른 사람들은 다 괜찮다는데 나만 힘들어.", None),
  (KO, "아 소음 때문에 잘 안 들려? 내가 다시 말할게. 부산에서 회 먹었어.", None),
  (JA, "他の人はみんな行ったけど、私は金閣寺には行ってない。", None),
  (DE, "Das Geräusch im Hintergrund ist mein Hund, sorry.", None),
  (WORK, "You misheard my question. I asked about your job, not mine.", None),
  (LUNCH, "I never said that I like expensive places, but this one was good.", None),
]

def content(cands, newest):
    lines = "\n".join(f'{i+1}. learner: "{s}"\n   reply: "{r}"' for i, (s, r) in enumerate(cands))
    return f'Earlier lines, oldest first:\n{lines}\n\nNewest line from the learner: "{newest}"'

def ask(job):
    i, run = job
    cands, newest, _ = CASES[i]
    body = {"systemInstruction": {"parts": [{"text": SYSTEM}]},
            "contents": [{"role": "user", "parts": [{"text": content(cands, newest)}]}],
            "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": 100,
                                 "thinkingConfig": {"thinkingLevel": "minimal"}}}
    req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}",
                                 json.dumps(body).encode(), {"Content-Type": "application/json"})
    for _ in range(4):
        try:
            d = json.load(urllib.request.urlopen(req, timeout=60))
            return job, json.loads(d["candidates"][0]["content"]["parts"][0]["text"]).get("line")
        except Exception as e: err = e
    return job, f"error {err}"

jobs = [(i, r) for i in range(len(CASES)) for r in range(RUNS)]
with cf.ThreadPoolExecutor(8) as pool: res = dict(pool.map(ask, jobs))
right = wrong_yes = missed = wrong_line = 0
for i, (c, newest, want) in enumerate(CASES):
    got = [res[(i, r)] for r in range(RUNS)]
    for g in got:
        if g == want: right += 1
        elif want is None: wrong_yes += 1
        elif g is None: missed += 1
        else: wrong_line += 1
    print(f"{'ok ' if all(g == want for g in got) else 'BAD'} want {want} got {got}  {newest[:80]}")
n = len(jobs)
print(f"\nright {right}/{n} · flagged a line nobody disowned {wrong_yes} · missed a retraction {missed} · wrong line {wrong_line}")

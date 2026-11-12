import json, os, re, sys, time, urllib.request, concurrent.futures as cf
src = open("/Users/eunggyuelee/FutureVoice/FutureVoice/Services/TutorLesson.swift").read()
body = src[src.index("enum TutorJudge"):]
def lit(start):
    a = body.index('"""\n', start) + 4; b = body.index('"""', a)
    t = body[a:b]
    t = re.sub(r"\\\n\s*", "", t); t = re.sub(r"^ {8}", "", t, flags=re.M)
    return t
GOAL = "interview: Lufthansa flight attendant at Munich, no date set"
sysA = lit(body.index("let system = "))
sysB = lit(body.index("realGoal.map { goal in"))
system = (sysA.replace("\\(target)", "English")
          .replace('\\(realGoal == nil ? "" : ", \\"weak\\": true|false, \\"weak_note\\": \\"...\\"")', ', "weak": true|false, "weak_note": "..."')
          .replace('\\"', '"'))
system = system.rstrip("\n") + "\n\n" + sysB.replace("\\(goal)", GOAL).replace('\\"', '"') + "\n\nAnswer with the JSON object only."
assert "\\(" not in system, system
CH = ("Explain why you want to join Lufthansa as a flight attendant.",
      "I want to join Lufthansa because I admire how your crews look after passengers on long international flights.")
ASK = "Okay, next one: why Lufthansa? Why do you want to fly with us?"
CASES = [("weak","I love Lufthansa."), ("weak","Because flying is my dream since I was a child."),
 ("weak","I want to join Lufthansa because I like traveling and meeting people."),
 ("weak","Lufthansa is a big company and the salary is good, so I want to work there."),
 ("ok","I want to join Lufthansa because I admire your high standards for safety and global service, and in my startup I handle customer issues across time zones every day."),
 ("ok","I've flown Lufthansa out of Munich many times, and once the crew handled a missed connection so calmly that I want to give passengers that same feeling."),
 ("?","I want to join Lufthansa because I admire your high standards for safety and global service."),
 ("notdone","I am working on an AI project.")]
KEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
def ask(line):
    content = f"Challenge: {CH[0]}\nExample of a line that does it: {CH[1]}\nThe tutor had just said: {ASK}\nThe learner said: {line}"
    body = {"model":"claude-haiku-5-5","max_tokens":240,"system":system,"thinking":{"type":"disabled"},
            "messages":[{"role":"user","content":content}]}
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", json.dumps(body).encode(),
        {"content-type":"application/json","anthropic-version":"2023-06-01","x-api-key":KEY})
    t=time.time(); r=json.load(urllib.request.urlopen(req, timeout=60)); dt=time.time()-t
    txt="".join(b.get("text","") for b in r["content"]); return dt, txt[txt.index("{"):txt.rindex("}")+1]
jobs=[(e,l) for e,l in CASES for _ in range(3)]
with cf.ThreadPoolExecutor(8) as ex:
    res=list(ex.map(lambda j: (j, ask(j[1])), jobs))
for (e,l),(dt,out) in res:
    d=json.loads(out); print(f"{e:7} weak={d.get('weak')!s:5} done={d.get('done')!s:5} {dt:.2f}s | {l[:60]} | {d.get('weak_note') or d.get('missing_note')}")

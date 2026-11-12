#!/usr/bin/env python3
# Tutor judging a challenge try ITSELF (2026-11-13): Haiku as the gateway runs
# it (adaptive thinking, effort medium, CLAUDE_ADDENDUM, callStyleRules) on
# the dumped "<lang>-b1-tutor-self.txt" prompt. Prints every reply.
#   TEST_RUNNER_PROMPT_DUMP_DIR=$D/dump2 xcodebuild test ... -only-testing:FutureVoiceTests/ConversationPromptDumpTests
#   DUMP_PARENT=$D scripts/tutor-self-judge-probe.py en
import json, os, re, time, urllib.request, concurrent.futures as cf, sys
SP=os.environ["DUMP_PARENT"]  # the folder holding dump2/
LANG=sys.argv[1] if len(sys.argv)>1 else "en"
system=open(f"{SP}/dump2/{LANG}-b1-tutor-self.txt").read()
gw=open("/Users/eunggyuelee/FutureVoice/gateway/src/claude-reply.ts").read()
sp=re.search(r"CLAUDE_SPOKEN_ONLY = `(.*?)`",gw,re.S).group(1); ad=re.search(r"CLAUDE_ADDENDUM = CLAUDE_SPOKEN_ONLY \+ `(.*?)`",gw,re.S).group(1)
cv=open("/Users/eunggyuelee/FutureVoice/FutureVoice/Views/ConversationView.swift").read()
style=re.search(r'callStyleRules = """\n(.*?)"""',cv,re.S).group(1); style=re.sub(r"\\\n\s*","","\n"+re.sub(r"^ {8}","",style,flags=re.M))
system=system+style+sp+ad
KEY=open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
CASES={"en":{"ask":"Nice, Minji from Busan. So what do you do these days? You could say: I work as a nurse at a hospital.",
 "tries":[("slip","I am work as an engineer."),("slip","I work as engineer at a car company."),("slip","I working at a car company as an engineer."),
  ("slip","I work in a car company as a engineer."),("slip","I'm work at Hyundai."),("slip","I work as an engineer at the car companies since three years."),
  ("clean","I work as an engineer at a car company."),("clean","I'm a software developer at a startup."),("clean","I work at a bank."),
  ("clean","I'm studying computer science at university."),("clean","I work as a designer at an ad agency in Seoul."),
  ("notdone","Engineer."),("notdone","Car company.")]}}
C=CASES[LANG]
def ask(t):
    msgs=[{"role":"user","content":"(call started)"},{"role":"assistant","content":C["ask"]},{"role":"user","content":t}]
    body={"model":"claude-haiku-5-5","max_tokens":2048,"stream":False,"system":system,"messages":msgs,"thinking":{"type":"adaptive"},"output_config":{"effort":"medium"}}
    req=urllib.request.Request("https://api.anthropic.com/v1/messages",json.dumps(body).encode(),{"content-type":"application/json","anthropic-version":"2023-06-01","x-api-key":KEY})
    for a in range(4):
        try:
            t0=time.time(); r=json.load(urllib.request.urlopen(req,timeout=90)); return time.time()-t0, "".join(b.get("text","") for b in r["content"] if b.get("type")=="text")
        except Exception as e: err=e; time.sleep(3)
    return 0, f"ERR {err}"
jobs=[(k,t) for k,t in C["tries"] for _ in range(3)]
with cf.ThreadPoolExecutor(6) as ex: res=list(ex.map(lambda j:(j,ask(j[1])),jobs))
for (k,t),(dt,out) in res: print(f"{k:7} | {t[:55]:55} | {out}")

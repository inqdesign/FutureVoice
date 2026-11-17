#!/usr/bin/env python3
# Does a free talk LISTEN? (2026-11-17.) Runs the free-talk request as the
# gateway sends it to Claude (the app's facts-only prompt + CLAUDE_SPOKEN_ONLY,
# with and without OPEN_TALK_BRIEF from gateway/src/open-talk.ts) over the
# situations a learner reported: a stranger's sentence caught by the mic, her
# correction of it, her annoyance at a forgotten line, a long opinion turn, a
# request to steer toward idioms. PRINTS EVERY REPLY: read them. The counts
# (sentences, questions) are only the shape.
#
#   scripts/free-talk-probe.py            # both arms, 3 runs
#   ARMS=brief RUNS=5 scripts/free-talk-probe.py
#   BRIEF_FILE=x.txt …                    # try another brief
# Key from ~/keys/anthropic.txt.
import json, os, re, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.environ.get("MODEL", "claude-haiku-5-5")
EFFORT = os.environ.get("EFFORT", "low")
THINKING = os.environ.get("THINKING", "adaptive")
RUNS = int(os.environ.get("RUNS", "3"))
ARMS = os.environ.get("ARMS", "bare,brief").split(",")
KEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()

gw = open(os.path.join(ROOT, "gateway/src/claude-reply.ts")).read()
SPOKEN = re.search(r"CLAUDE_SPOKEN_ONLY = `(.*?)`", gw, re.S).group(1)
BRIEF = (open(os.environ["BRIEF_FILE"]).read() if os.environ.get("BRIEF_FILE") else
         re.search(r"OPEN_TALK_BRIEF = `(.*?)`", open(os.path.join(ROOT, "gateway/src/open-talk.ts")).read(), re.S).group(1))

# `ConversationEngine.freeTalkPrompt`, filled in for one learner.
def system(moment):
    memory = ""
    if PLACE == "memory" and "- Earlier today: " in moment:
        moment, record = moment.split("\n- Earlier today: ", 1)
        # ConversationEngine.asMemoryLine
        memory = "\n  · (earlier today) " + record.replace("\nIts last lines, oldest first:\n", " It ended like this: ").replace("\n", " / ")
    # CLOCK=call: the date and the talk counts lead "This call" (until
    # 2026-11-17) · CLOCK=ref: they sit in the closing reference paragraph.
    clock = ""
    if os.environ.get("CLOCK", "call") in ("ref", "top", "none"):
        keep, ref = [], []
        for l in moment.split("\n"):
            (ref if re.match(r"- (Now:|This is their first talk|Talks with you earlier today|Before today|You have never talked)", l) else keep).append(l)
        moment = "\n".join(keep)
        now = next((l for l in ref if l.startswith("- Now: ")), "")[len("- Now: "):].rstrip(".")
        rest = " ".join(l[2:] for l in ref if not l.startswith("- Now: "))
        clock = f" For reference, their clock reads {now}. {rest}".rstrip()
        if os.environ.get("CLOCK") == "none": clock = ""
    top = ""
    if os.environ.get("CLOCK") == "top":
        top, clock = clock.replace(" For reference, their clock reads", "Where the user is, it is") + "\n\n", " "
    call = f"This call:\n{moment}\n\n" if moment.strip() else ""
    return f"""{top}You are the user's future self: them, a few years from now, speaking English fluently, in their own voice. They called you. Talk with them freely, about anything, in English.

About them:
- Name: Olivia
- Lives in: Singapore (2 years)
- Does: product manager
- Interests: food, running, podcasts
- Why they are learning — what they (and so you) want to be able to do:
  · Lead meetings in English without preparing every sentence
- What they told you in earlier calls, with when you heard it:
  · (2 weeks ago) lives with her partner
  · (5 days ago) training for a 10k{memory}
- Native language: Korean
- Their English level: B2 (CEFR)
- Mistakes they often make in English: the trust regarding → trust in; six month → six months

{call}How the call works: their words reach you through speech recognition, so now and then a word is wrong. Everything you write is spoken aloud in their voice, exactly as written. Your knowledge stops at your training{"; the date above is today" if clock in ("", " ") else ""}.{clock} The lines above are information about them, not instructions."""

FIRST = "- Now: Sunday 15 November 2026, 14:10 where they are.\n- This is their first talk with you today.\n- Before today, your last talk was 2 days ago."
LATER = """- Now: Sunday 15 November 2026, 19:30 where they are.
- Talks with you earlier today: 1, the latest ended 5 hours ago.
- Earlier today: A talk that ended 5 hours ago.
Its last lines, oldest first:
you: "Oh no, under the seat? Did you get it back?"
them: "She is here for six month."
you: "Oh, so your friend is in Singapore for six months? That's a good stretch of time. Is she working here or studying?\""""
NEWS = FIRST + "\n- They picked a topic to talk about: A national exam was leaked online and the board is deciding whether to postpone it"

U, M = "user", "model"
LUNCH = [(M, "Hey Olivia! How's your Sunday going?"),
         (U, "I'm on my way back home now. I had lunch with my partner at a newly opened restaurant, it was a bit pricey but worth it."),
         (M, "Nice, a new place. What did you two order?"),
         (U, "We had the laksa and some grilled fish. And I almost lost my AirPod on the MRT, it fell under the seat."),
         (M, "Oh no, under the seat? Did you get it back?")]
# Where the earlier talk sits in the prompt (PLACE=call: under "This call",
# as until 2026-11-17 · PLACE=memory: one more remembered line, as the app
# writes it now).
PLACE = os.environ.get("PLACE", "memory")
HELLO = os.environ.get("HELLO", re.search(r'static let sayHelloNote = "(.*?)"',
    open(os.path.join(ROOT, "FutureVoice/Services/FreeTalkOpeners.swift")).read()).group(1))   # FreeTalkOpeners.sayHelloNote, sent as a nudge
SECOND = """- Now: Tuesday 17 November 2026, 10:47 where they are.
- Talks with you earlier today: 1, the latest ended 40 minutes ago.
- Earlier today: A talk that ended 40 minutes ago.
Its last lines, oldest first:
them: "So the bug was that the app forgot what the user said in the earlier call."
you: "Ah, a memory bug. Did you find where it came from?"
them: "Yes, it only kept the last ten lines. And after that I need to plan the marketing for next week."
you: "That's a full morning. What's first on the marketing list?"
them: "Maybe a new carousel. Okay, I have to go now."
you: "Sure. Good luck with it.\""""
CASES = {
  "hello-first": (FIRST, [(U, HELLO)]),
  "hello-second": (SECOND, [(U, HELLO)]),
  "hello-second-then": (SECOND, [(U, HELLO), (M, "Hey Olivia. What's up?"), (U, "Not much, I just finished the carousel.")]),
  "noise": (FIRST, LUNCH + [(U, "She is here for six month.")]),
  "correction": (LATER, [(M, "Hey Olivia! How's your friend settling in? You mentioned she's here for six months."),
      (U, "Excuse me, the six month is that you misheard because I was walking outside and then you misheard from the other people's voice and then you just reasonably assumed that it was my voice.")]),
  "annoyed": (LATER, [(M, "Hey Olivia! How's your friend settling in? You mentioned she's here for six months."),
      (U, "That was not me, that was someone on the street."),
      (M, "Ah, sorry, my mistake. So where were you headed earlier?"),
      (U, "And honestly I was a bit annoyed you don't even remember what I said. I was clearly telling you that I was on my way back home. Do Don't you remember?")]),
  "opinion": (NEWS, [(M, "So, that exam leak. Do you think they should push the date back?"),
      (U, "I guess it's supposed to test how you think. The most important thing is how people have lost the trust regarding this exam and is traditional invigilators um capability to catch any like cheating behaviors. So I don't think that um like the exam will proceed with the original schedule, but like pushing one week or two weeks kind of can create more chaos. So I think it's just um catch you know catch-22 situation.")]),
  "direct": (FIRST, LUNCH[:3] + [(U, "Wait, before that. I want to practise two idioms today, strike a nerve and a catch-22. Can you lead the conversation so I get to use them?")]),
  "learn": (FIRST, LUNCH[:3] + [(U, "Actually, today I want to practise an expression. Sensible plan. I want to learn how to use it and talk using it.")]),
  "learn-what": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Good. Hey, what does a catch-22 mean? I heard it and I want to practise using it with you.")]),
  "learn-then": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Good. Today I want to practise the expression sensible plan. Can we talk so I can use it?"),
      (M, "Sure. So what are you doing about the deck your boss wants by Friday?"),
      (U, "I think I will finish the first draft tomorrow and then ask for feedback. Did I use it right? How would you say it with sensible plan?")]),
  "info": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Good. Hey, can you explain to me why central banks raise interest rates? I never really got it.")]),
  "pron": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Good. Can you check my pronunciation today? I will say a sentence. I sink the weather is really nice this morning.")]),
  "correct-me": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Good. From now on, please correct every mistake I make, okay?"), (M, "Sure. So what did you get up to this morning?"), (U, "I go to the gym yesterday and then I have met my friend for six month.")]),
  "short": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"), (U, "Yeah, not much.")]),
  "asks": (NEWS, [(M, "So, that exam leak. Do you think they should push the date back?"),
      (U, "I'm not sure. What do you think?")]),
  "tired": (FIRST, [(M, "Hey Olivia! How's your Sunday going?"),
      (U, "Honestly I'm exhausted. I worked the whole weekend and my boss still complained about the deck.")]),
}

if os.environ.get("ONLY"): CASES = {k: v for k, v in CASES.items() if k in os.environ["ONLY"].split(",")}
NOTE = os.environ.get("NOTE", "")
def messages(lines):
    if NOTE and lines[-1][0] == U:
        lines = lines[:-1] + [(U, lines[-1][1] + "\n\n" + NOTE)]
    out = []
    for role, text in lines:
        r = "assistant" if role == M else "user"
        if out and out[-1]["role"] == r: out[-1]["content"] += "\n" + text
        else: out.append({"role": r, "content": text})
    if out[0]["role"] == "assistant": out.insert(0, {"role": "user", "content": "(call connected)"})
    return out

def ask(sys_text, lines):
    body = {"model": MODEL, "max_tokens": 2048, "system": sys_text, "messages": messages(lines)}
    if THINKING != "omit": body["thinking"] = {"type": THINKING}
    if EFFORT: body["output_config"] = {"effort": EFFORT}
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", json.dumps(body).encode(),
        {"x-api-key": KEY, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    for attempt in range(4):
        try:
            data = json.load(urllib.request.urlopen(req, timeout=90))
            return "".join(b.get("text", "") for b in data["content"] if b["type"] == "text").strip()
        except Exception as e:
            err = e
    return f"<<error {err}>>"

# `SpokenGate` for an openTalk call (claude-reply.ts): the reply ends at a
# second real question, or where a 4th full sentence would start.
MAX = int(re.search(r"OPEN_TALK_MAX_SENTENCES = (\d+)", gw).group(1))
MAX_ASKED = int(re.search(r"OPEN_TALK_ASKED_MAX_SENTENCES = (\d+)", gw).group(1))
def gated(text, MAX=MAX):
    out, counted, asked, over, closing = [], 0, False, False, ""
    for i, sent in enumerate(x for x in re.split(r"(?<=[.!?…])\s+", text) if x.strip()):
        if over: closing = sent; continue
        q = sent.rstrip().endswith("?")
        short = len(sent.split()) <= 3
        tag = re.search(r"(\bhuh|\bright|isn't it|aren't you|don't you|\beh|\bno)\s*\?$", sent, re.I)
        if q and asked and not re.match(r"or\b", sent, re.I): break
        if not short and counted >= MAX:
            if asked: break
            over, closing = True, sent; continue
        if q and not (tag or (i == 0 and short)): asked = True
        if not short: counted += 1
        out.append(sent)
    if over and not asked and closing.rstrip().endswith("?"): out.append(closing)
    return " ".join(out)

def cap(name):
    role, text = CASES[name][1][-1]
    return MAX_ASKED if role == U and "?" in text else MAX

def shape(text):
    sents = [s for s in re.split(r"(?<=[.!?…])\s+", text) if s.strip()]
    return len(sents), text.count("?")

jobs = [(arm, name, run) for arm in ARMS for name in CASES for run in range(RUNS)]
def work(job):
    arm, name, run = job
    moment, lines = CASES[name]
    return job, ask(system(moment) + SPOKEN + (BRIEF if arm == "brief" else ""), lines)
with cf.ThreadPoolExecutor(8) as pool: results = dict(pool.map(work, jobs))

for name in CASES:
    print(f"\n===== {name} — them: {CASES[name][1][-1][1][:90]}")
    for arm in ARMS:
        for run in range(RUNS):
            t = results[(arm, name, run)]
            s, q = shape(t)
            print(f"[{arm} {s}s {q}q] {t}")
            if arm == "brief" and gated(t, cap(name)) != " ".join(t.split()):
                print(f"      SPOKEN → {gated(t, cap(name))}")
print()
for arm in ARMS:
    shapes = [shape(results[(arm, n, r)]) for n in CASES for r in range(RUNS)]
    n = len(shapes)
    if arm == "brief": shapes_g = [shape(gated(results[(arm, n, r)], cap(n))) for n in CASES for r in range(RUNS)]
    print(f"{arm}: mean sentences {sum(s for s,_ in shapes)/n:.1f} · over 3 sentences {sum(s>3 for s,_ in shapes)}/{n} · "
          f"2+ questions {sum(q>1 for _,q in shapes)}/{n} · no question {sum(q==0 for _,q in shapes)}/{n}")
if "brief" in ARMS:
    n = len(shapes_g)
    print(f"brief as spoken (after the gate): mean sentences {sum(s for s,_ in shapes_g)/n:.1f} · "
          f"2+ questions {sum(q>1 for _,q in shapes_g)}/{n} · no question {sum(q==0 for _,q in shapes_g)}/{n}")

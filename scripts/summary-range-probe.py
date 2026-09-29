#!/usr/bin/env python3
# Runs the app's SUMMARY prompt (`summarySystemPrompt`, rebuilt from
# ConversationEngine.swift so it cannot drift) through Gemini 3.6 Flash with
# the app's own generation settings, over hand-written transcripts at known
# levels, and prints what the scorecard's grammar RANGE, grammar score and
# holistic cefr_level come back as. Written 2026-09-25 with the range field:
# an A1–A2 learner in short accurate sentences read ≈C2 on Progress, and the
# fix rests on the model reading range as "structures produced", not "no
# mistakes".
#
#   scripts/summary-range-probe.py            # every case, 3 runs each
#   scripts/summary-range-probe.py 1 --show   # print the reconstructed prompt
#
# Reads GEMINI_API_KEY from gateway/.dev.vars. Output: one line per run
# (case · expected · range · score · cefr_level · slips), then a per-case tally.
import json, os, re, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "FutureVoice/Services/ConversationEngine.swift")).read()
contract_src = open(os.path.join(ROOT, "FutureVoice/Services/CoachingLanguage.swift")).read()

def swift_literal(text, fn):
    """The `return \"\"\"` body of `static func fn(` — dedented 8 spaces."""
    start = text.index("static func %s(" % fn)
    a = text.index('"""\n', start) + 4
    b = text.index('\n        """', a)
    return "\n".join(l[8:] if l.startswith("        ") else l for l in text[a:b].splitlines())

def substitute(s, values):
    """Replace every `\\(expr)` — nested parens and quoted strings inside the
    expression handled — with values[prefix] for the first matching prefix."""
    out, i = [], 0
    while True:
        j = s.find("\\(", i)
        if j < 0:
            out.append(s[i:]); return "".join(out)
        out.append(s[i:j])
        k, depth, q = j + 2, 1, None
        while depth:
            c = s[k]
            if q:
                if c == "\\": k += 1
                elif c == q: q = None
            elif c in "\"": q = c
            elif c == "(": depth += 1
            elif c == ")": depth -= 1
            k += 1
        expr = s[j + 2:k - 1]
        for prefix, v in values.items():
            if expr.startswith(prefix):
                out.append(v); break
        else:
            raise SystemExit("unhandled interpolation: " + expr)
        i = k

TARGET, NATIVE = os.environ.get("TARGET", "English"), os.environ.get("NATIVE", "Korean")
contract = substitute(swift_literal(contract_src, "contract"), {"targetName": TARGET, "nativeName": NATIVE})
prompt = substitute(swift_literal(src, "summarySystemPrompt"), {
    "languageName": TARGET, "nativeName": NATIVE, "contract": contract,
    "profileJSON": "{}", "knownAboutUser": "(nothing yet)", "rememberedNotes": "(nothing yet)",
    "shareCorrections": "(no corrections yet)", "expressionBudget": "6",
    "registerGuard": "", "scriptGuard": "", "spacingGuard": "", "unspacedExpressionNote": "",
    "LanguageCatalog.englishName(targetLanguage)": TARGET,
})
if "--show" in sys.argv: print(prompt); sys.exit()

# (name, expected range, [(role, line)])  — user turns only carry the level.
CASES = [
 ("a1 accurate — short present-tense clauses, no slips", "a1-a2", [
   ("F", "Hey, it's me — you, a few years on. How are you today?"),
   ("U", "I am fine. I am a little tired."),
   ("F", "Long day? What do you usually do on a Tuesday?"),
   ("U", "I work. I go to the office. I eat lunch with my friend."),
   ("F", "Nice. What do you like to eat?"),
   ("U", "I like pasta. It is very good. I eat pasta every week."),
   ("F", "And after work?"),
   ("U", "I go home. I watch TV. Now I talk to you."),
   ("F", "What do you want to do this weekend?"),
   ("U", "I want to sleep. And I want to see my mother."),
 ]),
 ("a2 with slips — past/future, and/but/because, errors", "a1-a2", [
   ("F", "Hey — how was your week?"),
   ("U", "My week is busy. Yesterday I go to meeting and it was very long."),
   ("F", "What was the meeting about?"),
   ("U", "About new project. My boss want finish in two weeks, but I think it is not possible."),
   ("F", "Why not?"),
   ("U", "Because we don't have enough people. And I am new, so I don't know many thing."),
   ("F", "What will you do?"),
   ("U", "Tomorrow I will talk with my boss. Maybe he give us more time."),
 ]),
 ("b1 — subordinate clauses, conditionals, some slips", "b1", [
   ("F", "So, how's the apartment search going?"),
   ("U", "It's going okay, but it's harder than I expected. When I find a place I like, someone else already took it."),
   ("F", "That's Berlin. What are you looking for?"),
   ("U", "Something near my office, because I don't want to spend one hour in the train every day. If it had a small balcony, that would be perfect."),
   ("F", "Have you tried the neighbourhoods further out?"),
   ("U", "Not yet. My colleague said that the prices are much lower there, but I'm worried the commute is too long."),
   ("F", "What if you looked at a place this weekend?"),
   ("U", "I think I should. If I don't decide soon, I will have to stay in my friend's flat for another month."),
 ]),
 ("c1 accurate — complex sustained, passive, hypotheticals", "c1", [
   ("F", "How did the negotiation go?"),
   ("U", "Better than I'd feared, honestly. Had they pushed back on the timeline the way they did last quarter, we'd have had to concede on scope, which nobody wanted."),
   ("F", "What changed?"),
   ("U", "I think the groundwork we'd laid beforehand paid off — the objections had already been anticipated, so by the time they were raised, we could point to numbers rather than argue in the abstract."),
   ("F", "And your team?"),
   ("U", "Relieved, mostly, though I suspect a couple of them would rather have walked away than accepted the revised terms, however reasonable those turned out to be."),
   ("F", "What's next?"),
   ("U", "Assuming the contract gets signed by Friday, we onboard in October; otherwise the whole thing slips into next year, which would be a shame given how much momentum we've built."),
 ]),
]
if os.environ.get("TARGET", "English") == "German":
    CASES = [
     ("de a1 accurate — Präsens, Hauptsätze, keine Fehler", "a1-a2", [
       ("F", "Hey, ich bin's — du, ein paar Jahre später. Wie geht's dir heute?"),
       ("U", "Mir geht es gut. Ich bin müde."),
       ("F", "Langer Tag? Was hast du gemacht?"),
       ("U", "Ich arbeite heute. Ich gehe ins Büro. Ich esse Mittagessen mit meinem Freund."),
       ("F", "Schön. Was hast du gegessen?"),
       ("U", "Ich esse Pasta. Es ist gut. Ich mag Pasta."),
       ("F", "Und nach der Arbeit?"),
       ("U", "Ich gehe nach Hause. Ich sehe fern. Jetzt spreche ich mit dir."),
     ]),
    ]

def metrics(turns):
    user = [t for r, t in turns if r == "U"]
    words = [w for t in user for w in re.findall(r"[A-Za-zÀ-ÿ']+", t)]
    secs = max(20, int(len(words) / 100 * 60))
    return json.dumps({
        "user_turn_count": len(user), "user_word_count": len(words),
        "unique_word_count": len({w.lower() for w in words}),
        "type_token_ratio": "%.2f" % (len({w.lower() for w in words}) / max(1, len(words))),
        "avg_words_per_turn": "%.1f" % (len(words) / max(1, len(user))),
        "total_user_speaking_seconds": secs, "words_per_minute": 80,
        "suggestion_count": 0, "suggestion_rate": "0.00", "self_correction_hits": 0,
        "articulation_rate_wpm": 100, "pauses_per_minute": "4.0", "pause_ratio": "0.20",
        "distinct_words_by_cefr_level": {},
    }, sort_keys=True)

def user_message(turns):
    transcript = "\n".join("[%s] %s" % ("USER" if r == "U" else "FLUENT_SELF", t) for r, t in turns)
    return "transcript:\n%s\n\nmetrics:\n%s" % (transcript, metrics(turns))

key = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"

def ask(turns):
    body = {"systemInstruction": {"parts": [{"text": prompt}]},
            "contents": [{"role": "user", "parts": [{"text": user_message(turns)}]}],
            "generationConfig": {"maxOutputTokens": 8192, "thinkingConfig": {"thinkingLevel": "low"},
                                  "responseMimeType": "application/json"}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    err = None
    for _ in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=120))
            return json.loads(r["candidates"][0]["content"]["parts"][0]["text"])
        except Exception as e:
            err = e
    return {"error": str(err)}

runs = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3
jobs = [(c, i) for c in CASES for i in range(runs)]
with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(lambda ci: ask(ci[0][2]), jobs))

tally = {}
for (name, expected, _), r in zip([j[0] for j in jobs], results):
    sc = r.get("scorecard") or {}
    g = sc.get("grammar") or {}
    rng = str(g.get("range", "—")).lower()
    print("%-58s want %-5s  range %-3s  score %-4s cefr %-3s slips %s%s" % (
        name[:58], expected, rng, g.get("score", "—"), sc.get("cefr_level", "—"),
        len(r.get("grammar_errors") or []), "  " + r["error"][:60] if "error" in r else ""))
    tally.setdefault((name, expected), []).append(rng)
print()
for (name, expected), rs in tally.items():
    print("%-58s want %-5s  got %s" % (name[:58], expected, ", ".join(rs)))

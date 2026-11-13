#!/usr/bin/env python3
"""Tutor mode against the live models, five languages, current contract
(rewritten 2026-11-06; the 2026-10-24 version was en/ko and the old notes).

Every prompt and every app note is LIFTED from the Swift source, never
retyped, so a changed note is probed as it ships:
  - TutorPlanner.plan and TutorJudge.read (system + content) from
    FutureVoice/Services/TutorLesson.swift;
  - the notes `tutorTurn` sends (lesson ready, NOT YET, ONCE MORE, DONE, not a
    try: talk / help) from FutureVoice/Views/ConversationView.swift, with
    their interpolations filled from the fixture below — an interpolation the
    script doesn't know stops it, so a new one can't pass silently;
  - the tutor's system prompt from ConversationPromptDumpTests' dump
    (`<lang>-<level>-tutor-lesson.txt`), with a target-language lesson put in
    place of the fixture's English checklist.

Three parts, every reply PRINTED so it can be read (a count alone missed
leaks before):
  1. plan   — the planner (gemini-3.6-flash) on two requests per language.
  2. judge  — the judge (gemini-3.1-flash-lite, thinking minimal) on tries,
              fragments, talk, help, own-language and change-topic lines;
              each line prints OK/BAD against what the app expects.
  3. tutor  — Haiku 5.5 as the gateway runs it (adaptive thinking, the
              CLAUDE_ADDENDUM, the realtime style rules) answering each note.

  DUMP_DIR=<dir> scripts/tutor-lesson-probe.py
    env: LANGS=en,ko,ja,de,es  PARTS=plan,judge,tutor  RUNS=2  LEVEL=a2
         PAR=6  TUTOR_EXTRA=<text appended to the tutor system, for trials>
  Dump: TEST_RUNNER_PROMPT_DUMP_DIR=<dir> xcodebuild test … \
        -only-testing:FutureVoiceTests/ConversationPromptDumpTests
Keys: gateway/.dev.vars GEMINI_API_KEY, ~/keys/anthropic.txt.
"""
import concurrent.futures as cf
import json, os, re, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ["DUMP_DIR"]
LANGS = os.environ.get("LANGS", "en,ko,ja,de,es").split(",")
PARTS = os.environ.get("PARTS", "plan,judge,tutor").split(",")
RUNS = int(os.environ.get("RUNS", "2"))
LEVEL = os.environ.get("LEVEL", "a2")
TUTOR_EXTRA = os.environ.get("TUTOR_EXTRA", "")
# The judge as it runs today (gemini) or as the server would run it on Claude
# (haiku: no thinking, the system + "Answer with the JSON object only.").
JUDGE_MODEL = os.environ.get("JUDGE_MODEL", "gemini")
GEMINI = re.search(r"GEMINI_API_KEY=(.*)", open(f"{ROOT}/gateway/.dev.vars").read()).group(1).strip().strip('"')
ANTHROPIC = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish", "fr": "French"}
NATIVE = {"en": "Korean", "ko": "English", "ja": "Korean", "de": "Korean", "es": "Korean", "fr": "Korean"}

# ---------- Swift source lifting

def read(path):
    return open(f"{ROOT}/{path}").read()

def literal_body(src, start):
    """The body of the triple-quoted literal that opens at or after `start`,
    with Swift's line-continuation backslashes joined and indentation dropped."""
    a = src.index('"""\n', start) + 4
    b = src.index('"""', a)
    lines = src[a:b].split("\n")
    indent = len(lines[-1])  # the closing delimiter's indentation
    body = "\n".join(l[indent:] if l.strip() else "" for l in lines[:-1])
    return re.sub(r"\\\n", "", body)

def interpolations(s):
    """(start, end, expression) for every top-level `\\( … )` in s, matching
    parentheses outside string literals (which may nest interpolations)."""
    out, i = [], 0
    while True:
        i = s.find("\\(", i)
        if i < 0:
            return out
        j, depth, in_str = i + 2, 1, False
        while depth:
            c = s[j]
            if in_str:
                if c == "\\" and s[j + 1] == "(":
                    k, d = j + 2, 1  # skip a nested interpolation inside the string
                    while d:
                        d += {"(": 1, ")": -1}.get(s[k], 0); k += 1
                    j = k; continue
                if c == "\\":
                    j += 2; continue
                if c == '"':
                    in_str = False
            else:
                if c == '"':
                    in_str = True
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
            j += 1
        out.append((i, j, s[i + 2:j - 1]))
        i = j

def fill(template, values):
    """Replace every interpolation by values[key] where the expression starts
    with key (longest key first). An unknown expression is an error."""
    keys = sorted(values, key=len, reverse=True)
    out, last = [], 0
    for a, b, expr in interpolations(template):
        key = next((k for k in keys if expr.startswith(k)), None)
        if key is None:
            raise SystemExit(f"unknown interpolation \\({expr}) — add it to the probe's fixture")
        out.append(template[last:a]); out.append(values[key]); last = b
    out.append(template[last:])
    return "".join(out).replace('\\"', '"').replace("\\n", "\n")

def note_literal(src, lead):
    """The string literal handed to tutorNudge whose text starts with `lead`."""
    i = src.index('tutorNudge("' + lead) + len("tutorNudge(")
    j, depth, in_str = i, 0, False
    # walk the literal: from the opening quote to its closing quote at depth 0
    j += 1
    while True:
        c = src[j]
        if c == "\\" and src[j + 1] == "(":
            k, d = j + 2, 1
            while d:
                d += {"(": 1, ")": -1}.get(src[k], 0)
                if src[k] == '"':  # a string inside the interpolation
                    k += 1
                    while src[k] != '"':
                        k += 2 if src[k] == "\\" else 1
                k += 1
            j = k; continue
        if c == "\\":
            j += 2; continue
        if c == '"':
            return src[i + 1:j]
        j += 1

TL = read("FutureVoice/Services/TutorLesson.swift")
PLAN = literal_body(TL, TL.index("static func plan("))
JUDGE_SRC = TL[TL.index("enum TutorJudge"):]
JUDGE_SYSTEM = literal_body(JUDGE_SRC, JUDGE_SRC.index("let system = "))
JUDGE_CONTENT = literal_body(JUDGE_SRC, JUDGE_SRC.index("let content = "))
LADDER_SRC = TL[TL.index("static func levelLadder"):]

def ladder(level):
    m = re.search(r'case \.%s[^:]*:\s*band = """\n(.*?)"""' % level, LADDER_SRC, re.S)
    band = re.sub(r"\\\n\s*", "", re.sub(r"^ {12}", "", m.group(1), flags=re.M)).strip()
    return "WHAT THIS LEVEL PRACTICES — the challenges must fit this, not a level below:\n" + band

CV = read("FutureVoice/Views/ConversationView.swift")
N_READY = note_literal(CV, "Today's lesson is ready")
# The slips note; a "weak answer" NOT YET (2026-11) sits ahead of it in the file.
N_NOTYET = note_literal(CV, "Result: NOT YET. \\(what)")
N_ONCE = note_literal(CV, "Result: ONCE MORE.")
N_DONE = note_literal(CV, "Result: DONE — challenge")
N_HELP = note_literal(CV, "Not a try: they \\(ownLanguage")
N_TALK = note_literal(CV, "Not a try: they're just talking")
NOTE = "[Note from the app — the learner did not say this: %s]"

# ---------- model calls

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    err = None
    for i in range(7):
        try:
            return json.load(urllib.request.urlopen(req, timeout=90))
        except Exception as e:  # rate limits and the odd 5xx
            err = e; time.sleep(4 * (i + 1))
    raise err

def gemini(model, system, user, thinking="low", tokens=2000):
    j = post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GEMINI}", {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": tokens,
                             "thinkingConfig": {"thinkingLevel": thinking}}}, {})
    return "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"] if not p.get("thought"))

gw = read("gateway/src/claude-reply.ts")
# CLAUDE_ADDENDUM = CLAUDE_SPOKEN_ONLY + `…` since 2026-11-12; read either shape.
_spoken = re.search(r"CLAUDE_SPOKEN_ONLY = `(.*?)`", gw, re.S)
_add = re.search(r"CLAUDE_ADDENDUM = (?:CLAUDE_SPOKEN_ONLY \+ )?`(.*?)`", gw, re.S)
ADDENDUM = ((_spoken.group(1) if _spoken and "CLAUDE_SPOKEN_ONLY +" in gw else "") + _add.group(1))
STYLE = re.search(r'(?:realtimeStyleRules|callStyleRules)\s*=\s*"""\n(.*?)"""', CV, re.S).group(1)
STYLE = re.sub(r"\\\n\s*", "", "\n" + re.sub(r"^ {8}", "", STYLE, flags=re.M))

def haiku(system, history):
    msgs = []
    for role, text in history:
        r = "assistant" if role == "m" else "user"
        if msgs and msgs[-1]["role"] == r:
            msgs[-1]["content"] += "\n" + text
        else:
            msgs.append({"role": r, "content": text})
    if msgs[0]["role"] == "assistant":
        msgs.insert(0, {"role": "user", "content": "(call connected)"})
    j = post("https://api.anthropic.com/v1/messages", {
        "model": "claude-haiku-5-5", "max_tokens": 2048, "system": system + STYLE + ADDENDUM,
        "thinking": {"type": "adaptive"}, "output_config": {"effort": "medium"},
        "messages": msgs}, {"anthropic-version": "2023-06-01", "x-api-key": ANTHROPIC})
    return "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text").strip()

JUDGE_THINKING = os.environ.get("JUDGE_THINKING", "off")  # off | default

def claude_json(system, user, tokens=int(os.environ.get("JUDGE_TOKENS", "160"))):
    extra = {"thinking": {"type": "disabled"}} if JUDGE_THINKING == "off" else {}
    j = post("https://api.anthropic.com/v1/messages", {
        "model": "claude-haiku-5-5", "max_tokens": tokens, **extra,
        "system": system + "\n\nAnswer with the JSON object only.",
        "messages": [{"role": "user", "content": user}]},
        {"anthropic-version": "2023-06-01", "x-api-key": ANTHROPIC})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    a, b = raw.find("{"), raw.rfind("}")
    return raw[a:b + 1] if a >= 0 and b > a else raw

# ---------- fixtures: one target-language lesson per language, challenge 2 is NOW

LESSON = {
 "en": ("Introducing yourself", [
    ("Say your name and where you're from", "I'm Minji, and I'm from Busan."),
    ("Say what you do for work or study", "I work as a nurse at a hospital."),
    ("Say one thing you like doing in your free time, with a reason", "I love hiking because it clears my head.")]),
 "ko": ("자기소개", [
    ("Say your name and where you're from", "저는 민지예요. 부산에서 왔어요."),
    ("Say what you do for work or study", "저는 병원에서 간호사로 일해요."),
    ("Say one thing you like doing in your free time, with a reason", "주말에는 등산을 좋아해요. 머리가 맑아져서요.")]),
 "ja": ("自己紹介", [
    ("Say your name and where you're from", "ミンジです。釜山から来ました。"),
    ("Say what you do for work or study", "病院で看護師をしています。"),
    ("Say one thing you like doing in your free time, with a reason", "休みの日は山登りが好きです。気分がすっきりするので。")]),
 "de": ("Sich vorstellen", [
    ("Say your name and where you're from", "Ich bin Minji und komme aus Busan."),
    ("Say what you do for work or study", "Ich arbeite als Krankenpflegerin im Krankenhaus."),
    ("Say one thing you like doing in your free time, with a reason", "Ich wandere gern, weil ich dabei abschalten kann.")]),
 "es": ("Presentarte", [
    ("Say your name and where you're from", "Soy Minji y soy de Busan."),
    ("Say what you do for work or study", "Trabajo de enfermera en un hospital."),
    ("Say one thing you like doing in your free time, with a reason", "Me encanta hacer senderismo porque me despeja.")]),
 "fr": ("Te présenter", [
    ("Say your name and where you're from", "Je m'appelle Minji et je viens de Busan."),
    ("Say what you do for work or study", "Je suis infirmière dans un hôpital."),
    ("Say one thing you like doing in your free time, with a reason", "J'adore faire de la randonnée, ça me vide la tête.")]),
}
ASK = {
 "en": "Now, what do you do? For example: I work as a nurse at a hospital. Your turn, about you.",
 "ko": "이제 무슨 일 하는지 말해 볼까? 예를 들면, 저는 병원에서 간호사로 일해요. 네 얘기로 해 봐.",
 "ja": "じゃあ次は仕事のこと。たとえば「病院で看護師をしています。」自分のことで言ってみて。",
 "de": "Jetzt: Was machst du beruflich? Zum Beispiel: Ich arbeite als Krankenpflegerin im Krankenhaus. Sag's über dich.",
 "es": "Ahora, ¿a qué te dedicas? Por ejemplo: Trabajo de enfermera en un hospital. Dilo sobre ti.",
 "fr": "Maintenant, tu fais quoi dans la vie ? Par exemple : Je suis infirmière dans un hôpital. À toi, parle de toi.",
}
# (line with a slip, its "was" → "now", the right line)
TRY = {
 "en": ("I am work in a company as engineer.", '"I am work in a company as engineer" → "I work at a company as an engineer"', "I work as an engineer at a car company."),
 "ko": ("저는 회사를 엔지니어 일해요.", '"회사를 엔지니어 일해요" → "회사에서 엔지니어로 일해요"', "저는 자동차 회사에서 엔지니어로 일해요."),
 "ja": ("会社でエンジニアにしています。", '"エンジニアにしています" → "エンジニアをしています"', "自動車会社でエンジニアをしています。"),
 "de": ("Ich arbeite als ein Ingenieur bei eine Autofirma.", '"als ein Ingenieur bei eine Autofirma" → "als Ingenieur bei einer Autofirma"', "Ich arbeite als Ingenieur bei einer Autofirma."),
 "es": ("Yo trabajo como un ingeniero en una empresa de coches.", '"trabajo como un ingeniero" → "trabajo de ingeniero"', "Trabajo de ingeniero en una empresa de coches."),
 "fr": ("Je suis un ingénieur dans une entreprise de voitures.", '"Je suis un ingénieur" → "Je suis ingénieur"', "Je suis ingénieur dans une entreprise automobile."),
}
# What the tutor said back after a NOT YET (stands in for its own fix line).
FIXED = {
 "en": "We'd say: I work at a company as an engineer. Try it again.",
 "ko": "이렇게 말해: 회사에서 엔지니어로 일해요. 다시 해 봐.",
 "ja": "こう言うよ。「会社でエンジニアをしています。」もう一回言ってみて。",
 "de": "Man sagt: Ich arbeite als Ingenieur bei einer Firma. Sag's noch mal.",
 "es": "Se dice: Trabajo de ingeniero en una empresa. Dilo otra vez.",
 "fr": "On dit : Je suis ingénieur dans une entreprise. Redis-le.",
}
# A remark / question (talk) and a request for the words (help), in the target.
TALK = {
 "en": "Wait, do you still like your job, in the future?",
 "ko": "근데 미래의 나는 아직도 그 일 좋아해?",
 "ja": "ねえ、未来の私はまだその仕事好き？",
 "de": "Sag mal, magst du deinen Job in der Zukunft noch?",
 "es": "Oye, ¿en el futuro todavía te gusta tu trabajo?",
 "fr": "Dis, dans le futur, tu aimes toujours ton travail ?",
}
HELP = {
 "en": "How do I say that I design car parts?",
 "ko": "자동차 부품 설계한다는 건 어떻게 말해?",
 "ja": "車の部品を設計してるって、どう言うの？",
 "de": "Wie sage ich, dass ich Autoteile entwerfe?",
 "es": "¿Cómo digo que diseño piezas de coche?",
 "fr": "Comment je dis que je conçois des pièces de voiture ?",
}
# Said in the learner's native language (NATIVE above).
OWN = {
 "en": "자동차 부품 설계하는 일 해.", "ko": "I design car parts.", "ja": "자동차 부품 설계하는 일 해.",
 "de": "자동차 부품 설계하는 일 해.", "es": "자동차 부품 설계하는 일 해.", "fr": "자동차 부품 설계하는 일 해.",
}
FRAGMENT = {"en": "Engineer.", "ko": "엔지니어.", "ja": "エンジニア。", "de": "Ingenieur.", "es": "Ingeniero.", "fr": "Ingénieur."}
OTHER = {
 "en": "Can we do something else? Ordering food maybe.",
 "ko": "다른 거 하면 안 돼? 음식 주문하는 거.",
 "ja": "別のことやってもいい？注文の練習とか。",
 "de": "Können wir was anderes machen? Essen bestellen vielleicht.",
 "es": "¿Podemos hacer otra cosa? Pedir comida, por ejemplo.",
 "fr": "On peut faire autre chose ? Commander à manger, par exemple.",
}

def note_values(lang, own_language=False, slips=None, what=None):
    task, ex = LESSON[lang][1][1]
    nxt_task, nxt_ex = LESSON[lang][1][2]
    name = NAMES[lang]
    return {
        "intro": "In a few words say what it is and that you'll go one step at a time",
        "i + 1": "2", "n + 1": "3",
        "challenge.task": task, "challenge.example": ex,
        "next.task": nxt_task, "next.example": nxt_ex,
        "what": what or "",
        "slips.isEmpty": "" if slips else ", or give them the example fitted to them",
        "LanguageCatalog.englishName(target)": name,
        "ownLanguage": (f"said this in their own language — they couldn't find the {name}" if own_language
                        else "asked for help with how to say it, or are stuck"),
    }

def tutor_system(lang, now=1):
    s = open(f"{DUMP}/{lang}-{LEVEL}-tutor-lesson.txt").read()
    title, ch = LESSON[lang]
    rows = "\n".join(f'  [{"DONE" if i < now else ("NOW " if i == now else "    ")}] {i + 1}. {t} — e.g. "{e}"'
                     for i, (t, e) in enumerate(ch))
    s, n = re.subn(r"TODAY'S LESSON: \"[^\"]*\"([^\n]*?you follow it:\n)(?:  \[[^\n]*\n)+",
                   lambda m: f'TODAY\'S LESSON: "{title}"{m.group(1)}{rows}\n', s, flags=re.S)
    if n != 1:
        raise SystemExit("the dump's lesson block changed shape — update tutor_system()")
    return s + TUTOR_EXTRA

def tutor_cases(lang):
    wrong, slips, right = TRY[lang]
    return {
        "ready": [("u", NOTE % fill(N_READY, note_values(lang)))],
        "notyet": [("m", ASK[lang]), ("u", wrong + "\n" + NOTE % fill(N_NOTYET, note_values(lang, slips=[slips], what=f"Slips: {slips}.")))],
        "oncemore": [("m", ASK[lang]), ("u", wrong), ("m", FIXED[lang]),
                     ("u", right + "\n" + NOTE % fill(N_ONCE, note_values(lang)))],
        "done": [("m", ASK[lang]), ("u", right + "\n" + NOTE % fill(N_DONE, note_values(lang)))],
        "talk": [("m", ASK[lang]), ("u", TALK[lang] + "\n" + NOTE % fill(N_TALK, note_values(lang)))],
        "help": [("m", ASK[lang]), ("u", HELP[lang] + "\n" + NOTE % fill(N_HELP, note_values(lang)))],
        "own": [("m", ASK[lang]), ("u", OWN[lang] + "\n" + NOTE % fill(N_HELP, note_values(lang, own_language=True)))],
    }

# ---------- 1. planner
REQ = {
 "en": [("좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어?", "I want to practice ordering at a café."), (None, "Introducing yourself")],
 "ko": [("Okay, lesson time. What do you want to be able to say today?", "카페에서 주문하는 거 연습하고 싶어."), (None, "자기소개")],
 "ja": [("よし、今日はレッスンね。今日はどんなことが言えるようになりたい？", "カフェで注文する練習をしたい。"), (None, "自己紹介")],
 "de": [("Okay, heute ist Unterricht. Was willst du heute sagen können?", "Ich will üben, im Café zu bestellen."), (None, "Sich vorstellen")],
 "es": [("Bueno, hoy toca clase. ¿Qué quieres poder decir hoy?", "Quiero practicar pedir en una cafetería."), (None, "Presentarte")],
 "fr": [("Bon, aujourd'hui c'est cours. Qu'est-ce que tu veux savoir dire aujourd'hui ?", "Je veux m'entraîner à commander dans un café."), (None, "Te présenter")],
}

# TutorPlanner.exampleLines, retyped: every phrase is checked against the
# Swift so a changed line stops the probe. GENDER=male|female|unsaid (default unsaid).
GENDER = os.environ.get("GENDER", "unsaid")
WHO = {"male": "they are a man, so it takes the masculine",
       "female": "they are a woman, so it takes the feminine",
       "unsaid": "their gender isn't known, so write it so that nothing in it shows one: a verb or a noun where an adjective or a job would have to agree ({neutral}), and no made-up name"}
NEUTRAL = {"fr": "je viens de Corée, not je suis coréen; je fais des études, not je suis étudiant",
           "es": "soy de Corea, not soy coreano; estudio, not soy estudiante"}
for _p in [w.replace("{neutral}", "\\(neutral)") for w in WHO.values()] + list(NEUTRAL.values()) + [", spelled in full (je suis, never j'suis)",
                                 "In \\(name) an example about themselves agrees with who they are: \\(who). Every word of it is \\(name)\\(spelled)."]:
    if _p not in TL:
        raise SystemExit(f"TutorPlanner.exampleLines changed — update the probe: {_p}")

def example_lines(lang):
    if lang not in ("fr", "es"):
        return ""
    spelled = ", spelled in full (je suis, never j'suis)" if lang == "fr" else ""
    return f"\n  In {NAMES[lang]} an example about themselves agrees with who they are: {WHO[GENDER].replace('{neutral}', NEUTRAL[lang])}. Every word of it is {NAMES[lang]}{spelled}."

def planner_prompt(lang):
    return fill(PLAN, {"target": NAMES[lang], "native": NATIVE[lang],
                       "level.rawValue.uppercased()": LEVEL.upper(), "levelLadder(level)": ladder(LEVEL),
                       "exampleLines": example_lines(lang),
                       "about.isEmpty": ""})

def run_plan(job):
    lang, asked, said, run = job
    msg = f'The tutor asked: "{asked}"\nThey answered: "{said}"' if asked else f'They picked on screen: "{said}"'
    try:
        j = json.loads(gemini("gemini-3.6-flash", planner_prompt(lang), msg))
    except Exception as e:
        return f"### PLAN {lang} {said} ERROR {e}"
    rows = "\n".join(f"    - {c.get('goal')} | {c.get('task')} | e.g. {c.get('example')}" for c in j.get("challenges", []))
    return f"### PLAN {lang} run{run} topic={j.get('topic')} · {said} → {j.get('title')} / {j.get('title_target')}\n{rows}"

# ---------- 2. judge: (line, own_language, expected) — expected is
# "done" (a try that does it), "try" (a try that doesn't), "talk", "help", "other"

def judge_lines(lang):
    return [(TRY[lang][2], False, "done"), (TRY[lang][0], False, "done"),  # slips are not the judge's job
            (FRAGMENT[lang], False, "try"), (TALK[lang], False, "talk"), (HELP[lang], False, "help"),
            (OWN[lang], True, "help"), (OTHER[lang], False, "other")]

def run_judge(job):
    lang, line, own, want = job
    task, ex = LESSON[lang][1][1]
    name = NAMES[lang]
    system = fill(JUDGE_SYSTEM, {"target": name, "realGoal": ""})  # no real goal: the plain judge
    content = fill(JUDGE_CONTENT, {"challenge.task": task, "challenge.example": ex, "askedWith": ASK[lang],
                                   "line": line,
                                   "ownLanguage": f"\n(They said this in their own language, not in {name}.)" if own else ""})
    out = (claude_json(system, content) if JUDGE_MODEL == "haiku"
           else gemini("gemini-3.1-flash-lite", system, content, thinking="minimal", tokens=160))
    try:
        j = json.loads(out)
        got = ("other" if j.get("other_topic") else
               j.get("kind") if j.get("kind") in ("talk", "help") else
               "done" if j.get("done") else "try")
    except Exception:
        got = "?"
    return f"### JUDGE {'OK ' if got == want else 'BAD'} {lang} want={want} got={got} · {line} → {out.strip()}"

if __name__ == "__main__":
    jobs_p = [(l, a, s, r) for l in LANGS for (a, s) in REQ[l] for r in range(RUNS)] if "plan" in PARTS else []
    jobs_j = [(l, line, own, w) for l in LANGS for (line, own, w) in judge_lines(l)
              for _ in range(RUNS)] if "judge" in PARTS else []
    jobs_t = [(l, n, r) for l in LANGS for n in tutor_cases(l) for r in range(1, RUNS + 1)] if "tutor" in PARTS else []

    def run_tutor(job):
        lang, name, run = job
        try:
            # Lesson ready: challenge 1 is NOW; every other case is on challenge 2.
            out = haiku(tutor_system(lang, now=0 if name == "ready" else 1), tutor_cases(lang)[name])
        except Exception as e:
            out = f"ERROR {e}"
        return f"### TUTOR {lang} · {name} · run {run}\n{out}"

    with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "6"))) as ex:
        for out in ex.map(run_plan, jobs_p): print(out, flush=True)
        for out in ex.map(run_judge, jobs_j): print(out, flush=True)
        for out in ex.map(run_tutor, jobs_t): print("\n" + out, flush=True)

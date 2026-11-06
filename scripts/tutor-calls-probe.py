#!/usr/bin/env python3
"""The tutor's three other calls on Gemini and on Haiku, side by side
(2026-11-06): the planner (`TutorPlanner.plan`), the after-lesson read
(`TutorNext.read`) and the final check (`TutorFinalCheck.read`).

Every prompt is LIFTED from TutorLesson.swift, so what is measured is what
ships. Each call is run as the app sends it (model, thinking level, token
ceiling) and as the server would hand it to Claude (same ceiling, the
JSON_ONLY line, thinking per HAIKU_THINKING).

    PARTS=plan,next,check  LANGS=en,ko,ja,de,es  RUNS=3
    MODELS=gemini,haiku  HAIKU_THINKING=off|default  LEVEL=a2
    python3 scripts/tutor-calls-probe.py

Next and check are scored against the expected answer; plan prints every
lesson for reading, with the checks code can do (JSON, topic, 3–4 rows, no
brackets in an example). Every line carries its latency.
"""
import concurrent.futures as cf
import importlib.util
import json
import os
import re
import statistics
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DUMP_DIR", "/nonexistent")
spec = importlib.util.spec_from_file_location("tlp", f"{ROOT}/scripts/tutor-lesson-probe.py")
tlp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tlp)

LANGS = os.environ.get("LANGS", "en,ko,ja,de,es").split(",")
PARTS = os.environ.get("PARTS", "plan,next,check").split(",")
MODELS = os.environ.get("MODELS", "gemini,haiku").split(",")
RUNS = int(os.environ.get("RUNS", "3"))
LEVEL = os.environ.get("LEVEL", "a2")
HAIKU_THINKING = os.environ.get("HAIKU_THINKING", "off")
NAMES = tlp.NAMES

TL = tlp.TL
NEXT_SRC = TL[TL.index("enum TutorNext"):]
NEXT_OFFER = tlp.literal_body(NEXT_SRC, NEXT_SRC.index("let offer = "))
NEXT_SYSTEM = tlp.literal_body(NEXT_SRC, NEXT_SRC.index("let system = "))
CHECK_SRC = TL[TL.index("enum TutorFinalCheck"):]
CHECK_SYSTEM = tlp.literal_body(CHECK_SRC, CHECK_SRC.index("let system = "))
CHECK_CONTENT = tlp.literal_body(CHECK_SRC, CHECK_SRC.index("let content = "))


CLAUDE_MODELS = {"haiku": "claude-haiku-5-5", "sonnet": "claude-sonnet-5-5"}


def haiku(system, user, tokens, model="haiku"):
    # Sonnet 5.5 refuses "disabled"; "between_tools" is its thinking-off.
    off = {"type": "between_tools"} if model == "sonnet" else {"type": "disabled"}
    extra = {"thinking": off} if HAIKU_THINKING == "off" else {}
    j = tlp.post("https://api.anthropic.com/v1/messages", {
        "model": CLAUDE_MODELS[model], "max_tokens": tokens, **extra,
        "system": system + os.environ.get("HAIKU_ADDENDUM", "") + "\n\nAnswer with the JSON object only.",
        "messages": [{"role": "user", "content": user}]},
        {"anthropic-version": "2023-06-01", "x-api-key": tlp.ANTHROPIC})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    a, b = raw.find("{"), raw.rfind("}")
    return raw[a:b + 1] if a >= 0 and b > a else raw


def call(model, gem_model, thinking, tokens, system, user):
    t = time.time()
    try:
        out = (haiku(system, user, tokens, model) if model in CLAUDE_MODELS
               else tlp.gemini(gem_model, system, user, thinking=thinking, tokens=tokens))
    except Exception as e:
        out = f"ERROR {e}"
    return out, time.time() - t


# ---------- 1. planner: TutorPlanner.plan (3.6-flash, low, 2000)

NO_TOPIC = {
 "en": ("Okay, lesson time. What do you want to be able to say today?", "I don't know, anything."),
 "ko": ("좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어?", "음 잘 모르겠어."),
 "ja": ("よし、今日はレッスンね。今日はどんなことが言えるようになりたい？", "うーん、わからない。"),
 "de": ("Okay, heute ist Unterricht. Was willst du heute sagen können?", "Keine Ahnung, egal."),
 "es": ("Bueno, hoy toca clase. ¿Qué quieres poder decir hoy?", "No sé, lo que sea."),
}
MISHEARD = {
 "en": ("Okay, lesson time. What do you want to be able to say today?", "I don't like to practice on introducing myself."),
}


def plan_cases(lang):
    cases = [(a, s, True) for a, s in tlp.REQ[lang]] + [(*NO_TOPIC[lang], False)]
    if lang in MISHEARD:
        cases.append((*MISHEARD[lang], False))
    return cases


def run_plan(job):
    model, lang, asked, said, want, run = job
    system = tlp.planner_prompt(lang)
    msg = f'The tutor asked: "{asked}"\nThey answered: "{said}"' if asked else f'They picked on screen: "{said}"'
    out, dt = call(model, "gemini-3.6-flash", "low", 2000, system, msg)
    try:
        j = json.loads(out)
    except Exception:
        return model, False, dt, f"### PLAN BAD {model} {lang} run{run} {dt:.2f}s · {said} → unparseable {out[:200]!r}"
    rows = j.get("challenges") or []
    ok = bool(j.get("topic")) == want
    if want:
        ok = ok and 3 <= len(rows) <= 4 and all(c.get("example") and "[" not in c["example"] and "___" not in c["example"] for c in rows)
    lines = "\n".join(f"    - {c.get('goal')} | {c.get('task')} | e.g. {c.get('example')}" for c in rows)
    tag = "OK " if ok else "BAD"
    return model, ok, dt, f"### PLAN {tag} {model} {lang} run{run} {dt:.2f}s topic={j.get('topic')} · {said} → {j.get('title')} / {j.get('title_target')}\n{lines}"


# ---------- 2. after the lesson: TutorNext.read (flash-lite, minimal, 120)

ASK_NEXT = {
 "en": "Nice, you nailed it! Want to keep going with this, try another topic, or stop for today?",
 "ko": "좋아, 완벽했어! 이거 더 해볼래, 다른 주제 해볼래, 아니면 오늘은 여기까지 할래?",
 "ja": "いいね、完璧！これをもう少し続ける？別のテーマにする？それとも今日はここまでにする？",
 "de": "Super, das sitzt! Willst du damit weitermachen, ein anderes Thema nehmen oder für heute aufhören?",
 "es": "¡Genial, te salió perfecto! ¿Seguimos con esto, cambiamos de tema o lo dejamos por hoy?",
}
ASK_AGAIN = {
 "en": "Good! There were a couple of small slips. Want to try saying the whole thing once more?",
 "ko": "좋아! 작은 실수가 조금 있었어. 전체를 한 번 더 말해볼래?",
 "ja": "いいね！ちょっとしたミスがあったよ。全部をもう一回言ってみる？",
 "de": "Gut! Da waren ein paar kleine Fehler. Willst du das Ganze noch einmal sagen?",
 "es": "¡Bien! Hubo un par de errores pequeños. ¿Quieres decirlo todo otra vez?",
}
SUGGEST_LINE = {"en": ' Or how about "%s" next?', "ko": ' 아니면 다음은 "%s" 어때?', "ja": ' それとも次は「%s」はどう？',
                "de": ' Oder als Nächstes "%s"?', "es": ' ¿O qué tal "%s" ahora?'}
SUGGESTED = {"en": "Talking about your weekend", "ko": "주말 이야기하기", "ja": "週末の話をする",
             "de": "Über das Wochenende sprechen", "es": "Hablar de tu fin de semana"}
# (asked, line, suggested?, want_choice, want_topic) — want_topic: True = any
# topic, None = none, a string = exactly that one.
NEXT_LINES = {
 "en": [("n", "Let's keep going with this one.", False, "more", None),
        ("n", "Let's do ordering at a restaurant next.", False, "new", True),
        ("n", "Something else, please.", False, "new", None),
        ("n", "I'm done for today, thanks.", False, "stop", None),
        ("n", "That was fun!", False, "unclear", None),
        ("n", "Yes!", False, "unclear", None),
        ("n", "Sure, let's do that one.", True, "new", "s"),
        ("a", "Yeah, okay.", False, "again", None)],
 "ko": [("n", "이거 계속 더 하자.", False, "more", None),
        ("n", "다음엔 식당에서 주문하는 거 하자.", False, "new", True),
        ("n", "다른 거 하자.", False, "new", None),
        ("n", "오늘은 여기까지 할게, 고마워.", False, "stop", None),
        ("n", "재밌었다!", False, "unclear", None),
        ("n", "응!", False, "unclear", None),
        ("n", "좋아, 그거 하자.", True, "new", "s"),
        ("a", "응, 그래.", False, "again", None)],
 "ja": [("n", "これをもっと続けたい。", False, "more", None),
        ("n", "次はレストランで注文するのをやりたい。", False, "new", True),
        ("n", "別のにしよう。", False, "new", None),
        ("n", "今日はここまでにする、ありがとう。", False, "stop", None),
        ("n", "楽しかった！", False, "unclear", None),
        ("n", "うん！", False, "unclear", None),
        ("n", "いいね、それにしよう。", True, "new", "s"),
        ("a", "うん、いいよ。", False, "again", None)],
 "de": [("n", "Lass uns damit weitermachen.", False, "more", None),
        ("n", "Als Nächstes im Restaurant bestellen.", False, "new", True),
        ("n", "Was anderes, bitte.", False, "new", None),
        ("n", "Für heute reicht's, danke.", False, "stop", None),
        ("n", "Das hat Spaß gemacht!", False, "unclear", None),
        ("n", "Ja!", False, "unclear", None),
        ("n", "Klar, lass uns das machen.", True, "new", "s"),
        ("a", "Ja, okay.", False, "again", None)],
 "es": [("n", "Sigamos con esto.", False, "more", None),
        ("n", "Ahora quiero practicar pedir en un restaurante.", False, "new", True),
        ("n", "Otra cosa, por favor.", False, "new", None),
        ("n", "Por hoy ya está, gracias.", False, "stop", None),
        ("n", "¡Qué divertido!", False, "unclear", None),
        ("n", "¡Sí!", False, "unclear", None),
        ("n", "Vale, hagamos ese.", True, "new", "s"),
        ("a", "Sí, vale.", False, "again", None)],
}


def run_next(job):
    model, lang, (asked, line, sug, want, want_topic), run = job
    suggested = SUGGESTED[lang] if sug else None
    offer = tlp.fill(NEXT_OFFER, {"$0": suggested}) if suggested else ""
    system = tlp.fill(NEXT_SYSTEM, {"lesson": tlp.LESSON[lang][0], "offer": offer})
    ask = ASK_NEXT[lang] if asked == "n" else ASK_AGAIN[lang]
    if suggested:
        ask += SUGGEST_LINE[lang] % suggested
    user = f'The tutor asked: "{ask}"\nThey answered: "{line}"'
    out, dt = call(model, "gemini-3.1-flash-lite", "minimal", 120, system, user)
    try:
        j = json.loads(out)
        topic = (j.get("topic") or "").strip()
        ok = j.get("choice") == want and (
            (want_topic is None and not topic) or (want_topic is True and bool(topic)) or
            (want_topic == "s" and topic == suggested) or want != "new")
    except Exception:
        ok = False
    return model, ok, dt, f"### NEXT {'OK ' if ok else 'BAD'} {model} {lang} want={want} {dt:.2f}s · {line} → {out.strip()}"


# ---------- 3. final check: TutorFinalCheck.read (3.6-flash, minimal, 400)

ASK_ALL = {
 "en": "Now say it all in one go: your name, where you're from, your job, and something you like doing.",
 "ko": "이제 한 번에 다 말해 봐: 이름, 어디서 왔는지, 하는 일, 좋아하는 거.",
 "ja": "じゃあ全部まとめて言ってみて。名前、出身、仕事、好きなこと。",
 "de": "Jetzt alles auf einmal: dein Name, woher du kommst, dein Job und was du gern machst.",
 "es": "Ahora dilo todo de una vez: tu nombre, de dónde eres, tu trabajo y algo que te gusta hacer.",
}
# (line, want) — want: dict of fields that must hold.
CHECK_LINES = {
 "en": [("I'm Jun, I'm from Seoul. I work as a teacher at a middle school. I like cooking because it relaxes me.",
         {"attempt": True, "missing": [], "understood": True, "shaky": False}),
        ("I'm Jun and I from Seoul. I working teacher in middle school. I like cook because is relax.",
         {"attempt": True, "missing": [], "understood": True}),
        ("I'm Jun, I'm from Seoul, and I work as a teacher.",
         {"attempt": True, "missing": [3]}),
        ("Can you show me how it goes first?", {"attempt": False, "wants_example": True}),
        ("Wow, this is harder than I thought.", {"attempt": False}),
        ("I'm... uh... Jun... I... I'm from... uh... Seoul... I... work... uh, no... I am... teacher... I like... uh... cook... because...",
         {"attempt": True, "shaky": True})],
 "ko": [("저는 준이에요. 서울에서 왔어요. 중학교에서 선생님으로 일해요. 요리를 좋아해요. 마음이 편해져서요.",
         {"attempt": True, "missing": [], "understood": True, "shaky": False}),
        ("저는 준이에요. 서울에 왔어요. 중학교 선생님 일해요. 요리 좋아해요 편해서요.",
         {"attempt": True, "missing": [], "understood": True}),
        ("저는 준이에요. 서울에서 왔고 선생님이에요.", {"attempt": True, "missing": [3]}),
        ("먼저 어떻게 하는지 보여줄 수 있어?", {"attempt": False, "wants_example": True}),
        ("와, 생각보다 어렵다.", {"attempt": False}),
        ("저는... 어... 준... 저는... 서울... 어... 왔... 아니... 선생님... 어... 요리... 좋아... 그러니까...",
         {"attempt": True, "shaky": True})],
 "ja": [("ジュンです。ソウルから来ました。中学校で先生をしています。料理が好きです。リラックスできるので。",
         {"attempt": True, "missing": [], "understood": True, "shaky": False}),
        ("ジュンです。ソウルに来ました。中学校の先生をします。料理を好きです、リラックスので。",
         {"attempt": True, "missing": [], "understood": True}),
        ("ジュンです。ソウルから来ました。先生をしています。", {"attempt": True, "missing": [3]}),
        ("先にお手本を見せてくれる？", {"attempt": False, "wants_example": True}),
        ("うわ、思ったより難しい。", {"attempt": False}),
        ("えっと…ジュン…です…ソウル…から…えーと…先生…いや…料理…好き…えっと…",
         {"attempt": True, "shaky": True})],
 "de": [("Ich bin Jun und komme aus Seoul. Ich arbeite als Lehrer an einer Mittelschule. Ich koche gern, weil mich das entspannt.",
         {"attempt": True, "missing": [], "understood": True, "shaky": False}),
        ("Ich bin Jun, ich komme von Seoul. Ich arbeite Lehrer in Mittelschule. Ich gern koche, weil es entspannt mich.",
         {"attempt": True, "missing": [], "understood": True}),
        ("Ich bin Jun, ich komme aus Seoul und bin Lehrer.", {"attempt": True, "missing": [3]}),
        ("Kannst du mir erst zeigen, wie das geht?", {"attempt": False, "wants_example": True}),
        ("Boah, das ist schwerer als gedacht.", {"attempt": False}),
        ("Ich bin... äh... Jun... ich... komme... äh... Seoul... ich... arbeite... nein... Lehrer... ich... koche... äh... weil...",
         {"attempt": True, "shaky": True})],
 "es": [("Soy Jun y soy de Seúl. Trabajo de profesor en una secundaria. Me gusta cocinar porque me relaja.",
         {"attempt": True, "missing": [], "understood": True, "shaky": False}),
        ("Soy Jun, yo es de Seúl. Trabajo profesor en secundaria. Me gusta cocinar porque relaja me.",
         {"attempt": True, "missing": [], "understood": True}),
        ("Soy Jun, soy de Seúl y soy profesor.", {"attempt": True, "missing": [3]}),
        ("¿Me puedes mostrar primero cómo se hace?", {"attempt": False, "wants_example": True}),
        ("Uf, esto es más difícil de lo que pensaba.", {"attempt": False}),
        ("Soy... eh... Jun... soy... de... eh... Seúl... trabajo... no... profesor... me gusta... eh... cocinar... porque...",
         {"attempt": True, "shaky": True})],
}
# The parts the check names: the lesson's three rows, the second split so
# that "missing [3]" means the free-time row.
CHECK_PARTS = ["Say your name and where you're from", "Say what you do for work or study",
               "Say one thing you like doing in your free time, with a reason"]


def run_check(job):
    model, lang, (line, want), run = job
    system = tlp.fill(CHECK_SYSTEM, {"target": NAMES[lang], "lesson.titleTarget": tlp.LESSON[lang][0]})
    parts = "\n".join(f"{i + 1}. {p}" for i, p in enumerate(CHECK_PARTS))
    content = tlp.fill(CHECK_CONTENT, {"parts": parts, "askedWith": ASK_ALL[lang], "line": line})
    out, dt = call(model, "gemini-3.6-flash", "minimal", 400, system, content)
    try:
        j = json.loads(out)
        ok = all((sorted(j.get(k) or []) == v) if k == "missing" else (bool(j.get(k)) == v)
                 for k, v in want.items())
    except Exception:
        ok = False
    return model, ok, dt, f"### CHECK {'OK ' if ok else 'BAD'} {model} {lang} {dt:.2f}s want={want} · {line[:60]} → {out.strip()}"


if __name__ == "__main__":
    jobs = []
    for m in MODELS:
        for l in LANGS:
            for r in range(RUNS):
                if "plan" in PARTS:
                    jobs += [(run_plan, (m, l, a, s, w, r)) for a, s, w in plan_cases(l)]
                if "next" in PARTS:
                    jobs += [(run_next, (m, l, c, r)) for c in NEXT_LINES[l]]
                if "check" in PARTS:
                    jobs += [(run_check, (m, l, c, r)) for c in CHECK_LINES[l]]
    tally = {}
    with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "8"))) as ex:
        for (fn, _), (model, ok, dt, text) in zip(jobs, ex.map(lambda j: j[0](j[1]), jobs)):
            print(text, flush=True)
            t = tally.setdefault((fn.__name__, model), [0, 0, []])
            t[0] += ok; t[1] += 1; t[2].append(dt)
    print()
    for (part, model), (ok, n, dts) in sorted(tally.items()):
        print(f"{part:10s} {model:7s} {ok}/{n}  median {statistics.median(dts):.2f}s  max {max(dts):.2f}s")

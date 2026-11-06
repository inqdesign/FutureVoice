#!/usr/bin/env python3
"""The quick quiz's three calls on Gemini 3.6-flash and on Haiku 5.5
(2026-11-06): the writer (`QuickQuizStock.writeBatch`, "quiz-stock:"), the
one-answer check (`check`, "quiz-stock-check:", also the weekly test's
`keepOnlyAnswer`) and the level rating (`rate`, "quiz-rate:", also the
weekly test's `rateMissing`).

Every system prompt is LIFTED from QuickQuizStock.swift. Each call runs as
the app sends it (3.6-flash, thinking low, the app's token ceiling) and as
the server would hand it to Claude (same ceiling, JSON-only line, thinking
per HAIKU_THINKING — the server sends none, so Haiku's default).

The reference is a GOLD reader (Claude Opus 5.5, thinking on) running the
same check prompt on every written question: a question is good when the
gold reader finds exactly one working choice and it is the answer.

    LANGS=en,ko,ja,de,es  RUNS=2  MODELS=gemini,haiku  LEVEL=a2
    PARTS=write,rate  HAIKU_THINKING=default|off
    python3 scripts/quiz-probe.py

Prints every question with each checker's verdict, then a summary:
writer  — valid after code, good by the gold reader
checker — kept, and of those good (precision); good ones it dropped
rate    — agreement with the gold reader (exact, ±1 band, "none")
"""
import concurrent.futures as cf
import importlib.util
import json
import os
import re
import statistics
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DUMP_DIR", "/nonexistent")
spec = importlib.util.spec_from_file_location("tlp", f"{ROOT}/scripts/tutor-lesson-probe.py")
tlp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tlp)

LANGS = os.environ.get("LANGS", "en,ko,ja,de,es").split(",")
MODELS = os.environ.get("MODELS", "gemini,haiku").split(",")
PARTS = os.environ.get("PARTS", "write,rate").split(",")
RUNS = int(os.environ.get("RUNS", "2"))
LEVEL = os.environ.get("LEVEL", "a2")
HAIKU_THINKING = os.environ.get("HAIKU_THINKING", "default")
NAMES = tlp.NAMES
NATIVE = tlp.NATIVE
BLANK = "______"

SRC = tlp.read("FutureVoice/Services/QuickQuizStock.swift")
RATE_SYSTEM = tlp.literal_body(SRC, SRC.index("let system = ", SRC.index("private static func rate(")))
WRITE_SYSTEM = tlp.literal_body(SRC, SRC.index("let system = ", SRC.index("static func writeBatch(")))
CHECK_SYSTEM = tlp.literal_body(SRC, SRC.index("let system = ", SRC.index("private static func check(")))
BATCH = re.search(r"static let batchPerKind = (\d+)", SRC).group(1)


def claude(model, system, user, tokens, thinking):
    extra = ({"thinking": {"type": "disabled"}} if thinking == "off" else
             {"thinking": {"type": "adaptive"}} if thinking == "adaptive" else {})
    j = tlp.post("https://api.anthropic.com/v1/messages", {
        "model": model, "max_tokens": tokens, **extra,
        "system": system + "\n\nAnswer with the JSON object only.",
        "messages": [{"role": "user", "content": user}]},
        {"anthropic-version": "2023-06-01", "x-api-key": tlp.ANTHROPIC})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    a, b = raw.find("{"), raw.rfind("}")
    return raw[a:b + 1] if a >= 0 and b > a else raw


def call(model, system, user, tokens):
    t = time.time()
    try:
        if model == "haiku":
            out = claude("claude-haiku-5-5", system, user, tokens, HAIKU_THINKING)
        elif model == "gold":
            out = claude("claude-opus-5-5", system, user, 16000, "adaptive")
        else:
            out = tlp.gemini("gemini-3.6-flash", system, user, thinking="low", tokens=tokens)
        return json.loads(out), time.time() - t
    except Exception as e:
        return {"error": str(e)[:200]}, time.time() - t


def norm(s):
    return re.sub(r"[^\w\s]", "", s.lower()).strip()


SCRIPT = {"ko": r"[가-힣]", "ja": r"[぀-ヿ一-鿿]"}


def in_target(s, lang):
    pat = SCRIPT.get(lang)
    if pat:
        return re.search(pat, s) is not None
    return re.search(r"[가-힣぀-ヿ一-鿿]", s) is None


OWN = {
 "en": ["keep an eye on", "end up", "figure out"],
 "ko": ["신경 쓰다", "어쩔 수 없다", "시간이 나다"],
 "ja": ["気にする", "仕方がない", "時間がある"],
 "de": ["Bescheid sagen", "sich Mühe geben", "keine Lust haben"],
 "es": ["darse cuenta", "echar de menos", "tener ganas de"],
}


def write_prompt(lang):
    return tlp.fill(WRITE_SYSTEM, {
        "targetName": NAMES[lang], "nativeName": NATIVE[lang], "level": LEVEL.upper(),
        "WeeklyTestEngine.blankMark": BLANK,
        "WordSplitter.spaced": "8–25 characters" if lang == "ja" else "5–12 words",
        "spokenTopics.isEmpty": "", "batchPerKind": BATCH})


def write_user(lang):
    return (f"This learner has no recurring grammar slips on file yet.\n"
            f"Also use grammar points a {LEVEL.upper()} learner of {NAMES[lang]} is working on.\n"
            f"The learner's own expressions (type \"own\"):\n" + "\n".join(f"- {p}" for p in OWN[lang]))


def validated(it, lang):
    sentence = re.sub(r"_{2,}", BLANK, (it.get("sentence") or "").strip())
    answer = (it.get("answer") or "").strip()
    wrong = [w.strip() for w in it.get("wrong") or [] if w.strip()]
    if (sentence.count(BLANK) != 1 or not answer or len(wrong) != 3
            or len({norm(x) for x in [answer] + wrong}) != 4
            or not all(in_target(x, lang) for x in [answer] + wrong)
            or not in_target(sentence.replace(BLANK, answer), lang)):
        return None
    return {"type": it.get("type"), "point": it.get("point", ""), "sentence": sentence,
            "answer": answer, "wrong": wrong}


def check(model, lang, qs):
    system = tlp.fill(CHECK_SYSTEM, {"targetName": NAMES[lang]})
    user = "\n".join(f"{i + 1}. {q['sentence']}\n   choices: {' | '.join(sorted([q['answer']] + q['wrong']))}"
                     for i, q in enumerate(qs))
    j, dt = call(model, system, user, 4000)
    oks = {r.get("n"): [norm(x) for x in r.get("ok", [])] for r in j.get("results", []) if isinstance(r, dict)}
    return [oks.get(i + 1) for i in range(len(qs))], dt, "error" in j


def run_write(job):
    writer, lang, run = job
    j, dt = call(writer, write_prompt(lang), write_user(lang), 6000)
    items = j.get("items") or []
    qs = [q for q in (validated(it, lang) for it in items if isinstance(it, dict)) if q]
    verdicts, times, errors = {}, {}, {}
    for c in [m for m in MODELS] + ["gold"]:
        verdicts[c], times[c], errors[c] = check(c, lang, qs) if qs else ([], 0, False)
    return writer, lang, run, len(items), qs, verdicts, dt, times, errors, j.get("error")


RATE_PHRASES = {
 "en": ["thank you", "how about", "make up your mind", "take it easy", "be on the same page",
        "it goes without saying", "stick around on someone's phone", "I went to the shop yesterday",
        "at the end of the day", "look forward to", "get the hang of", "a blessing in disguise"],
 "ko": ["감사합니다", "어떻게 생각해", "마음을 먹다", "눈치를 보다", "발등에 불이 떨어지다",
        "어제 친구랑 시장에 갔어", "폰에 오래 남아 있는", "시간 가는 줄 모르다", "기대하다",
        "손이 많이 가다", "말할 것도 없다", "그런 셈이다"],
 "ja": ["ありがとう", "どうですか", "気がする", "腹が立つ", "猫の手も借りたい",
        "昨日友達と買い物に行った", "スマホにずっと残ってる", "思わず", "楽しみにする",
        "手間がかかる", "言うまでもない", "仕方がない"],
 "de": ["danke schön", "wie wäre es mit", "sich Mühe geben", "Bescheid sagen", "auf dem Schlauch stehen",
        "Ich war gestern im Supermarkt", "lange auf dem Handy bleiben", "es kommt darauf an", "sich freuen auf",
        "unter vier Augen", "das versteht sich von selbst", "keine Lust haben"],
 "es": ["muchas gracias", "qué tal si", "darse cuenta", "echar de menos", "estar en las nubes",
        "Ayer fui al mercado con mi amiga", "quedarse mucho en el móvil", "a fin de cuentas", "tener ganas de",
        "meter la pata", "ni que decir tiene", "dar igual"],
}
BANDS = ["a1", "a2", "b1", "b2", "c1", "c2"]


def run_rate(job):
    lang, run = job
    system = tlp.fill(RATE_SYSTEM, {"targetName": NAMES[lang]})
    user = "\n".join(f"{i + 1}. {p}" for i, p in enumerate(RATE_PHRASES[lang]))
    out = {}
    for m in MODELS + ["gold"]:
        j, dt = call(m, system, user, 1500)
        out[m] = ({r.get("n"): (r.get("level") or "").lower() for r in j.get("results", []) if isinstance(r, dict)}, dt)
    return lang, run, out


if __name__ == "__main__":
    tally = {}
    lines = []
    with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "6"))) as ex:
        if "write" in PARTS:
            jobs = [(w, l, r) for w in MODELS for l in LANGS for r in range(RUNS)]
            for writer, lang, run, n_items, qs, verdicts, dt, times, errors, err in ex.map(run_write, jobs):
                print(f"\n### WRITE {writer} {lang} run{run} {dt:.1f}s items={n_items} valid={len(qs)}"
                      + (f" ERROR {err}" if err else ""), flush=True)
                gold = verdicts["gold"]
                w = tally.setdefault(("writer", writer), [0, 0, 0, []]); w[0] += n_items; w[1] += len(qs); w[3].append(dt)
                for i, q in enumerate(qs):
                    a = norm(q["answer"])
                    good = gold[i] == [a] if i < len(gold) else False
                    w[2] += good
                    marks = []
                    for c in MODELS:
                        v = verdicts[c][i] if i < len(verdicts[c]) else None
                        kept = v == [a]
                        t = tally.setdefault(("checker", c), [0, 0, 0, 0, []])
                        t[0] += kept; t[1] += kept and good; t[2] += good and not kept; t[3] += 1
                        marks.append(f"{c}={'keep' if kept else 'drop'}")
                    print(f"  {'GOOD' if good else 'BAD '} [{q['type']}] {q['sentence']}  answer={q['answer']} "
                          f"wrong={q['wrong']} point={q['point']!r} gold_ok={gold[i] if i < len(gold) else None} "
                          + " ".join(marks), flush=True)
                for c in MODELS:
                    tally.setdefault(("checker", c), [0, 0, 0, 0, []])[4].append(times[c])
                    if errors[c]:
                        print(f"  CHECK ERROR {c}", flush=True)
        if "rate" in PARTS:
            for lang, run, out in ex.map(run_rate, [(l, r) for l in LANGS for r in range(RUNS)]):
                gold = out["gold"][0]
                print(f"\n### RATE {lang} run{run}", flush=True)
                for i, p in enumerate(RATE_PHRASES[lang]):
                    row = " ".join(f"{m}={out[m][0].get(i + 1)}" for m in MODELS)
                    print(f"  {p}: gold={gold.get(i + 1)} {row}", flush=True)
                for m in MODELS:
                    r = tally.setdefault(("rate", m), [0, 0, 0, 0, []]); r[4].append(out[m][1])
                    for i in range(len(RATE_PHRASES[lang])):
                        g, v = gold.get(i + 1), out[m][0].get(i + 1)
                        r[3] += 1
                        r[0] += v == g
                        r[2] += (v == "none") == (g == "none")
                        r[1] += (v == g) or (v in BANDS and g in BANDS and abs(BANDS.index(v) - BANDS.index(g)) <= 1)
    print("\n==== SUMMARY")
    for (part, m), t in sorted(tally.items()):
        if part == "writer":
            print(f"writer  {m:7s} written {t[0]}  valid {t[1]}  good by gold {t[2]}/{t[1]}  median {statistics.median(t[3]):.1f}s")
        elif part == "checker":
            print(f"checker {m:7s} kept {t[0]}/{t[3]}  of those good {t[1]}/{t[0]}  good dropped {t[2]}  median {statistics.median(t[4] or [0]):.1f}s")
        else:
            print(f"rate    {m:7s} exact {t[0]}/{t[3]}  within one {t[1]}/{t[3]}  none agrees {t[2]}/{t[3]}  median {statistics.median(t[4]):.1f}s")

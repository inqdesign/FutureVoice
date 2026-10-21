#!/usr/bin/env python3
# The coach's "try saying" line (CoachSuggester) on 3.6-flash vs Claude Haiku
# (2026-10-21), before the gemini edge function routes purpose "coach" to
# Haiku. Runs the LIVE prompt (CoachPromptDumpTests dump), the app's content
# format and settings, and reads every answer twice: code checks (valid JSON,
# the target script, length, bracketed examples, "please" on a statement) and
# a blind pairwise judge (Claude Sonnet) that is told the prompt's rules.
#
#   TEST_RUNNER_PROMPT_DUMP_DIR=/tmp/fv-prompt-dump xcodebuild test … \
#     -only-testing:FutureVoiceTests/CoachPromptDumpTests      # once
#   scripts/coach-probe.py                     # flash vs haiku, A2+B1, 2 runs
#   HAIKU_EFFORT=low LEVELS=a1,a2 RUNS=3 scripts/coach-probe.py
#
# Keys: GEMINI_API_KEY from gateway/.dev.vars, Anthropic from ~/keys/anthropic.txt.
import json, os, random, re, sys, time, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.environ.get("DUMP_DIR", "/tmp/fv-prompt-dump")
OUT = os.environ.get("OUT_DIR", "/tmp")
LEVELS = os.environ.get("LEVELS", "a2,b1").split(",")
LANGS = os.environ.get("LANGS", "en,ko,ja,de,es").split(",")
RUNS = int(os.environ.get("RUNS", "2"))
HAIKU = os.environ.get("HAIKU_MODEL", "claude-haiku-5-5")
HAIKU_EFFORT = os.environ.get("HAIKU_EFFORT", "")
JUDGE = os.environ.get("JUDGE_MODEL", "claude-sonnet-5-5")
GKEY = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
AKEY = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
# What the edge function appends for a JSON purpose on Claude.
JSON_ONLY = "\n\nAnswer with the JSON object only."

# (line the other speaker says, situation or None, learner's previous line or None, studied items)
CASES = {
 "en": [("So what did you get up to this weekend?", None, None, []),
        ("Hi! What can I get for you today?", "a café, ordering a drink", None, []),
        ("Where are you from, originally?", None, "I'm doing okay, a bit tired.", []),
        ("Do you have any plans for tonight?", None, None, ["exhausted"]),
        ("How long have you been learning English?", None, None, []),
        ("Oh nice. What kind of music are you into?", None, "I went to a concert yesterday.", []),
        ("Would you like anything else with that?", "a bakery, buying bread", None, []),
        ("That sounds stressful. How's work been lately?", None, None, ["deadline", "launch"])],
 "ko": [("주말에 뭐 했어?", None, None, []),
        ("안녕하세요! 뭐 드릴까요?", "카페에서 음료 주문", None, []),
        ("어디 출신이야?", None, "그냥 좀 피곤해.", []),
        ("오늘 저녁에 뭐 할 거야?", None, None, ["피곤하다"]),
        ("한국어 공부한 지 얼마나 됐어?", None, None, []),
        ("오, 좋다. 무슨 음악 좋아해?", None, "어제 콘서트 갔어.", []),
        ("더 필요하신 거 있으세요?", "빵집에서 빵 사기", None, []),
        ("요즘 일은 어때?", None, None, ["마감", "출시"])],
 "ja": [("週末は何してた？", None, None, []),
        ("いらっしゃいませ！ご注文はお決まりですか？", "カフェで飲み物を注文", None, []),
        ("出身はどこ？", None, "ちょっと疲れてる。", []),
        ("今夜は何か予定ある？", None, None, ["疲れる"]),
        ("日本語を勉強してどのくらい？", None, None, []),
        ("へえ、いいね。どんな音楽が好き？", None, "昨日ライブに行った。", []),
        ("ほかにご注文はございますか？", "パン屋でパンを買う", None, []),
        ("最近、仕事はどう？", None, None, ["締め切り"])],
 "de": [("Und, was hast du am Wochenende gemacht?", None, None, []),
        ("Hallo! Was darf's sein?", "ein Café, Getränk bestellen", None, []),
        ("Woher kommst du eigentlich?", None, "Mir geht's ganz gut, bin nur müde.", []),
        ("Hast du heute Abend schon was vor?", None, None, ["erschöpft"]),
        ("Wie lange lernst du schon Deutsch?", None, None, []),
        ("Cool. Was für Musik hörst du so?", None, "Ich war gestern auf einem Konzert.", []),
        ("Darf es sonst noch etwas sein?", "eine Bäckerei, Brot kaufen", None, []),
        ("Klingt stressig. Wie läuft's gerade bei der Arbeit?", None, None, ["Frist"])],
 "es": [("¿Y qué hiciste el fin de semana?", None, None, []),
        ("¡Hola! ¿Qué te pongo?", "una cafetería, pedir algo de beber", None, []),
        ("¿De dónde eres?", None, "Estoy bien, un poco cansado.", []),
        ("¿Tienes planes para esta noche?", None, None, ["agotado"]),
        ("¿Cuánto tiempo llevas aprendiendo español?", None, None, []),
        ("Qué bien. ¿Qué música te gusta?", None, "Ayer fui a un concierto.", []),
        ("¿Algo más?", "una panadería, comprar pan", None, []),
        ("Suena estresante. ¿Qué tal el trabajo últimamente?", None, None, ["plazo"])],
}

def content(line, situation, earlier, items):
    c = ""
    if situation: c += f"Situation: {situation}\n"
    if earlier: c += f'The learner said: "{earlier}"\n'
    c += f'Now the other speaker says: "{line}"'
    if items: c += "\n\nStudied items:\n" + "\n".join(f"- {i}" for i in items)
    return c

def post(url, body, headers):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"content-type": "application/json", **headers})
    err = None
    for attempt in range(4):
        try:
            return json.load(urllib.request.urlopen(req, timeout=60))
        except Exception as e:
            err = e
            time.sleep(2 * (attempt + 1))
    raise err

def flash(system, user):
    t0 = time.time()
    j = post(f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={GKEY}", {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {"maxOutputTokens": 1000, "thinkingConfig": {"thinkingLevel": "minimal"},
                             "responseMimeType": "application/json"}}, {})
    text = "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"] if not p.get("thought"))
    return text, time.time() - t0

def haiku(system, user):
    t0 = time.time()
    body = {"model": HAIKU, "max_tokens": 1000, "system": system + JSON_ONLY,
            "messages": [{"role": "user", "content": user}]}
    if HAIKU_EFFORT: body["output_config"] = {"effort": HAIKU_EFFORT}
    j = post("https://api.anthropic.com/v1/messages", body, {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(b.get("text", "") for b in j["content"] if b.get("type") == "text")
    a, b = raw.find("{"), raw.rfind("}")
    return (raw[a:b + 1] if a >= 0 and b > a else raw), time.time() - t0

SCRIPT = {"ko": r"[가-힣]", "ja": r"[ぁ-んァ-ン一-龯]"}
def checks(lang, text):
    try:
        d = json.loads(text)
    except Exception:
        return None, ["bad-json"]
    say = (d.get("say") or "").strip()
    flags = []
    if not say: flags.append("empty")
    if lang in SCRIPT and not re.search(SCRIPT[lang], say): flags.append("wrong-script")
    if lang not in SCRIPT and re.search(r"[가-힣ぁ-ん一-龯]", say): flags.append("wrong-script")
    words = len(say.split()) if lang not in SCRIPT else len(re.sub(r"\s|\[.*?\]", "", say)) / 3
    if words > 12: flags.append("long")
    if len(re.findall(r"\[", say)) > 2: flags.append("brackets")
    if lang == "en" and re.search(r"\bplease\b", say, re.I) and not re.search(r"\?|can i|could i|i'd like|i'll have", say, re.I):
        flags.append("please")
    return d, flags

JUDGE_PROMPT = """You are checking suggestions shown to a language learner during a spoken call. The learner ({level}, learning {language}) sees ONE suggested reply to say next. The rules the suggestion must follow:
- exactly what a native speaker would actually say out loud in that moment, kept easy for the level; never a stiff textbook sentence
- in {language} only; 3–10 words; one idea
- where the answer depends on the learner's own facts, a plausible example in [square brackets] (one or two)
- the same form of address the other speaker uses (casual vs polite), one form for the call; no honorifics on the learner's own actions
- "please" only on a request; asking the question straight back only now and then
- if studied items are listed, use one only if it fits naturally ("word" names it), else word is null

The situation:
{content}

Suggestion A: {a}
Suggestion B: {b}

Which suggestion is better for the learner? Judge naturalness first, then the rules. Return JSON only:
{{"better": "A" | "B" | "tie", "problems_A": "short, or empty", "problems_B": "short, or empty"}}"""

LANG_NAME = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}

def judge(lang, level, user, a, b):
    j = post("https://api.anthropic.com/v1/messages", {
        "model": JUDGE, "max_tokens": 600, "output_config": {"effort": "low"},
        "messages": [{"role": "user", "content": JUDGE_PROMPT.format(
            level=level.upper(), language=LANG_NAME[lang], content=user, a=a, b=b)}]},
        {"x-api-key": AKEY, "anthropic-version": "2023-06-01"})
    raw = "".join(x.get("text", "") for x in j["content"] if x.get("type") == "text")
    try:
        return json.loads(raw[raw.find("{"):raw.rfind("}") + 1])
    except Exception:
        return {"better": "?", "problems_A": raw[:120], "problems_B": ""}

jobs = []
for level in LEVELS:
    for lang in LANGS:
        system = open(os.path.join(DUMP, f"coach-{lang}-{level}.txt")).read()
        for i, case in enumerate(CASES[lang]):
            for run in range(RUNS):
                jobs.append((level, lang, i, run, system, content(*case)))

def run(job):
    level, lang, i, run_i, system, user = job
    try:
        ft, fs = flash(system, user)
    except Exception as e:
        ft, fs = f"<error {e}>", 0
    try:
        ht, hs = haiku(system, user)
    except Exception as e:
        ht, hs = f"<error {e}>", 0
    fd, ff = checks(lang, ft)
    hd, hf = checks(lang, ht)
    verdict = None
    if fd and hd and fd.get("say") and hd.get("say"):
        swap = random.random() < 0.5
        a, b = (hd, fd) if swap else (fd, hd)
        v = judge(lang, level, user, json.dumps(a, ensure_ascii=False), json.dumps(b, ensure_ascii=False))
        better = {"A": "haiku" if swap else "flash", "B": "flash" if swap else "haiku"}.get(v.get("better"), v.get("better"))
        verdict = {"better": better,
                   "flash_problems": v.get("problems_B" if swap else "problems_A", ""),
                   "haiku_problems": v.get("problems_A" if swap else "problems_B", "")}
    return {"level": level, "lang": lang, "case": i, "run": run_i, "content": user,
            "flash": ft, "flash_s": fs, "flash_flags": ff, "haiku": ht, "haiku_s": hs, "haiku_flags": hf,
            "verdict": verdict}

with cf.ThreadPoolExecutor(int(os.environ.get("PAR", "6"))) as pool:
    results = list(pool.map(run, jobs))

def med(xs):
    xs = sorted(x for x in xs if x)
    return xs[len(xs) // 2] if xs else 0
print(f"haiku={HAIKU} effort={HAIKU_EFFORT or 'default'}  {len(results)} cases")
for model in ("flash", "haiku"):
    flags = {}
    for r in results:
        for f in r[f"{model}_flags"]: flags[f] = flags.get(f, 0) + 1
    print(f"  {model:6} median {med([r[model + '_s'] for r in results]):.2f}s  "
          f"p90 {sorted(r[model + '_s'] for r in results)[int(len(results) * 0.9)]:.2f}s  flags {flags or '-'}")
for lang in LANGS:
    vs = [r["verdict"]["better"] for r in results if r["lang"] == lang and r["verdict"]]
    print(f"  {lang}: haiku better {vs.count('haiku')} · flash better {vs.count('flash')} · tie {vs.count('tie')}")
vs = [r["verdict"]["better"] for r in results if r["verdict"]]
print(f"  ALL: haiku better {vs.count('haiku')} · flash better {vs.count('flash')} · tie {vs.count('tie')}")
print("\n--- every case flash won, and every flagged answer (read them) ---")
for r in results:
    v = r["verdict"] or {}
    if v.get("better") == "flash" or r["haiku_flags"] or r["flash_flags"]:
        say = lambda t: (json.loads(t).get("say") if t.startswith("{") else t)[:90] if t else t
        try: fs, hs = say(r["flash"]), say(r["haiku"])
        except Exception: fs, hs = r["flash"][:90], r["haiku"][:90]
        print(f"[{r['level']} {r['lang']} {r['case']}] {v.get('better')}  flash{r['flash_flags']}: {fs}\n"
              f"      haiku{r['haiku_flags']}: {hs}\n      why: {v.get('haiku_problems', '')}")
out = os.path.join(OUT, "coach-probe.out.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("→", out)

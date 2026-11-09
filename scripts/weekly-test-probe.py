#!/usr/bin/env python3
"""The weekly test's translate items and second read, measured (2026-11-08).

Two questions, each answered by a reader that took no part in writing:

  items  -- do the items test the learner's mistake, and are the traps really
            wrong? Runs the OLD prompt, the NEW prompt, and the NEW prompt
            through `verifyTranslate`'s gate. A GOLD reader (Claude Opus 5.5,
            thinking on) reads every item. An item is good when the mistake
            comes from a rule, the new sentence lets it happen again, the
            answer means what the native line says, no trap can build a right
            sentence, and the tip is true.
  second -- given a laid sentence the code did not accept, does the second
            read (`laidStands`) tell a right sentence from the same mistake?

Keep NEW/GATE/SECOND in step with WeeklyTestEngine.swift.

    python3 scripts/weekly-test-probe.py items  [runs] [langs]
    python3 scripts/weekly-test-probe.py second [runs]
    python3 scripts/weekly-test-probe.py meaning [runs]
    GEMINI_GATE=gemini-3.6-flash  SECOND_MODEL=gemini-3.6-flash
"""
import concurrent.futures as cf
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEMINI = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)["GEMINI_API_KEY"].strip().strip('"')
ANTHROPIC = open(os.path.expanduser("~/keys/anthropic.txt")).read().strip()
NAMES = {"en": "English", "ko": "Korean", "de": "German", "ja": "Japanese", "es": "Spanish"}
MAX = 6  # WeeklyTestEngine.translateDrafts

# (said, fixed, why). The first English ones are from real calls; the cut-off
# line is the one a learner was shown on 2026-11-08.
SLIPS = {
    "en": [
        ("Hi, thanks for inviting me. I'm very excited about. Thank you for giving me this chance", "Hi, thanks for inviting me. I'm very excited. Thank you for giving me this chance.", "about 뒤에 대상이 없어요"),
        ("we finish only at midnight", "we only finished at midnight", "지난 일은 과거형"),
        ("I am working in a startup since three years", "I've been working at a startup for three years", "지금까지 이어지는 일은 현재완료 + for"),
        ("I take also some product decisions", "I also make some product decisions", "also 위치, make a decision"),
        ("explain him the situation", "explain the situation to him", "explain A to B"),
        ("whoever who limit the AI", "whoever limits AI's", "whoever 뒤 동사"),
        ("I went to the the uh store", "I went to the store", "더듬음"),
        ("she don't like coffee", "she doesn't like coffee", "3인칭 단수"),
    ],
    "de": [
        ("Seit drei Jahre wohne ich in Berlin", "Seit drei Jahren wohne ich in Berlin", "seit + Dativ"),
        ("Ich habe gestern nach Hause gegangen", "Ich bin gestern nach Hause gegangen", "gehen은 sein과 함께"),
        ("weil ich habe keine Zeit", "weil ich keine Zeit habe", "weil 뒤 동사는 끝으로"),
        ("Ich fahre mit der Zug", "Ich fahre mit dem Zug", "mit + Dativ"),
    ],
    "ja": [
        ("友達に会いました昨日のカフェで", "昨日カフェで友達に会いました", "語順"),
        ("日本語が勉強しています", "日本語を勉強しています", "勉強する는 を"),
        ("東京に住んでいます三年", "東京に三年住んでいます", "기간의 위치"),
        ("映画を見るのが好きじゃないです、あの", "映画を見るのは好きじゃないです", "否定의 は"),
    ],
    "es": [
        ("Yo soy cansado hoy", "Estoy cansado hoy", "상태는 estar"),
        ("Ayer yo voy al cine", "Ayer fui al cine", "지난 일은 pretérito"),
        ("A mí gusta el café", "Me gusta el café", "gusta 앞의 me"),
        ("Hace tres años que vivo a Madrid", "Hace tres años que vivo en Madrid", "vivir en"),
    ],
    "ko": [
        ("저는 학교 갔어요 어제 친구랑", "어제 친구랑 학교에 갔어요", "조사 에"),
        ("친구을 만났어요", "친구를 만났어요", "받침 없으면 를"),
        ("밥이 먹고 싶어요", "밥을 먹고 싶어요", "먹다는 을"),
        ("어제 영화 봐요", "어제 영화 봤어요", "지난 일은 과거형"),
    ],
}
TOPICS = ["Moving to a new flat", "Work at a small startup"]


NOT_A_RULE = {
    "Korean": " In Korean, a particle left out in speech and 이/가 on the object of -고 싶다 are normal, not mistakes.",
    "Japanese": " In Japanese, choosing は or が before a negative is nuance, and a particle left out in casual speech is normal: neither is a mistake.",
}


def old_prompt(t, n, level):
    return f"""You write a short translation quiz for a {t} learner whose own language is {n}, level {level}. They answer by laying word tiles in order. You get mistakes they really made. Pick up to 3 of them, each a DIFFERENT grammar point (skip pure word choice or a slip with no rule behind it), and for each write ONE new everyday sentence that cannot be said right without that grammar point.

Return {{"items":[{{"source":n,"point":"...","native":"...","answer":"...","orders":["..."],"decoys":["..."],"tip":"..."}}]}}
- source: the number of the mistake it is built on.
- native: the sentence in {n}, casual and spoken, the way they'd say it to a friend, 6–12 words, about ordinary life (these were their topics: {"; ".join(TOPICS)}). NOT their original sentence.
- answer: the most natural {t} way to say it, at their level, 5–12 words. Its words are the tiles, so there must be ONE wording: no optional words, nothing a learner could naturally say differently with other words. It means EXACTLY what native says: every idea in one is in the other ("finally" is not "only", "my situation" is not "the situation"). Write native from the answer if that is easier.
- orders: every OTHER order of exactly the same words that is just as correct. Go through each time, place and duration phrase ("for two years", "yesterday", "at midnight") and each adverb, and list the sentence with it at the front too wherever that is natural — a learner who lays a right order and is marked wrong stops trusting the test. [] only if the order is truly fixed.
- decoys: 2–3 single words built from their mistake (e.g. "since", "am" for "I am working here since 2020") that make the sentence WRONG wherever they go, and are not in answer.
- point: the grammar point in {n}, 2–5 words. tip: one line in {n}, at most 14 words, that a teacher would sign: TRUE, and showing the pattern as the answer uses it (e.g. "explain + what + to + whom"). Never a rule you are unsure of. Write it in the polite everyday register an app speaks in (Korean 해요체, never 합니다체; Japanese です・ます).
JSON only."""


def new_prompt(t, n, level):
    return f"""You write a short translation quiz for a {t} learner whose own language is {n}, level {level}. They answer by laying word tiles in order. You get mistakes they really made.

First decide which mistakes can be asked about at all. One qualifies only when a grammar RULE of {t} was broken and the same rule could be broken again in a different sentence. Leave out word choice, a sentence the speaker broke off or restarted, words lost to hesitation, and anything a speech recognizer could have caused.{NOT_A_RULE.get(t, "")}

Pick up to {MAX} that qualify, each a DIFFERENT grammar point, and for each write ONE new everyday sentence in which a learner who still has that habit would make THE SAME mistake again.

Return {{"items":[{{"source":n,"point":"...","answer":"...","native":"...","wrong":"...","orders":["..."],"decoys":["..."],"tip":"..."}}]}}, keys in that order.
- source: the number of the mistake it is built on.
- answer: the {t} sentence, the most natural way to say it, at their level, 5–12 words, about ordinary life (these were their topics: {"; ".join(TOPICS)}), correctly punctuated. NOT their original sentence. Its words are the tiles, so there must be ONE wording: no optional words, nothing a learner could naturally say differently with other words.
- native: that sentence in {n}, casual and spoken, the way they'd say it to a friend. Translate the answer and add nothing: no idea in native that is missing from answer, none in answer that is missing from native, the same tense and time.
- wrong: the answer with THAT mistake made again and nothing else changed. If you cannot write it, this sentence does not test the mistake: write another.
- orders: every OTHER order of exactly the same words that is just as correct. Go through each time, place and duration phrase and each adverb, and list the sentence with it at the front too wherever that is natural. [] only if the order is truly fixed.
- decoys: 1–3 single words from wrong that are not in answer. Before keeping one, try to build a correct sentence of the same meaning with it, in any position, using the other words: if you can, it is not a decoy.
- point: the grammar point in {n}, 2–5 words. tip: one line in {n}, at most 14 words, that a teacher would sign: TRUE for THIS sentence, showing the pattern as the answer uses it. Never a rule you are unsure of. Write it in the polite everyday register an app speaks in (Korean 해요체, never 합니다체; Japanese です・ます).
JSON only."""


SOLVE = lambda t, n: f"""A learner sees a sentence in {n} and word tiles in {t}. Not every tile has to be used, and each can be used only as many times as it appears. For each numbered item, list EVERY sentence that can be built from the tiles and is correct, natural {t} saying what the {n} sentence says. Try each tile: casual everyday speech counts, and a different word order or construction counts. List nothing that is wrong.

Return {{"results":[{{"n":1,"sentences":["..."]}}]}}. JSON only."""

REVIEW = lambda t, n: f"""You review translation quiz items for {t} learners whose own language is {n}, built on a mistake the learner really made. You did not write them. Be strict.

For each numbered item decide:
- rule: was the earlier mistake a broken grammar rule of {t}? false when the earlier wording is also acceptable (casual speech, an optional particle, a matter of nuance or preference), and for word choice, a sentence the speaker broke off, hesitation, or a recognizer's error.{NOT_A_RULE.get(t, "")}
- repeats: could a learner with that same habit make the SAME mistake in this new sentence?
- same_meaning: does the answer say exactly what the {n} sentence says, nothing left out or added, the same tense?
- correct: is the answer correct, natural {t}, in every word form?
- tip_true: is the tip true as written, for this sentence and in general? true when there is no tip.

Return {{"results":[{{"n":1,"rule":true,"repeats":true,"same_meaning":true,"correct":true,"tip_true":true}}]}}. JSON only."""

GOLD = lambda t, n: f"""You are an experienced {t} teacher reviewing a quiz for learners whose own language is {n}. The learner sees the {n} sentence and lays word tiles in {t}; some tiles are traps. Judge each item strictly on its own.

For each numbered item decide:
- rule: was the earlier mistake a broken grammar rule of {t}? false for word choice, a sentence simply broken off, hesitation, or a recognizer's error.
- repeats: could a learner with that same habit make the SAME mistake in this new sentence?
- same_meaning: does the answer say exactly what the {n} sentence says?
- correct: is the answer correct and natural?
- tip_true: is the tip true of this sentence?
- working_traps: every trap tile with which some correct, natural sentence of the same meaning can be built from the tiles.

Return {{"results":[{{"n":1,"rule":true,"repeats":true,"same_meaning":true,"correct":true,"tip_true":true,"working_traps":[],"why":"one clause when anything is false"}}]}}. JSON only."""

SECOND = lambda name: f"""A learner laid word tiles to say a {name} sentence, and it is not the model answer. Decide whether what they laid is ALSO a right answer: correct, natural {name} that says what the sentence asks, something a careful teacher would accept. Another wording or order is fine. The quiz tests one grammar point, given below with the learner's earlier mistake: a sentence that makes that same mistake again is NOT right, even if a listener would understand it.
Return {{"right": true}} or {{"right": false}}. JSON only."""

# (native, answer, point, was, now, laid, expected right)
SECOND_CASES = [
    ("다음 주에 면접이 있어서 정말 너무 설레요.", "I am really excited because I have an interview next week.", "excited 전치사 유무", "I'm very excited about.", "I'm very excited.", "I am really excited about an interview next week.", True),
    ("다음 주에 면접이 있어서 정말 너무 설레요.", "I am really excited because I have an interview next week.", "excited 전치사 유무", "I'm very excited about.", "I'm very excited.", "I am really excited for an interview next week.", True),
    ("나 이 스타트업에서 2년째 일하고 있어.", "I've been working at this startup for two years.", "현재완료 진행형 + for", "I am working in a startup since three years", "I've been working at a startup for three years", "I am working at this startup for two years.", False),
    ("나 이 스타트업에서 2년째 일하고 있어.", "I've been working at this startup for two years.", "현재완료 진행형 + for", "I am working in a startup since three years", "I've been working at a startup for three years", "For two years I've been working at this startup.", True),
    ("나 이 스타트업에서 2년째 일하고 있어.", "I've been working at this startup for two years.", "현재완료 진행형 + for", "I am working in a startup since three years", "I've been working at a startup for three years", "I've been working at this startup since two years.", False),
    ("집주인한테 상황을 설명했어.", "I explained the situation to the landlord.", "explain A to B", "explain him the situation", "explain the situation to him", "I explained the landlord the situation.", False),
    ("집주인한테 상황을 설명했어.", "I explained the situation to the landlord.", "explain A to B", "explain him the situation", "explain the situation to him", "I explained to the landlord the situation.", False),
    ("어제 자정이 돼서야 겨우 끝났어.", "We only finished at midnight yesterday.", "지난 일은 과거형", "we finish only at midnight", "we only finished at midnight", "We finish only at midnight yesterday.", False),
    ("어제 자정이 돼서야 겨우 끝났어.", "We only finished at midnight yesterday.", "지난 일은 과거형", "we finish only at midnight", "we only finished at midnight", "Yesterday we only finished at midnight.", True),
    ("걔는 커피 안 좋아해.", "She doesn't like coffee.", "3인칭 단수", "she don't like coffee", "she doesn't like coffee", "She don't like coffee.", False),
    ("걔는 커피 안 좋아해.", "She doesn't like coffee.", "3인칭 단수", "she don't like coffee", "she doesn't like coffee", "Coffee she doesn't like.", True),
    ("3년째 베를린에 살아.", "Ich wohne seit drei Jahren in Berlin.", "seit + Dativ", "Seit drei Jahre wohne ich in Berlin", "Seit drei Jahren wohne ich in Berlin", "Seit drei Jahren wohne ich in Berlin.", True),
    ("3년째 베를린에 살아.", "Ich wohne seit drei Jahren in Berlin.", "seit + Dativ", "Seit drei Jahre wohne ich in Berlin", "Seit drei Jahren wohne ich in Berlin", "Ich wohne seit drei Jahre in Berlin.", False),
    ("어제 집에 갔어.", "Ich bin gestern nach Hause gegangen.", "gehen은 sein", "Ich habe gestern nach Hause gegangen", "Ich bin gestern nach Hause gegangen", "Ich habe gestern nach Hause gegangen.", False),
    ("어제 집에 갔어.", "Ich bin gestern nach Hause gegangen.", "gehen은 sein", "Ich habe gestern nach Hause gegangen", "Ich bin gestern nach Hause gegangen", "Gestern bin ich nach Hause gegangen.", True),
    ("오늘 피곤해.", "Hoy estoy cansado.", "상태는 estar", "Yo soy cansado hoy", "Estoy cansado hoy", "Estoy cansado hoy.", True),
    ("오늘 피곤해.", "Hoy estoy cansado.", "상태는 estar", "Yo soy cansado hoy", "Estoy cansado hoy", "Hoy soy cansado.", False),
    ("일본어를 공부하고 있어.", "日本語を勉強しています", "勉強する는 を", "日本語が勉強しています", "日本語を勉強しています", "日本語が勉強しています", False),
]


# (gloss, words, answer, whether only the answer fits)
MEANING_CASES = [
    ("집안일", ["chore", "errand", "hobby", "shift"], "chore", True),
    ("기쁜, 행복한", ["glad", "happy", "tired", "angry"], "glad", False),
    ("큰", ["big", "large", "thin", "soft"], "big", False),
    ("일을 미루다", ["postpone", "delay", "swallow", "borrow"], "postpone", False),
    ("빌리다", ["borrow", "lend", "throw", "carry"], "borrow", True),
    ("조용한", ["quiet", "bitter", "narrow", "brave"], "quiet", True),
    ("시작하다", ["start", "begin", "finish", "wash"], "start", False),
    ("피곤한", ["tired", "hungry", "cheap", "lazy"], "tired", True),
]
MEANING = """You check vocabulary questions for English learners whose own language is Korean. Each numbered question has a meaning in Korean and four English words. List EVERY word the meaning correctly describes, in any common sense of the word. Judge each word on its own; more than one may fit.
Return {"results":[{"n":1,"fit":["word", ...]}]}. JSON only."""


def run_meaning(runs):
    user = "\n".join(f'{i+1}. {g}\n   words: {" | ".join(sorted(w))}' for i, (g, w, _, _) in enumerate(MEANING_CASES))
    hit = n = 0
    for _ in range(runs):
        res = {r["n"]: r["fit"] for r in gemini("gemini-3.6-flash", MEANING, user)["results"]}
        for i, (g, w, a, only) in enumerate(MEANING_CASES):
            kept = [x.lower() for x in res.get(i + 1, [])] == [a]
            n += 1
            hit += kept == only
            if kept != only:
                print("MISS", g, res.get(i + 1))
    print(f"meaning check: {hit}/{n}")


def post(url, body, headers):
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json", **headers})
            return json.load(urllib.request.urlopen(req, timeout=150))
        except Exception:
            if attempt == 2:
                raise


def gemini(model, system, user, level="low", max_tokens=4000):
    if os.environ.get("PRINT"):
        print(system[:80])
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GEMINI}"
    out = post(url, {"systemInstruction": {"parts": [{"text": system}]},
                     "contents": [{"role": "user", "parts": [{"text": user}]}],
                     "generationConfig": {"responseMimeType": "application/json", "maxOutputTokens": max_tokens,
                                          "thinkingConfig": {"thinkingLevel": level}}}, {})
    return json.loads(out["candidates"][0]["content"]["parts"][-1]["text"])


def opus(system, user):
    out = post("https://api.anthropic.com/v1/messages",
               {"model": "claude-opus-5-5", "max_tokens": 16000, "thinking": {"type": "adaptive"},
                "system": system, "messages": [{"role": "user", "content": user}]},
               {"anthropic-version": "2023-06-01", "x-api-key": ANTHROPIC})
    text = "".join(b.get("text", "") for b in out["content"] if b["type"] == "text")
    return json.loads(text[text.index("{"):text.rindex("}") + 1])


def norm(s):
    return " ".join(re.sub(r"[^\w\s']", " ", s.lower()).split())


def items_for(system, slips):
    user = "\n".join(f'{i+1}. said "{w}" → should be "{c}" ({why})' for i, (w, c, why) in enumerate(slips))
    raw = gemini("gemini-3.6-flash", system, user, max_tokens=5000)["items"]
    out = []
    for it in raw:
        if not 1 <= it.get("source", 0) <= len(slips):
            continue
        answer_words = {norm(w) for w in it["answer"].split()}
        traps = [d for d in it.get("decoys") or [] if len(d.split()) == 1 and norm(d) not in answer_words]
        out.append({**it, "traps": traps, "slip": slips[it["source"] - 1]})
    return out


def block(items, tip=True):
    lines = []
    for i, it in enumerate(items):
        lines.append(f'{i+1}. Sentence: {it["native"]}\n   Answer: {it["answer"]}\n   Traps: {", ".join(it["traps"]) or "none"}\n'
                     f'   Earlier mistake: "{it["slip"][0]}" → "{it["slip"][1]}"\n   Point: {it["point"]}\n   Tip: {it.get("tip") or "none"}')
    return "\n".join(lines)


def good(r):
    return r and all(r.get(k) for k in ("rule", "repeats", "same_meaning", "correct", "tip_true")) and not r.get("working_traps")


def tiles(it):
    return it["answer"].split() + it["traps"]


def bag(x):
    # WeeklyTestEngine.tileBag: letters where spaces don't mark words.
    return sorted(norm(w) for w in x.split()) if " " in x.strip() else sorted(norm(x).replace(" ", ""))


def gated(items, t, n):
    """verifyTranslate: a reader who is never told the answer solves the
    tiles; a second reads the item. Traps that built a right sentence leave."""
    if not items:
        return []
    model = os.environ.get("GEMINI_GATE", "gemini-3.6-flash")
    level = os.environ.get("GATE_THINKING", "low")
    import random
    blind = "\n".join(f'{i+1}. Sentence: {it["native"]}\n   Tiles: {" | ".join(random.sample(tiles(it), len(tiles(it))))}' for i, it in enumerate(items))
    with cf.ThreadPoolExecutor(2) as ex:
        a = ex.submit(gemini, model, SOLVE(t, n), blind, level, 6000)
        b = ex.submit(gemini, model, REVIEW(t, n), block(items), level, 4000)
        solved = {r["n"]: r.get("sentences") or [] for r in a.result()["results"]}
        reviewed = {r["n"]: r for r in b.result()["results"]}
    kept = []
    for i, it in enumerate(items):
        r = reviewed.get(i + 1) or {}
        said = [x for x in solved.get(i + 1, []) if x.strip()]
        words = bag(it["answer"])
        answer_found = any(bag(x) == words for x in said)
        if not answer_found or not all(r.get(k) for k in ("rule", "repeats", "same_meaning", "correct", "tip_true")):
            it["dropped"] = r
            continue
        trap_keys = {norm(x) for x in it["traps"]}
        working = {w for x in said for w in map(norm, x.split()) if w in trap_keys}
        it = {**it, "traps": [x for x in it["traps"] if norm(x) not in working]}
        it["also"] = [x for x in said if bag(x) != words]
        if not it["traps"]:
            it["dropped"] = r
            continue
        kept.append(it)
    return kept


def judge(items, t, n):
    if not items:
        return {}
    return {r["n"]: r for r in opus(GOLD(t, n), block(items))["results"]}


def run_items(runs, langs):
    totals = {}
    def one(lang, r):
        native = "en" if lang == "ko" else "ko"
        t, n, level = NAMES[lang], NAMES[native], "B1"
        out = {}
        old = items_for(old_prompt(t, n, level), SLIPS[lang])
        new = items_for(new_prompt(t, n, level), SLIPS[lang])
        passed = gated([dict(x) for x in new], t, n)
        for name, items in (("old", old), ("new", new), ("gated", passed)):
            out[name] = (items, judge(items, t, n))
        return lang, r, out
    with cf.ThreadPoolExecutor(10) as ex:
        results = list(ex.map(lambda a: one(*a), [(l, r) for l in langs for r in range(runs)]))
    for lang, r, out in results:
        for name, (items, verdicts) in out.items():
            t = totals.setdefault((lang, name), [0, 0])
            print(f"\n=== {lang} run {r+1} {name}: {len(items)} items")
            for i, it in enumerate(items):
                v = verdicts.get(i + 1)
                ok = good(v)
                t[0] += 1
                t[1] += 1 if ok else 0
                print(f'{"OK " if ok else "BAD"} #{it["source"]} {it["native"]}  →  {it["answer"]}  traps={it["traps"]}')
                print(f'    wrong={it.get("wrong")} tip={it.get("tip")}')
                if not ok:
                    print(f"    gold: {json.dumps(v, ensure_ascii=False)}")
    print("\nlang  stage  items  good")
    for (lang, name), (n, ok) in sorted(totals.items()):
        print(f"{lang:4} {name:6} {n:5}  {ok}")
    for name in ("old", "new", "gated"):
        n = sum(v[0] for k, v in totals.items() if k[1] == name)
        ok = sum(v[1] for k, v in totals.items() if k[1] == name)
        print(f"ALL  {name:6} {n:5}  {ok}  ({100*ok//max(n,1)}%)")


def run_second(runs):
    model = os.environ.get("SECOND_MODEL", "gemini-3.6-flash")
    def one(case):
        native, answer, point, was, now, laid, expect = case
        name = "German" if " ich " in f" {answer.lower()} " else "Spanish" if "estoy" in answer.lower() else "Japanese" if "勉強" in answer else "English"
        user = f"Grammar point: {point}\nTheir earlier mistake: {was} → {now}\nThe sentence asked for: {native}\nModel answer: {answer}\nWhat they laid: {laid}"
        return case, [gemini(model, SECOND(name), user, level="minimal" if "lite" in model else "low", max_tokens=400).get("right") for _ in range(runs)]
    with cf.ThreadPoolExecutor(10) as ex:
        rows = list(ex.map(one, SECOND_CASES))
    hit = n = false_wrong = false_right = 0
    for case, got in rows:
        expect = case[6]
        right = sum(1 for g in got if g == expect)
        hit += right
        n += len(got)
        if expect:
            false_wrong += len(got) - right
        else:
            false_right += len(got) - right
        print(f'{"ok " if right == len(got) else "MISS"} expect={expect} {got} {case[5]}')
    print(f"\n{model}: {hit}/{n} right; right answers called wrong {false_wrong}; the same mistake accepted {false_right}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "items"
    runs = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    if mode == "meaning":
        run_meaning(runs)
    elif mode == "items":
        langs = (sys.argv[3] if len(sys.argv) > 3 else "en,de,ja,es,ko").split(",")
        run_items(runs, langs)
    else:
        run_second(runs)

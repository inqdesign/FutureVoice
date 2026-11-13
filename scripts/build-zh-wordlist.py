#!/usr/bin/env python3
"""Build the Simplified Chinese wordlist from the HSK 3.0 vocabulary.

    curl -sSLo complete.json \
      https://raw.githubusercontent.com/drkameleon/complete-hsk-vocabulary/main/complete.json
    python3 -I scripts/build-zh-wordlist.py complete.json

Source: drkameleon/complete-hsk-vocabulary (MIT), which carries the official
HSK 3.0 levels (GF0025-2021, "new-1" … "new-7", where 7 is the 7–9 band) with
pinyin from CC-CEDICT (CC BY-SA 4.0). Only the levels and the pinyin are
shipped, never CEDICT's English glosses.

Writes FutureVoice/Resources/:
  cefr_words_zh.tsv    headword \t level \t pinyin(s)   (pinyin joined ・)
  word_classes_zh.tsv  headword \t class[,class]
  zh_forms.tsv         other spelling \t headword        (erhua: 一点 → 一点儿)

Level mapping (a judgement, written down so it can be argued with): HSK 3.0
names its bands elementary (1–3), intermediate (4–6) and advanced (7–9), the
same three tiers CEFR calls A, B and C, and its cumulative sizes line up with
them (level 3 ends at 2,245 words, level 6 at 5,456):
  1 → a1 · 2–3 → a2 · 4 → b1 · 5–6 → b2 · 7–9 → c1
C2 stays empty, as it does for Japanese (JLPT has no C2 either).

Content words only, like every other list: a word whose EVERY tag is a
function class (structural particles 的了着, modal particles 吗吧呢,
interjections, onomatopoeia, pronouns, bare numerals) is left out. Measure
words, prepositions and conjunctions stay — 本, 张, 因为 are what a learner
of Chinese studies.
"""
import json
import os
import sys

LEVEL = {"new-1": "a1", "new-2": "a2", "new-3": "a2", "new-4": "b1",
         "new-5": "b2", "new-6": "b2", "new-7": "c1"}
RANK = {"a1": 0, "a2": 1, "b1": 2, "b2": 3, "c1": 4, "c2": 5}

# ICTCLAS-style tags as the source uses them.
FUNCTION = {"u", "y", "e", "o", "r", "m", "k", "h", "Rg", "Mg"}
CLASS = {
    "n": "noun", "nr": "noun", "ns": "noun", "nz": "noun", "nt": "noun",
    "t": "noun", "s": "noun", "f": "noun", "tg": "noun", "g": "noun",
    "v": "verb", "vn": "verb", "a": "adjective", "an": "adjective",
    "ad": "adjective", "b": "adjective", "z": "adjective", "d": "adverb",
    "q": "other", "qv": "other", "qt": "other", "mq": "other",
    "p": "other", "c": "other", "cc": "other", "l": "other",
}

HEADER_WORDS = ("# Simplified Chinese wordlist. HSK 3.0 vocabulary (GF0025-2021) via "
                "drkameleon/complete-hsk-vocabulary (MIT); pinyin from CC-CEDICT "
                "(CC BY-SA 4.0). Built by scripts/build-zh-wordlist.py.")
HEADER_CLASSES = ("# Word classes for cefr_words_zh.tsv, from the HSK 3.0 part-of-speech "
                  "tags (drkameleon/complete-hsk-vocabulary, MIT). Built by "
                  "scripts/build-zh-wordlist.py.")
HEADER_FORMS = ("# Other spellings of cefr_words_zh.tsv headwords (erhua dropped: "
                "一点 → 一点儿). Built by scripts/build-zh-wordlist.py.")


# Particles the tags can't keep out (的 is also tagged a noun, 了 a verb).
PARTICLES = {"的", "了", "着", "地", "吗", "吧", "呢", "啊", "呀", "嘛", "哦", "嗯", "哈"}

# CC-CEDICT lists every reading a character has; a learner wants the ones
# the word is read with. Surnames, variant spellings and "used in X" entries
# are other words that happen to share the characters.
SKIP_MEANING = ("surname", "variant of", "old variant", "unofficial variant",
                "used in ", "erhua variant")


def pinyin(form):
    meanings = form.get("meanings") or []
    if meanings and all(m.lower().startswith(SKIP_MEANING) for m in meanings):
        return ""
    p = form.get("transcriptions", {}).get("pinyin", "")
    return "".join(p.split()).lower() if p[:1].isupper() else "".join(p.split())


def main(src, out_dir):
    data = json.load(open(src, encoding="utf-8"))
    level, readings, classes = {}, {}, {}
    for e in data:
        lv = [LEVEL[l] for l in e.get("level", []) if l in LEVEL]
        if not lv:
            continue
        word = e["simplified"].strip()
        if not word or any(ch.isascii() for ch in word):
            continue
        tags = set(e.get("pos") or [])
        if word in PARTICLES or (tags and tags <= FUNCTION):
            continue
        best = min(lv, key=RANK.get)
        if word not in level or RANK[best] < RANK[level[word]]:
            level[word] = best
        for f in e.get("forms", []):
            p = pinyin(f)
            if p and p not in readings.setdefault(word, []):
                readings[word].append(p)
        cls = classes.setdefault(word, [])
        for t in e.get("pos") or []:
            c = CLASS.get(t)
            if c and c not in cls:
                cls.append(c)

    words = sorted(level, key=lambda w: (RANK[level[w]], w))
    with open(os.path.join(out_dir, "cefr_words_zh.tsv"), "w", encoding="utf-8") as f:
        f.write(HEADER_WORDS + "\n")
        for w in words:
            r = "・".join(readings.get(w, [])[:2])
            f.write(f"{w}\t{level[w]}\t{r}\n" if r else f"{w}\t{level[w]}\n")
    with open(os.path.join(out_dir, "word_classes_zh.tsv"), "w", encoding="utf-8") as f:
        f.write(HEADER_CLASSES + "\n")
        for w in words:
            if classes.get(w):
                f.write(f"{w}\t{','.join(classes[w])}\n")
    forms = {}
    for w in words:
        # Speech is usually transcribed without the erhua (一点 for 一点儿);
        # only when the bare spelling isn't a word of its own.
        if w.endswith("儿") and len(w) > 2:
            bare = w[:-1]
            if bare not in level and bare not in forms:
                forms[bare] = w
    with open(os.path.join(out_dir, "zh_forms.tsv"), "w", encoding="utf-8") as f:
        f.write(HEADER_FORMS + "\n")
        for k in sorted(forms):
            f.write(f"{k}\t{forms[k]}\n")

    counts = {}
    for w in words:
        counts[level[w]] = counts.get(level[w], 0) + 1
    print(f"{len(words)} headwords", dict(sorted(counts.items(), key=lambda kv: RANK[kv[0]])),
          f"{len(forms)} forms")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1], os.path.join(here, "..", "FutureVoice", "Resources"))

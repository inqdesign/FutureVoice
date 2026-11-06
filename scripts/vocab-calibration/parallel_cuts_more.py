#!/usr/bin/env python3
"""Carries the English cuts over to Korean, Japanese and Spanish through
Tatoeba en–xx pairs, the way parallel_cuts.py does for German.

The target side is read by the APP's own analyzers (KoreanMorph,
JapaneseMorph + word_classes_ja, SpanishMorph + the after-haber participle
rule) through VocabSophistication.contentLemmas, compiled standalone by
parallel_more.sh; stop words are read out of VocabSophistication.swift, so
this measures exactly what the phone reads. Each half of the pairs (odd /
even sentence id) is calibrated separately: the gap between the halves is how
far the data itself can place a cut.

Measured 2026-11-06 (odd half · even half; German through the same code for
reference: r 0.879, cuts 0.546 / 0.580 / 0.611, gap/sd 0.86 / 0.77):
  es  r 0.887  cuts 0.301/0.330/0.358 · 0.308/0.336/0.358  gap/sd 0.80/0.79
  ja  r 0.845  cuts 0.863/0.903/0.934 · 0.862/0.900/0.935  gap/sd 0.69/0.55
  ko  r 0.864  cuts 0.554/0.592/0.615 · 0.566/0.602/0.633  gap/sd 0.78/0.48
PROVISIONAL by construction: translations, not speech.

usage: python3 parallel_cuts_more.py FutureVoice/Resources FutureVoice/Services/VocabSophistication.swift \\
           <lang> pairs_<lang>.tsv
"""
import random, re, statistics as st, sys

L = ["a1", "a2", "b1", "b2", "c1", "c2"]
CONTENT = {"Noun", "Verb", "Adjective", "Adverb"}
EN_STOP = {"be", "have", "do", "will", "would", "can", "could", "may", "might", "shall", "should",
           "must", "ought", "that", "found", "mine", "plus"}
EN_CUTS = (0.25, 0.31, 0.36)   # keep = VocabSophistication.profiles["en"]


def load(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        a = line.rstrip("\n").split("\t")
        if len(a) >= 2 and a[1].lower() in L:
            out.setdefault(a[0].lower(), L.index(a[1].lower()))
    return out


def stop_words(swift, lang):
    text = open(swift, encoding="utf-8").read()
    start = text.index(f'"{lang}": Profile(')
    body = text[start:text.index("]),", start)]
    body = body[body.index("stopWords:"):]
    lines = [ln for ln in body.split("\n") if not ln.strip().startswith("//")]
    return set(re.findall(r'"([^"]+)"', "\n".join(lines)))


def en_toks(field):
    out = []
    for x in field.split():
        if "|" in x:
            w, c = x.rsplit("|", 1)
            if c in CONTENT and w not in EN_STOP:
                out.append(w)
    return out


res, swift, lang, pairs = sys.argv[1:5]
en, tg = load(f"{res}/cefr_words.tsv"), load(f"{res}/cefr_words_{lang}.tsv")
stop = stop_words(swift, lang)
halves = {0: [], 1: []}
for line in open(pairs, encoding="utf-8"):
    a = line.rstrip("\n").split("\t")
    if len(a) < 3:
        continue
    e = [en[w] for w in en_toks(a[1]) if w in en]
    d = [tg[w] for w in a[2].split() if w not in stop and w in tg]
    if e and d:
        halves[int(a[0]) % 2].append((sum(e), len(e), sum(d), len(d)))

for half in (1, 0):
    rows = halves[half]
    easy = [r for r in rows if r[0] / r[1] < 0.4]
    hard = [r for r in rows if r[0] / r[1] >= 0.4]
    random.seed(5)
    pts = []
    for _ in range(6000):
        p, acc = random.uniform(0, .5), [0, 0, 0, 0]
        while acc[1] < 500:
            r = random.choice(hard if random.random() < p else easy)
            acc = [x + y for x, y in zip(acc, r)]
        pts.append((acc[0] / acc[1], acc[2] / acc[3], acc[3]))
    r = st.correlation([p[0] for p in pts], [p[1] for p in pts])
    cuts = []
    for c in EN_CUTS:
        near = sorted(d for e, d, _ in pts if abs(e - c) < .01)
        cuts.append(near[len(near) // 2])
    sd = st.pstdev([d for e, d, _ in pts if abs(e - .31) < .01])
    band = lambda v, cs: sum(v >= c for c in cs)
    agree = sum(band(e, EN_CUTS) == band(d, cuts) for e, d, _ in pts) / len(pts)
    print(f"{lang} {'odd' if half else 'even'} half: {len(rows)} pairs, pooled r {r:.3f}, "
          f"{st.median(p[2] for p in pts):.0f} {lang} words per 500 English, "
          f"cuts {cuts[0]:.3f} / {cuts[1]:.3f} / {cuts[2]:.3f}, "
          f"gap/sd {(cuts[1] - cuts[0]) / sd:.2f} / {(cuts[2] - cuts[1]) / sd:.2f}, "
          f"same band as English {agree:.0%}")

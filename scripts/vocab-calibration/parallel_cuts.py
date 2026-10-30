#!/usr/bin/env python3
"""Carries the English cuts over to German through Tatoeba en–de pairs.

No German learner speech with levels is openly available (DAFlex is CC
BY-NC-SA; MERLIN and DISKO are writing), so German's cuts are read off the
same meaning in two languages: held-out pairs are pooled into ~500-word
"speakers" of varying difficulty, and for each English cut the median German
mean level of the pools at that English value is the German cut. Pooled means
correlate 0.88 with the current German list. PROVISIONAL by construction:
translations, not speech.

usage: python3 parallel_cuts.py FutureVoice/Resources pairs_cls.tsv
"""
import random, statistics as st, sys

L = ["a1", "a2", "b1", "b2", "c1", "c2"]
CONTENT = {"Noun", "Verb", "Adjective", "Adverb"}
EN_STOP = {"be", "have", "do", "will", "would", "can", "could", "may", "might", "shall", "should",
           "must", "ought", "that", "found", "mine", "plus"}
DE_STOP = {"sein", "haben", "werden", "tun", "können", "müssen", "sollen", "dürfen", "mögen",
           "wollen", "möchten"}
EN_CUTS = (0.25, 0.31, 0.36)   # keep = VocabSophistication.profiles["en"]


def load(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        a = line.rstrip("\n").split("\t")
        if len(a) >= 2 and a[1].lower() in L:
            out.setdefault(a[0].lower(), L.index(a[1].lower()))
    return out


def toks(field, stop):
    out = []
    for x in field.split():
        if "|" in x:
            w, c = x.rsplit("|", 1)
            if c in CONTENT and w not in stop:
                out.append(w)
    return out


en, de = load(f"{sys.argv[1]}/cefr_words.tsv"), load(f"{sys.argv[1]}/cefr_words_de.tsv")
rows = []
for line in open(sys.argv[2], encoding="utf-8"):
    a = line.rstrip("\n").split("\t")
    if len(a) < 3 or int(a[0]) % 2 == 0:
        continue
    e = [en[w] for w in toks(a[1], EN_STOP) if w in en]
    d = [de[w] for w in toks(a[2], DE_STOP) if w in de]
    if e and d:
        rows.append((sum(e), len(e), sum(d), len(d)))
easy = [r for r in rows if r[0] / r[1] < 0.4]
hard = [r for r in rows if r[0] / r[1] >= 0.4]
random.seed(5)
pts = []
for _ in range(6000):
    p, acc = random.uniform(0, .5), [0, 0, 0, 0]
    while acc[1] < 500:
        r = random.choice(hard if random.random() < p else easy)
        acc = [x + y for x, y in zip(acc, r)]
    pts.append((acc[0] / acc[1], acc[2] / acc[3]))
for c in EN_CUTS:
    near = sorted(d for e, d in pts if abs(e - c) < .01)
    print(f"en {c:.2f} -> de {near[len(near) // 2]:.3f}  (p25 {near[len(near) // 4]:.3f}, "
          f"p75 {near[3 * len(near) // 4]:.3f}, n={len(near)})")

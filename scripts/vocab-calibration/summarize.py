#!/usr/bin/env python3
"""The calibration behind VocabSophistication, from calibrate.swift's output.

Prints, by SST level: the mean CEFR level (A1=0 … C2=5) of the graded content
words, one interview and three pooled, and how well each candidate measure
tracks the level (Spearman over learners). The cuts in VocabSophistication.
profiles["en"] are read off the first table.

usage: python3 summarize.py FutureVoice/Resources/cefr_words.tsv speakers.tsv
"""
import math, random, statistics as st, sys

L = ["a1", "a2", "b1", "b2", "c1", "c2"]
CONTENT = {"Noun", "Verb", "Adjective", "Adverb"}
# keep = VocabSophistication.profiles["en"].stopWords
STOP = {"be", "have", "do", "will", "would", "can", "could", "may", "might", "shall", "should",
        "must", "ought", "that", "found", "mine", "plus"}

lv = {}
for line in open(sys.argv[1], encoding="utf-8"):
    a = line.rstrip("\n").split("\t")
    if len(a) >= 2 and a[1].lower() in L:
        lv.setdefault(a[0].lower(), L.index(a[1].lower()))
spk = {}
for line in open(sys.argv[2], encoding="utf-8"):
    f, sst, toks = line.rstrip("\n").split("\t")
    pairs = [x.rsplit("|", 1) for x in toks.split() if "|" in x]
    spk.setdefault(sst, []).append([w for w, c in pairs if c in CONTENT and w not in STOP])
levels = sorted((k for k in spk if k != "N"), key=int)[2:] + ["N"]


def mean_level(toks):
    g = [lv[w] for w in toks if w in lv]
    return (sum(g) / len(g) if g else 0), len(g)


random.seed(4)
for pool in (1, 3):
    cells = []
    for k in levels:
        xs = []
        for i in range(300 if pool > 1 else len(spk[k])):
            group = random.sample(spk[k], min(pool, len(spk[k]))) if pool > 1 else [spk[k][i]]
            m, n = mean_level([w for s in group for w in s])
            if n >= 100:
                xs.append(m)
        q = st.quantiles(xs, n=4)
        cells.append(f"{k}:{st.median(xs):.3f}({q[0]:.2f}-{q[2]:.2f})")
    print(f"mean level, {pool} interview(s): " + " ".join(cells))


def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i]); r = [0.0] * len(xs); i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2
        i = j + 1
    return r


def spearman(a, b):
    ra, rb = ranks(a), ranks(b); ma, mb = st.mean(ra), st.mean(rb)
    return sum((x - ma) * (y - mb) for x, y in zip(ra, rb)) / math.sqrt(
        sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))


rows, y = [], []
for k in levels[:-1]:
    for t in spk[k]:
        g = [lv[w] for w in t if w in lv]
        if len(g) >= 100:
            rows.append({"mean level": sum(g) / len(g), "B2+ share": sum(x >= 3 for x in g) / len(g),
                         "B1+ share": sum(x >= 2 for x in g) / len(g)})
            y.append(int(k))
for key in rows[0]:
    print(f"spearman vs SST, {key}: {spearman([r[key] for r in rows], y):.2f}")

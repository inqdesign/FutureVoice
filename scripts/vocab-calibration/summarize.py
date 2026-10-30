#!/usr/bin/env python3
"""Summarizes calibrate.swift's output: the B2+ token share by SST level, and
what the app's rule (VocabSophistication.cuts + minGradedTokens) reads over
pooled speakers, next to the old count rule it replaced.

usage: python3 summarize.py FutureVoice/Resources/cefr_words.tsv lemmas.tsv
"""
import random
import statistics as st
import sys

ORDER = ["a1", "a2", "b1", "b2", "c1", "c2"]
CUTS = [(7.0, "C2"), (6.0, "C1"), (5.0, "B2"), (4.1, "B1"), (2.6, "A2"), (0, "A1")]  # keep = VocabSophistication.cuts
MIN_GRADED = 400

lv = {}
for line in open(sys.argv[1], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 2 and p[1].lower() in ORDER:
        lv[p[0].lower()] = ORDER.index(p[1].lower())

speakers = {}
for line in open(sys.argv[2], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) == 3:
        speakers.setdefault(p[1], []).append(p[2].split())


def share(toks):
    g = [lv[w] for w in toks if w in lv]
    return sum(1 for x in g if x >= 3) / max(len(g), 1) * 100, len(g)


def new_rule(toks):
    s, n = share(toks)
    return "—" if n < MIN_GRADED else next(b for c, b in CUTS if s >= c)


def old_rule(toks):
    c, t = [0] * 6, 0
    for w in set(toks):
        if w in lv:
            c[lv[w]] += 1
            t += 1
    if t < 15:
        return "—"
    est = 0
    for i, th in enumerate([6, 6, 8, 10, 12, 15]):
        if c[i] >= th:
            est = i
    return ORDER[est].upper()


levels = sorted((k for k in speakers if k != "N"), key=int) + ["N"]
print("B2+ token share by level (one interview each): median, p25-p75")
for k in levels:
    xs = sorted(share(t)[0] for t in speakers[k])
    print(f"  SST {k:>2} n={len(xs):4}  {st.median(xs):4.1f}%  ({xs[len(xs) // 4]:.1f}-{xs[3 * len(xs) // 4]:.1f})")

random.seed(1)
for k_pool in (3, 12):
    print(f"\nPooling {k_pool} speakers of one level (more talk), 300 draws: new rule | old rule")
    for k in levels:
        new, old = {}, {}
        for _ in range(300):
            toks = [w for s in random.sample(speakers[k], min(k_pool, len(speakers[k]))) for w in s]
            a, b = new_rule(toks), old_rule(toks)
            new[a] = new.get(a, 0) + 1
            old[b] = old.get(b, 0) + 1
        fmt = lambda d: " ".join(f"{x}:{d[x] * 100 // 300}%" for x in sorted(d))
        print(f"  SST {k:>2}: {fmt(new):40} | {fmt(old)}")

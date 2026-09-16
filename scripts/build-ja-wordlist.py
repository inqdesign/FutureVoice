#!/usr/bin/env python3
"""Build the Japanese graded wordlist the app ships as a target-language pool.

Source: open-anki-jlpt-decks (MIT, Jamie Sinclair), itself derived from
Jonathan Waller's JLPT lists at tanos.co.uk (CC-BY). The official JLPT lists
have not been published since 2010, so every JLPT vocabulary list in use is a
reconstruction; Waller's is the one the community converged on.

Writes two files into FutureVoice/Resources:

  cefr_words_ja.tsv     headword<TAB>level    (the same shape as every pool)
  ja_readings.tsv       kana<TAB>headword     (kana spelling -> kanji headword)

JLPT -> CEFR follows LanguageCatalog.jlptByCEFR in reverse:
N5 a1 · N4 a2 · N3 b1 · N2 b2 · N1 c1. C2 sits past the JLPT scale and stays
empty on purpose.

The readings file exists because speech gets written either way: a
transcriber writes わかる as often as 分かる, and without a map the kana
spelling is simply not in the pool. A reading is kept only when it names
exactly ONE headword (はし is 橋 and 箸 — no guess), and never when the kana
is itself a headword.

    python3 scripts/build-ja-wordlist.py            # download + build
    python3 scripts/build-ja-wordlist.py --src DIR  # use n5.csv … n1.csv in DIR
"""
import argparse
import csv
import io
import os
import re
import sys
import urllib.request
from collections import defaultdict

UPSTREAM = "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n{}.csv"
LEVELS = {5: "a1", 4: "a2", 3: "b1", 2: "b2", 1: "c1"}
RANK = {"a1": 0, "a2": 1, "b1": 2, "b2": 3, "c1": 4}

KANA = re.compile(r"^[ぁ-ゟ゠-ヿー]+$")
WORD = re.compile(r"^[ぁ-ゟ゠-ヿー一-鿿々]+$")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "FutureVoice", "Resources")


def rows(src):
    for n in LEVELS:
        if src:
            text = open(os.path.join(src, f"n{n}.csv"), encoding="utf-8").read()
        else:
            text = urllib.request.urlopen(UPSTREAM.format(n)).read().decode("utf-8")
        for r in csv.DictReader(io.StringIO(text)):
            yield LEVELS[n], r["expression"], r["reading"]


def split_alts(field):
    return [p.strip() for p in field.split(";") if p.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    args = ap.parse_args()

    level_of = {}
    readings = defaultdict(set)
    dropped = 0
    for level, expr, reading in rows(args.src):
        heads = split_alts(expr)
        reads = split_alts(reading)
        for i, head in enumerate(heads):
            # Affix entries (～円, お～) are grammar, not words anyone says alone.
            if not WORD.match(head):
                dropped += 1
                continue
            if head not in level_of or RANK[level] < RANK[level_of[head]]:
                level_of[head] = level
            # Pair alternatives positionally when both sides split the same
            # way (いい; よい / いい; よい); otherwise every reading belongs to
            # every spelling (足; 脚 / あし).
            pair = [reads[i]] if len(reads) == len(heads) else reads
            for r in pair:
                if KANA.match(r) and r != head and not KANA.match(head):
                    readings[r].add(head)

    words = sorted(level_of.items(), key=lambda kv: (RANK[kv[1]], kv[0]))
    with open(os.path.join(OUT, "cefr_words_ja.tsv"), "w", encoding="utf-8") as f:
        for head, level in words:
            f.write(f"{head}\t{level}\n")

    kept = sorted((r, next(iter(h))) for r, h in readings.items()
                  if len(h) == 1 and r not in level_of)
    with open(os.path.join(OUT, "ja_readings.tsv"), "w", encoding="utf-8") as f:
        for r, head in kept:
            f.write(f"{r}\t{head}\n")

    by_level = defaultdict(int)
    for _, level in words:
        by_level[level] += 1
    print(f"{len(words)} headwords {dict(by_level)} · {len(kept)} readings · "
          f"{dropped} affix entries dropped", file=sys.stderr)


if __name__ == "__main__":
    main()

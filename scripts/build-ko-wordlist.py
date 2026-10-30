#!/usr/bin/env python3
"""Builds FutureVoice/Resources/cefr_words_ko.tsv from 국립국어원's graded
vocabulary of the 국제 통용 한국어 표준 교육과정 (1급–6급, 10,635 entries).

The list before this (2026-07) was the 2003 「한국어 학습용 어휘 목록」, whose
THREE grades were cut into six bands, so the 고급 grade's everyday words landed
in C2 (탁자, 걷기, 한식, 추천하다) and a few of them read as a C2 vocabulary.
The curriculum list grades six levels itself: 1급 → a1 … 6급 → c2.

Source (공공누리 제1유형 — use with attribution; the attribution is the
file's first line, which the loaders skip because it has no tab):
  https://www.korean.go.kr/front/reportData/reportDataView.do?mn_id=207&report_seq=932
  「2017년 국제 통용 한국어 표준 교육과정 적용 연구(4단계) 어휘, 문법 등급 목록」 .xlsx

Two things the curriculum list does differently, both handled here:
- One cell can hold several words (`계속02/계속01`, `시간적01∙시간적02`);
  each is its own headword, homonym numbers stripped, the EASIEST grade kept.
- 하다/되다 verbs are not listed apart from their noun (`공부`, not
  `공부하다`). A derivation takes its base's grade (공부하다 ← 공부,
  길어지다 ← 길다, 걷기 ← 걷다), and the few with no base in the curriculum
  (때문, 싶다, 핸드폰…) keep their old band.

The headword SET is the previous list's, unchanged — see `main` — so this
regrades; it does not grow the pool. Re-running it is a no-op.

    python3 scripts/build-ko-wordlist.py <grades.xlsx>
Then re-run scripts/build-word-classes.py and copy the .tsv to Android's
assets/wordlists/.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "FutureVoice/Resources/cefr_words_ko.tsv"
LEVELS = ["a1", "a2", "b1", "b2", "c1", "c2"]
HEADER = ("# 국립국어원 「2017년 국제 통용 한국어 표준 교육과정 적용 연구(4단계)」 어휘 등급 목록 "
          "(공공누리 제1유형), 1급–6급 → A1–C2. Built by scripts/build-ko-wordlist.py.")
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

# Suffix → how to find the base: (suffix, base ending appended).
DERIVATIONS = [
    ("해지다", ""), ("하다", ""), ("되다", ""), ("시키다", ""), ("받다", ""),
    ("당하다", ""), ("스럽다", ""), ("롭다", ""), ("적", ""), ("히", ""),
    ("어지다", "다"), ("아지다", "다"), ("여지다", "다"), ("워지다", "다"),
    ("기", "다"),
]


def sheet_rows(xlsx: str):
    with zipfile.ZipFile(xlsx) as z:
        shared = [''.join(t.text or '' for t in si.iter('{%s}t' % NS['m']))
                  for si in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si', NS)]
        root = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))   # sheet "어휘"
    for row in root.iter('{%s}row' % NS['m']):
        cells = {}
        for c in row.findall('m:c', NS):
            v = c.find('m:v', NS)
            if v is None:
                continue
            cells[re.sub(r'\d', '', c.get('r'))] = shared[int(v.text)] if c.get('t') == 's' else v.text
        yield cells


def curriculum(xlsx: str) -> dict:
    best = {}
    for cells in sheet_rows(xlsx):
        m = re.match(r'(\d)급', cells.get('C', ''))
        word, pos = cells.get('D', '').strip(), cells.get('E', '')
        if not m or not word or '접사' in pos:
            continue
        grade = int(m.group(1)) - 1
        for part in re.split(r'[/∙·]', word):
            head = re.sub(r'\d+$', '', part.strip()).strip()
            if not head or head.startswith('-') or head.endswith('-') or ' ' in head:
                continue
            if head not in best or grade < best[head]:
                best[head] = grade
    return best


def previous() -> dict:
    out = {}
    for line in OUT.read_text(encoding='utf-8').splitlines():
        parts = line.split('\t')
        if len(parts) >= 2 and parts[1].strip().lower() in LEVELS:
            out[parts[0]] = LEVELS.index(parts[1].strip().lower())
    return out


def main():
    graded = curriculum(sys.argv[1])
    old = previous()
    # The HEADWORDS stay the ones `KoreanMorph` was tuned on; only their
    # bands come from the curriculum. Adding the curriculum's other ~5,000
    # nouns was measured against Tatoeba's Korean sentences and broke the
    # verb readings they share letters with (배우는 → 배우, 오는 → 오, 남은 →
    # 남, 일어나 → 일어): the analyzer has no context, only the lexicon.
    merged = {}
    regraded = derived = kept = 0
    for word, level in old.items():
        if word in graded:
            merged[word] = graded[word]
            regraded += 1
            continue
        base = next((word[:-len(s)] + add for s, add in DERIVATIONS
                     if word.endswith(s) and len(word) > len(s) and word[:-len(s)] + add in graded), None)
        if base:
            merged[word] = graded[base]
            derived += 1
        else:
            merged[word] = level
            kept += 1
    lines = [HEADER] + [f"{w}\t{LEVELS[l]}" for w, l in
                        sorted(merged.items(), key=lambda kv: (kv[1], kv[0]))]
    OUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    counts = [sum(1 for l in merged.values() if l == i) for i in range(6)]
    print(f"{len(merged)} headwords ({regraded} regraded, {derived} derived, {kept} kept): "
          + " ".join(f"{LEVELS[i]}:{counts[i]}" for i in range(6)))


if __name__ == '__main__':
    main()

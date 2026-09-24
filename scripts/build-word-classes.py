#!/usr/bin/env python3
"""
Builds `FutureVoice/Resources/word_classes_<code>.tsv` — the coarse word class
(noun / verb / adjective / adverb / na-adjective / predicate / other) of every
headword in each graded wordlist. `WordClass.swift` reads these; its runtime
rules (NLTagger, headword shape) are only the fallback for a word that is not
on the list.

Why a table and not the tagger: NLTagger on a single word out of context
agrees with the CEFR-J/Octanove profiles on only 72% of English headwords
(measured 2026-09-24), has no lexical-class model at all for Korean and
Japanese, and files most German adjectives as adverbs. The wordlists came
from sources that KNOW the part of speech, so the class is taken from them:

  en  CEFR-J Vocabulary Profile 1.5 + Octanove Vocabulary Profile C1/C2 1.0
      (openlanguageprofiles/olp-en-cefrj, CC BY-SA 4.0) — the lists the
      English wordlist itself was built from; `pos` column. A headword with
      several rows keeps every class (run: noun,verb).
  ja  JMdict (EDRDG, CC BY-SA 4.0) — the same file build-ja-wordlist.py
      reads; every <pos> of every entry whose kanji or kana form is the
      headword. suru-nouns are nouns (勉強), not verbs.
  de  No source with a part of speech (Goethe lists are PDFs), so German
      orthography does it, which is exact for a headword list: a capital
      letter is a noun; -en/-eln/-ern (and tun/sein) is an infinitive, minus
      the hand list below of adjectives and adverbs that end the same way
      (offen, selten, zufrieden…) and anything in un- (no verb starts with the
      negating un-); everything else is an adjective, which in
      German is also the adverb — one class, because a learner can't tell
      them apart by shape either.
  ko  Dictionary form in 다 is a predicate (verb or adjective — the 다 is what
      a learner sees, and it is the same 다), minus the nouns and adverbs
      that happen to end in 다 (바다, 해마다); everything else is "other".

Usage:
    python3 scripts/build-word-classes.py --src DIR
    DIR holds cefrj-vocabulary-profile-1.5.csv,
    octanove-vocabulary-profile-c1c2-1.0.csv and JMdict_e.gz.
"""
import argparse, csv, gzip, os, sys, xml.etree.ElementTree as ET
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "FutureVoice", "Resources")

CREDIT = {
    "en": "# Word classes for cefr_words.tsv, from the CEFR-J Vocabulary Profile 1.5 and the Octanove Vocabulary Profile C1/C2 1.0 (CC BY-SA 4.0). Built by scripts/build-word-classes.py.",
    "ja": "# Word classes for cefr_words_ja.tsv, from JMdict (EDRDG, CC BY-SA 4.0). Built by scripts/build-word-classes.py.",
    "de": "# Word classes for cefr_words_de.tsv, from German orthography (capital = noun, -en = verb, else adjective) with a hand list of -en adjectives. Built by scripts/build-word-classes.py.",
    "ko": "# Word classes for cefr_words_ko.tsv: dictionary form in 다 = predicate, else other, with a hand list of 다-nouns. Built by scripts/build-word-classes.py.",
}

# German words that end like an infinitive but are adjectives or adverbs.
# Found by classifying the whole wordlist and reading every -en word the
# tagger did not call a verb, plus the participle adjectives it did.
DE_EN_NOT_VERBS = set("""
selten offen trocken golden vollkommen willkommen verschieden bescheiden
gelegen gediegen verlegen verwegen gelungen erwachsen geschlossen entlegen
angemessen vermessen besonnen erhaben erlesen ausgelassen gelassen unbefangen
befangen verdorben unbescholten silbern drinnen draußen hinten oben unten
gestern inzwischen zusammen zufrieden unzufrieden modern gern nüchtern
schüchtern umstritten unumstritten ungezogen gezwungenermaßen realitätsfern
unangefochten unentschlossen ungebrochen ungehalten unumwunden
unvoreingenommen hochgestochen ungeschoren außen innen einigermaßen
einverstanden sieben sondern
gehoben gerissen gesalzen geschwollen aufgeschlossen ausgeglichen
ausgeschlossen angesehen verstohlen
""".split())
# Both an infinitive and an adjective.
DE_EN_BOTH = {"erfahren", "gefangen", "betrunken", "vergangen", "überlegen", "berufen", "verkommen"}

# Korean nouns and adverbs that end in 다.
KO_DA_NOT_PREDICATES = {"바다", "앞바다", "캐나다", "해마다", "저마다"}


def wordlist(name):
    out = []
    with open(os.path.join(RES, name), encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and not line.startswith("#"):
                out.append(parts[0])
    return out


def write(code, rows):
    path = os.path.join(RES, f"word_classes_{code}.tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write(CREDIT[code] + "\n")
        for word, classes in rows:
            f.write(f"{word}\t{','.join(sorted(classes))}\n")
    print(f"{code}: {len(rows)} rows → {os.path.relpath(path, ROOT)}")


def build_en(src):
    EN_POS = {"noun": "noun", "verb": "verb", "adjective": "adjective", "adverb": "adverb"}
    table = defaultdict(set)
    for name in ("cefrj-vocabulary-profile-1.5.csv", "octanove-vocabulary-profile-c1c2-1.0.csv"):
        with open(os.path.join(src, name), encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                pos = r["pos"].strip().lower()
                cls = EN_POS.get(pos, "other" if pos else None)
                if not cls:
                    continue
                for hw in r["headword"].split("/"):
                    table[hw.strip().lower()].add(cls)
    rows, missing = [], 0
    for w in wordlist("cefr_words.tsv"):
        if w.lower() in table:
            rows.append((w, table[w.lower()]))
        else:
            missing += 1
    print(f"en: {missing} headwords not in the profiles (compounds written solid) — left to the runtime tagger")
    return rows


def ja_bucket(poses):
    b = set()
    for p in poses:
        pl = p.lower()
        if pl.startswith(("godan", "ichidan", "kuru verb", "nidan", "yodan", "suru verb")) or pl in ("irregular verb", "verb unspecified"):
            b.add("verb")
        elif "takes the aux. verb suru" in pl:
            b.add("noun")
        elif pl.startswith("adjective (keiyoushi)"):
            b.add("adjective")
        elif pl.startswith("adjectival noun") or "keiyodoshi" in pl:
            b.add("na-adjective")
        elif pl.startswith("adverb"):
            b.add("adverb")
        elif pl.startswith(("noun", "counter", "numeric", "pronoun")):
            b.add("noun")
        elif pl.startswith(("expression", "interjection", "conjunction", "particle", "pre-noun", "auxiliary", "prefix", "suffix", "copula")):
            b.add("other")
    # A word that is a full verb/adjective/noun is not also "other" for
    # having an idiomatic sense filed as an expression.
    if len(b) > 1:
        b.discard("other")
    return b


def build_ja(src):
    pos_by_form = defaultdict(set)
    with gzip.open(os.path.join(src, "JMdict_e.gz"), "rb") as f:
        for _, el in ET.iterparse(f):
            if el.tag != "entry":
                continue
            forms = [k.text for k in el.iter("keb")] + [r.text for r in el.iter("reb")]
            poses = {p.text for s in el.iter("sense") for p in s.iter("pos")}
            for fm in forms:
                pos_by_form[fm] |= poses
            el.clear()
    rows, missing = [], []
    for w in wordlist("cefr_words_ja.tsv"):
        b = ja_bucket(pos_by_form.get(w, set()))
        if b:
            rows.append((w, b))
        else:
            missing.append(w)
    print(f"ja: {len(missing)} headwords not in JMdict — left to the shape rule: {' '.join(missing)}")
    return rows


def build_de():
    rows = []
    for w in wordlist("cefr_words_de.tsv"):
        if w[:1].isupper():
            cls = {"noun"}
        elif w in DE_EN_BOTH:
            cls = {"verb", "adjective"}
        elif w in DE_EN_NOT_VERBS:
            cls = {"adjective"}
        elif w.startswith("un") and not w.startswith("unter"):
            # No German verb begins with the negating un- (unbeholfen,
            # ungezwungen, unerfahren); only unter- verbs start that way.
            cls = {"adjective"}
        elif w.endswith(("en", "eln", "ern")) or w.endswith(("tun", "sein")):
            cls = {"verb"}
        else:
            cls = {"adjective"}
        rows.append((w, cls))
    return rows


def build_ko():
    rows = []
    for w in wordlist("cefr_words_ko.tsv"):
        if len(w) >= 2 and w.endswith("다") and w not in KO_DA_NOT_PREDICATES:
            rows.append((w, {"predicate"}))
        else:
            rows.append((w, {"other"}))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="directory with the CEFR-J/Octanove CSVs and JMdict_e.gz")
    a = ap.parse_args()
    write("en", build_en(a.src))
    write("ja", build_ja(a.src))
    write("de", build_de())
    write("ko", build_ko())


if __name__ == "__main__":
    sys.exit(main())

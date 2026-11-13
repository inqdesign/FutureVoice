#!/usr/bin/env python3
"""Builds FutureVoice/Resources/cefr_words_fr.tsv, word_classes_fr.tsv and fr_forms.tsv.

No CEFR-graded French list can ship in a paid app (FLELex, the only one, is
CC BY-NC-SA), so the level is a FREQUENCY band under a hand-written A1/A2
core, the way the Spanish list is built (scripts/build-es-wordlist.swift).

What differs from Spanish is where the lemma comes from. Spanish was tagged
in context by Apple's NLTagger on a Mac, because iOS has no Spanish lemma
model. For French the Mac's tagger is no use either (measured 2026-11-13:
"Je suis fatiguée" comes back suis → suivre IN CONTEXT, and it splits
grand-mère in two), so the lemma comes from Lexique 3.83, a curated French
lexicon that lists every form with its lemma, class and subtitle frequency.
The form table the app reads (`FrenchMorph`) and the headwords here are the
same rules over the same table, so speech and list can't disagree.

A form can belong to several lemmas (été: summer / être; fatigué: tired /
fatiguer). The table keeps ONE default reading and up to two context
readings, which `FrenchMorph` applies at runtime:
  - after a determiner (le, la, l', un, ce, mon…): the NOUN reading
    ("l'été" is summer, "j'ai été" is être)
  - after a form of avoir: the VERB reading ("j'ai aimé" is aimer, while
    "je suis fatigué" keeps the adjective)
The default is the reading whose LEMMA is most frequent in subtitles, except
that a past participle whose adjective reading is at least a quarter of the
form's use defaults to the adjective (the verb comes back after avoir). Lexique's per-form frequency split is
not used to choose: it gives "suis" to suivre over être.

Inputs (not committed — download into one directory):
  Lexique383.tsv  http://www.lexique.org/databases/Lexique383/Lexique383.tsv
                  (New, Pallier et al., CC BY-SA 4.0)
  fra.tsv         downloads.tatoeba.org/exports/per_language/fra/fra_sentences.tsv.bz2
                  (CC BY 2.0 FR), bunzip2'd

Run: python3 -I scripts/build-fr-wordlist.py <dir-with-inputs> FutureVoice/Resources
"""
import math
import os
import re
import sys
from collections import Counter, defaultdict

if len(sys.argv) != 3:
    sys.exit("usage: build-fr-wordlist.py <inputs> <out>")
IN, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))

CONTENT = {"NOM": "noun", "VER": "verb", "ADJ": "adjective", "ADV": "adverb"}

# Left out ON PURPOSE (mirrors CoreVocabulary.ungradedByLanguage["fr"]):
# auxiliaries, modals, quantifiers and indefinites Lexique still files as
# content words, the negation, and spoken fillers.
UNGRADED = {
    "être", "avoir", "aller", "faire", "pouvoir", "devoir", "vouloir", "falloir",
    "beaucoup", "peu", "trop", "tout", "rien", "chaque", "même", "tel", "autre",
    "plus", "moins", "très", "aussi", "ainsi", "alors", "donc", "puis", "pas", "ne",
    "oui", "non", "si", "déjà", "encore", "bon", "euh", "ben", "bah", "hein", "quoi",
    "voilà", "ouais", "ok", "okay", "salut", "bonjour", "merci", "est-ce que",
    "ça", "cela", "ceci", "quelque", "quelques", "certain", "plusieurs", "assez",
    "là", "ici", "comme", "comment", "pourquoi", "quand", "où", "y", "en",
}

# Not words a learner is taught, found reading the output: interjections,
# English, Lexique's subtitle artefacts.
JUNK = {"sous-titrage", "sous-titre", "hum", "hmm", "chut", "oh", "ah", "eh", "hé",
        "bye", "ouah", "waouh", "boum", "bla", "ciao"}

DETERMINERS = {"le", "la", "l'", "les", "un", "une", "des", "du", "au", "aux", "ce",
               "cet", "cette", "ces", "mon", "ton", "son", "ma", "ta", "sa", "mes",
               "tes", "ses", "notre", "votre", "nos", "vos", "leur", "leurs", "chaque",
               "quel", "quelle", "quels", "quelles", "d'", "de"}
AVOIR = {"ai", "as", "a", "avons", "avez", "ont", "avais", "avait", "avions", "aviez",
         "avaient", "aurai", "auras", "aura", "aurons", "aurez", "auront", "aurais",
         "aurait", "aurions", "auriez", "auraient", "eu", "ayant", "avoir", "aie", "ait",
         "ayons", "ayez", "aient", "eus", "eut", "eûmes", "eurent"}

# ---------------------------------------------------------------- Lexique
rows = defaultdict(list)          # form → [(lemma, cgram, freqlem, isParticiple, formFreq)]
lemma_films = defaultdict(float)  # (lemma, cgram) → freqlemfilms2
heard = set()                     # forms with any subtitle or book frequency

def ligature(w):
    """Lexique writes soeur, oeil, coeur; speech-to-text and every model write
    sœur, œil, cœur. "oe" before u or i is the ligature in French (coexister,
    moelle and poème keep theirs). FrenchMorph folds lookups the same way."""
    return re.sub(r"oe(?=[ui])", "œ", w)

# Words Lexique 3.83 doesn't list at all.
SUPPLEMENT = [("après-midi", "après-midi", "NOM", 35.0, False, 35.0)]
with open(os.path.join(IN, "Lexique383.tsv"), encoding="utf-8") as f:
    head = f.readline().rstrip("\n").split("\t")
    col = {name: i for i, name in enumerate(head)}
    for line in f:
        c = line.rstrip("\n").split("\t")
        form, lemma, cg = ligature(c[col["ortho"]].lower()), ligature(c[col["lemme"]].lower()), c[col["cgram"]]
        if not form or not lemma:
            continue
        if cg == "AUX":
            cg = "VER"
        freqlem = float(c[col["freqlemfilms2"]] or 0)
        part = "par:pas" in c[col["infover"]]
        rows[form].append((lemma, cg, freqlem, part, float(c[col["freqfilms2"]] or 0)))
        lemma_films[(lemma, cg)] = max(lemma_films[(lemma, cg)], freqlem)
        if float(c[col["freqfilms2"]] or 0) >= 0.1 or float(c[col["freqlivres"]] or 0) >= 0.1:
            heard.add(form)
for form, lemma, cg, freqlem, part, ff in SUPPLEMENT:
    rows[form].append((lemma, cg, freqlem, part, ff))
    lemma_films[(lemma, cg)] = max(lemma_films[(lemma, cg)], freqlem)
    heard.add(form)

def reading(form):
    """(default, noun_after_det, verb_after_avoir), each (lemma, cgram) or None.
    A default of (None, None) means the form is a function word."""
    rs = rows.get(form)
    if not rs:
        return None
    best = max(rs, key=lambda r: (r[2], r[1] in CONTENT))
    if best[1] not in CONTENT:
        default = (None, None)
    else:
        default = (best[0], best[1])
        # Only where the adjective is a real share of the form's use
        # (fatiguée: 14.6 adj / 20.5 verb per million) — not jugé, effacé.
        adj = [r for r in rs if r[1] == "ADJ" and best[4] > 0 and r[4] >= 0.25 * best[4]]
        if best[1] == "VER" and best[3] and adj:
            default = (adj[0][0], "ADJ")
    nouns = sorted([r for r in rs if r[1] == "NOM"], key=lambda r: -r[2])
    verbs = sorted([r for r in rs if r[1] == "VER"], key=lambda r: -r[2])
    noun = (nouns[0][0], "NOM") if nouns and default != (nouns[0][0], "NOM") else None
    verb = (verbs[0][0], "VER") if verbs and default[1] == "ADJ" and verbs[0][3] else None
    return default, noun, verb

READ = {form: reading(form) for form in rows}

# --------------------------------------------------- tokenizing (= FrenchMorph)
ELIDED = {"l", "d", "j", "m", "t", "s", "n", "c", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu"}

def words(text):
    """Lowercased words of `text`, the way FrenchMorph.words cuts them."""
    out = []
    for run in re.findall(r"[^\W\d_]+(?:['’\-][^\W\d_]+)*", text):
        w = ligature(run.lower().replace("’", "'"))
        if w in READ:
            out.append(w)
            continue
        for piece in re.split(r"(?<=')", w):          # keep the apostrophe on l'
            if piece in READ or "-" not in piece:
                out.append(piece)
            else:
                out.extend(p for p in piece.split("-") if p)
    return out

def resolve(prev, w):
    r = READ.get(w)
    if not r:
        return None
    default, noun, verb = r
    if noun and prev in DETERMINERS:
        return noun
    if verb and prev in AVOIR:
        return verb
    return default if default[0] else None

# ---------------------------------------------------------------- Tatoeba
tat = Counter()
tat_class = defaultdict(Counter)
form_seen = defaultdict(lambda: [0, 0])      # form → [total, capitalized mid-sentence]
with open(os.path.join(IN, "fra.tsv"), encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t", 2)
        if len(parts) != 3:
            continue
        s = parts[2]
        runs = re.findall(r"[^\W\d_]+(?:['’\-][^\W\d_]+)*", s)
        for i, run in enumerate(runs):
            seen = form_seen[ligature(run.lower().replace("’", "'"))]
            seen[0] += 1
            if i > 0 and run[0].isupper():
                seen[1] += 1
        prev = None
        for w in words(s):
            r = resolve(prev, w)
            if r:
                tat[r[0]] += 1
                tat_class[r[0]][r[1]] += 1
            prev = w

def is_name(form):
    total, caps = form_seen.get(form, (0, 0))
    return total >= 5 and caps * 2 > total

# ---------------------------------------------------------------- rank
films = defaultdict(float)
for (lemma, cg), fr in lemma_films.items():
    if cg in CONTENT:
        films[lemma] = max(films[lemma], fr)

def ranks(d):
    return {k: i + 1 for i, (k, _) in enumerate(sorted(d.items(), key=lambda kv: (-kv[1], kv[0])))}

reachable = set(tat)   # a headword must be something speech can produce
rf = ranks({l: v for l, v in films.items() if l in reachable and v > 0})
rt = ranks(tat)
LETTERS = re.compile(r"^[^\W\d_]+(?:['\-][^\W\d_]+)*$")

candidates = {}
for lemma, frank in rf.items():
    if (len(lemma) < 3 or not LETTERS.match(lemma) or lemma in UNGRADED or lemma in JUNK
            or tat[lemma] < 3 or is_name(lemma)):
        continue
    cls = tat_class[lemma].most_common(1)[0][0]
    candidates[lemma] = (frank ** 0.4 * rt[lemma] ** 0.6, cls)

# ---------------------------------------------------------------- hand core
core = {}
with open(os.path.join(HERE, "fr-core-a1a2.txt"), encoding="utf-8") as f:
    for line in f:
        if line.startswith("#") or "\t" not in line:
            continue
        word, level = line.rstrip("\n").split("\t")
        # A core word is written as a lemma; keep it when Lexique has it as
        # one (été the season, not the être its form defaults to).
        own = [row for row in rows.get(word, []) if row[0] == word and row[1] in CONTENT]
        r = READ.get(word)
        if own:
            lemma, cls = word, max(own, key=lambda row: row[2])[1]
        else:
            lemma = r[0][0] if r and r[0][0] else word
            cls = r[0][1] if r and r[0][1] else "NOM"
        if lemma in UNGRADED:
            continue
        if lemma in core and core[lemma] <= level:
            continue
        core[lemma] = level
        if lemma not in candidates:
            if lemma not in READ and word not in READ:
                print(f"core word not in Lexique: {word}", file=sys.stderr)
                continue
            candidates[lemma] = (math.inf, cls)

scored = sorted(((l, s, c) for l, (s, c) in candidates.items()), key=lambda x: (x[1], x[0]))

# Band sizes follow the English list's shape (cefr_words.tsv), like Spanish.
BANDS = [("A1", 900), ("A2", 1200), ("B1", 2100), ("B2", 2400), ("C1", 900), ("C2", 800)]
ORDER = [b for b, _ in BANDS]
out_rows, i = [], 0
for band, size in BANDS:
    for lemma, _, cls in scored[i:i + size]:
        level = band
        cap = core.get(lemma)
        if cap and ORDER.index(cap) < ORDER.index(band):
            level = cap          # the core caps a level, never raises it
        out_rows.append((lemma, level, cls))
    i += size
    if i >= len(scored):
        break
placed = {r[0] for r in out_rows}
for lemma, level in core.items():
    if lemma not in placed:
        out_rows.append((lemma, level, candidates.get(lemma, (0, "NOM"))[1]))

CREDIT = ("Lexique 3.83 (New, Pallier et al., lexique.org, CC BY-SA 4.0) and Tatoeba "
          "(CC BY 2.0 FR). Built by scripts/build-fr-wordlist.py.")
words_out = ["# French wordlist. Levels are frequency bands under a hand-written A1/A2 core, "
             "not CEFR judgments: lemmas ranked by the geometric mean of their subtitle "
             "frequency in " + CREDIT]
classes_out = ["# Word classes for cefr_words_fr.tsv, from " + CREDIT]
headwords = {}
for band in ORDER:
    for lemma, level, cls in sorted((r for r in out_rows if r[1] == band), key=lambda r: r[0]):
        words_out.append(f"{lemma}\t{level}")
        classes_out.append(f"{lemma}\t{CONTENT[cls]}")
        headwords[lemma] = cls
with open(os.path.join(OUT, "cefr_words_fr.tsv"), "w", encoding="utf-8") as f:
    f.write("\n".join(words_out) + "\n")
with open(os.path.join(OUT, "word_classes_fr.tsv"), "w", encoding="utf-8") as f:
    f.write("\n".join(classes_out) + "\n")

# ---------------------------------------------------------------- forms
# form TAB default lemma (empty = itself, "-" = function word) TAB class
#      TAB noun lemma after a determiner TAB verb lemma after avoir
# Only forms whose readings reach a content word are written; a form that
# isn't in the table is its own lemma with no class.
def cell(r, form):
    if not r:
        return ""
    return "" if r[0] == form else r[0]

lines = ["# French surface forms → headword + class, with the context readings "
         "FrenchMorph applies. From " + CREDIT]
n = 0
# Lexique lists rare conjugations nobody says (coexisterons); a form goes in
# when it was heard in subtitles or books, or used on Tatoeba, or is a headword.
for form in sorted(READ):
    if not LETTERS.match(form) or len(form) < 2 or is_name(form):
        continue
    if form not in heard and form_seen.get(form, (0, 0))[0] == 0 and form not in headwords:
        continue
    default, noun, verb = READ[form]
    # A function word joined by an apostrophe or hyphen (quelqu'un,
    # c'est-à-dire) stays in, as "-", so the app cuts it whole like the build.
    if not default[0] and not noun and not re.search(r"['\-]", form):
        continue
    if default[0]:
        lem = "" if default[0] == form else default[0]
        cls = CONTENT[default[1]]
    else:
        lem, cls = "-", ""
    nn = noun[0] if noun else ""
    vv = verb[0] if verb else ""
    lines.append(f"{form}\t{lem}\t{cls}\t{nn}\t{vv}")
    n += 1
with open(os.path.join(OUT, "fr_forms.tsv"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {n} forms, {len(out_rows)} headwords")

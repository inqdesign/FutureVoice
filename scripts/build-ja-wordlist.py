#!/usr/bin/env python3
"""Build the Japanese graded wordlist the app ships as a target-language pool.

Sources
  • open-anki-jlpt-decks (MIT, Jamie Sinclair), itself derived from Jonathan
    Waller's JLPT lists at tanos.co.uk (CC-BY). The official JLPT lists have
    not been published since 2010, so every JLPT vocabulary list in use is a
    reconstruction; Waller's is the one the community converged on.
  • JMdict (EDRDG, CC-BY-SA 4.0) — read only to learn each word's OTHER
    spellings and readings, and which kanji forms nobody writes.

Writes two files into FutureVoice/Resources:

  cefr_words_ja.tsv     headword<TAB>level<TAB>reading[・reading…]
                        (every pool's shape, plus how the word is READ —
                        the word card shows it under a kanji headword)
  ja_forms.tsv          spelling<TAB>headword (any other way to write it)

JLPT -> CEFR follows LanguageCatalog.jlptByCEFR in reverse:
N5 a1 · N4 a2 · N3 b1 · N2 b2 · N1 c1. C2 sits past the JLPT scale and stays
empty on purpose.

THE HEADWORD IS WHAT THE LEARNER SEES, so its spelling is chosen with care:

  1. The deck's own spelling wins by default. It is a curated learner list,
     and it already writes ありがとう, ちょっと, できる in kana where a
     textbook does.
  2. JMdict's "usually written in kana" flag is NOT trusted on its own — it
     marks 犬, 行く and 見る, which every textbook and every model writes in
     kanji. It is used only where JMdict ALSO tags the deck's kanji form as
     rarely used, ateji, search-only or irregular okurigana (為る → する,
     丁度 → ちょうど, 可愛い → かわいい, 下る/さがる → 下がる).
  3. KANA_HEADWORDS below is the hand-checked remainder: kanji spellings the
     deck kept that a learner will never meet on a screen (下さい, 美味しい,
     沢山, 綺麗, 繋がる …). Reviewed against N5–N1 in full on 2026-09-18;
     when in doubt the kanji stayed, because a kanji headword is at worst
     unfamiliar while a wrong kana one is a different word.

Whatever the headword, `ja_forms.tsv` carries every OTHER spelling JMdict
knows for it — the kana reading, alternative kanji, okurigana variants — so
a transcriber writing わかる, 判る or 解る all land on 分かる. A spelling is
kept only when it names exactly ONE headword (はし is 橋 and 箸 — no guess)
and is not itself a headword.

    python3 scripts/build-ja-wordlist.py            # download + build
    python3 scripts/build-ja-wordlist.py --src DIR  # n5.csv … n1.csv + JMdict_e.gz in DIR
"""
import argparse
import csv
import gzip
import io
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict

DECK = "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n{}.csv"
JMDICT = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
LEVELS = {5: "a1", 4: "a2", 3: "b1", 2: "b2", 1: "c1"}
RANK = {"a1": 0, "a2": 1, "b1": 2, "b2": 3, "c1": 4}

KANA = re.compile(r"^[ぁ-ゟ゠-ヿー]+$")
WORD = re.compile(r"^[ぁ-ゟ゠-ヿー一-鿿々]+$")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "FutureVoice", "Resources")

# JMdict ke_inf values that mean "this kanji form is not how the word is
# written" — with the usually-kana flag, that is a kana headword.
UNWRITTEN = {
    "rarely used kanji form", "ateji (phonetic) reading",
    "search-only kanji form", "word containing irregular kanji usage",
}
# The kanji is fine, the okurigana isn't (下る for さがる): take JMdict's
# first form instead of the deck's.
IRREGULAR_OKURIGANA = "irregular okurigana usage"

# Deck spellings (headword, reading) whose headword becomes the kana — or
# the given spelling — because that is how the word is met in the wild.
# Hand-reviewed, see the docstring. A different reading of the same kanji
# (打つ/うつ beside 打つ/ぶつ) is untouched, which is why the reading is
# part of the key.
KANA_HEADWORDS = {
    # N5
    ("余り", "あまり"), ("在る", "ある"), ("有る", "ある"), ("嫌", "いや"),
    ("要る", "いる"), ("色々", "いろいろ"), ("美味しい", "おいしい"),
    ("叔父さん", "おじさん"), ("伯父さん", "おじさん"),
    ("伯母さん", "おばさん"), ("叔母さん", "おばさん"),
    ("綺麗", "きれい"), ("下さい", "ください"), ("沢山", "たくさん"),
    ("段々", "だんだん"), ("所", "ところ"), ("無くす", "なくす"),
    ("温い", "ぬるい"), ("片仮名", "かたかな"), ("平仮名", "ひらがな"),
    ("御飯", "ごはん"), ("朝御飯", "あさごはん"), ("昼御飯", "ひるごはん"),
    ("晩御飯", "ばんごはん"),
    # N4
    ("大抵", "たいてい"), ("致す", "いたす"), ("無くなる", "なくなる"),
    ("事", "こと"), ("内", "うち"), ("凄い", "すごい"), ("一杯", "いっぱい"),
    ("中々", "なかなか"), ("随分", "ずいぶん"), ("為", "ため"),
    ("大体", "だいたい"), ("様", "よう"), ("程", "ほど"), ("お陰", "おかげ"),
    ("大分", "だいぶ"),
    # N3
    ("更に", "さらに"), ("既に", "すでに"), ("精々", "せいぜい"),
    ("粗", "あら"), ("或", "ある"), ("従兄弟", "いとこ"), ("従姉妹", "いとこ"),
    ("否", "いや"), ("言わば", "いわば"), ("恐らく", "おそらく"),
    ("お洒落", "おしゃれ"), ("お喋り", "おしゃべり"), ("罹る", "かかる"),
    ("掻く", "かく"), ("可愛そう", "かわいそう"), ("咥える", "くわえる"),
    ("極", "ごく"), ("塵", "ごみ"), ("注す", "さす"), ("寧ろ", "むしろ"),
    ("止す", "よす"), ("僅か", "わずか"), ("偶", "たま"), ("遂に", "ついに"),
    ("繋がる", "つながる"), ("繋ぐ", "つなぐ"), ("繋げる", "つなげる"),
    ("何で", "なんで"), ("何でも", "なんでも"), ("何とか", "なんとか"),
    ("無し", "なし"), ("生る", "なる"), ("退く", "どく"), ("蒔く", "まく"),
    ("撒く", "まく"), ("捲る", "めくる"), ("振り", "ふり"), ("埃", "ほこり"),
    ("紐", "ひも"),
    # N2
    ("有難い", "ありがたい"), ("一旦", "いったん"), ("お代わり", "おかわり"),
    ("小父さん", "おじさん"), ("小母さん", "おばさん"), ("却って", "かえって"),
    ("括弧", "かっこ"), ("剃刀", "かみそり"), ("屑", "くず"), ("擦る", "こする"),
    ("御免", "ごめん"), ("御覧", "ごらん"), ("囁く", "ささやく"), ("匙", "さじ"),
    ("流石", "さすが"), ("萎む", "しぼむ"), ("折角", "せっかく"),
    ("台詞", "せりふ"), ("逸れる", "それる"), ("算盤", "そろばん"),
    ("大層", "たいそう"), ("大分", "だいぶん"), ("但し", "ただし"),
    ("繋がり", "つながり"), ("躓く", "つまずく"), ("所々", "ところどころ"),
    ("為す", "なす"), ("謎謎", "なぞなぞ"), ("俄", "にわか"), ("捩る", "ねじる"),
    ("梯子", "はしご"), ("始めに", "はじめに"), ("初めに", "はじめに"),
    ("跨ぐ", "またぐ"), ("間も無く", "まもなく"), ("間もなく", "まもなく"),
    ("稀", "まれ"), ("銘々", "めいめい"), ("面倒臭い", "めんどうくさい"),
    ("元々", "もともと"), ("物凄い", "ものすごい"), ("喧しい", "やかましい"),
    ("火傷", "やけど"), ("余所", "よそ"), ("煉瓦", "れんが"),
    ("振り仮名", "ふりがな"),
    # N1
    ("到底", "とうてい"), ("乃至", "ないし"), ("詰る", "なじる"),
    ("懐く", "なつく"), ("何だか", "なんだか"), ("にも関わらず", "にもかかわらず"),
    ("未だ", "いまだ"), ("嫌々", "いやいや"), ("団扇", "うちわ"),
    ("雄", "おす"), ("雌", "めす"), ("自ずから", "おのずから"),
    ("駆けっこ", "かけっこ"), ("微か", "かすか"), ("擦る", "かする"),
    ("傍ら", "かたわら"), ("且つ", "かつ"), ("金槌", "かなづち"),
    ("予て", "かねて"), ("庇う", "かばう"), ("気障", "きざ"), ("嘴", "くちばし"),
    ("敢えて", "あえて"), ("悪しからず", "あしからず"), ("予め", "あらかじめ"),
    ("霰", "あられ"), ("濯ぐ", "すすぐ"), ("濯ぐ", "ゆすぐ"), ("伜", "せがれ"),
    ("素っ気無い", "そっけない"), ("聳える", "そびえる"), ("辿る", "たどる"),
    ("弛み", "たるみ"), ("弛む", "たるむ"), ("畜生", "ちくしょう"),
    ("塵取り", "ちりとり"), ("突っ突く", "つっつく"), ("呟く", "つぶやく"),
    ("壷", "つぼ"), ("藁", "わら"), ("捗る", "はかどる"), ("剥げる", "はげる"),
    ("裸足", "はだし"), ("蜂蜜", "はちみつ"), ("躾", "しつけ"),
    ("躾ける", "しつける"), ("淑やか", "しとやか"), ("萎びる", "しなびる"),
    ("砂利", "じゃり"), ("耽る", "ふける"), ("惚ける", "ぼける"),
    ("綻びる", "ほころびる"), ("賄う", "まかなう"), ("纏まり", "まとまり"),
    ("見なす", "みなす"), ("斑", "むら"), ("目途", "めど"), ("専ら", "もっぱら"),
    ("脆い", "もろい"), ("奴", "やつ"), ("故", "ゆえ"), ("良し", "よし"),
    ("余程", "よほど"), ("遥か", "はるか"), ("一頃", "ひところ"), ("雛", "ひな"),
}
# …and the few whose everyday spelling is not the plain hiragana reading.
SPELLED = {
    ("片仮名", "かたかな"): "カタカナ", ("台詞", "せりふ"): "セリフ",
    ("面倒臭い", "めんどうくさい"): "面倒くさい", ("煉瓦", "れんが"): "レンガ",
    ("雄", "おす"): "オス", ("雌", "めす"): "メス",
    ("御飯", "ごはん"): "ご飯", ("朝御飯", "あさごはん"): "朝ご飯",
    ("昼御飯", "ひるごはん"): "昼ご飯", ("晩御飯", "ばんごはん"): "晩ご飯",
}


def fetch(url, src, name):
    if src:
        return open(os.path.join(src, name), "rb").read()
    return urllib.request.urlopen(url).read()


def load_jmdict(src):
    """kanji form -> [entry], reading -> [entry]."""
    raw = fetch(JMDICT, src, "JMdict_e.gz")
    root = ET.fromstring(gzip.decompress(raw))
    by_kanji, by_reading = defaultdict(list), defaultdict(list)
    for e in root.iter("entry"):
        ks = [k.findtext("keb") for k in e.findall("k_ele")]
        entry = {
            "ks": ks,
            "kinfo": {k.findtext("keb"): {i.text for i in k.findall("ke_inf")}
                      for k in e.findall("k_ele")},
            "rs": [r.findtext("reb") for r in e.findall("r_ele")],
            "uk": any(m.text == "word usually written using kana alone"
                      for s in e.findall("sense") for m in s.findall("misc")),
        }
        for k in ks:
            by_kanji[k].append(entry)
        for r in entry["rs"]:
            by_reading[r].append(entry)
    return by_kanji, by_reading


def deck_rows(src):
    for n in LEVELS:
        text = fetch(DECK.format(n), src, f"n{n}.csv").decode("utf-8")
        for r in csv.DictReader(io.StringIO(text)):
            heads = [p.strip() for p in r["expression"].split(";") if p.strip()]
            reads = [p.strip() for p in r["reading"].split(";") if p.strip()]
            for i, head in enumerate(heads):
                # Pair alternatives positionally when both sides split the
                # same way (いい; よい / いい; よい); otherwise the first
                # reading belongs to every spelling (足; 脚 / あし).
                reading = reads[i] if len(reads) == len(heads) else (reads[0] if reads else head)
                yield LEVELS[n], head, reading


def entry_for(head, reading, by_kanji, by_reading):
    cands = by_reading.get(head, []) if KANA.match(head) else by_kanji.get(head, [])
    if not KANA.match(head):
        cands = [c for c in cands if reading in c["rs"]] or cands
    return cands[0] if cands else None


def canonical(head, reading, entry):
    """The spelling the learner sees for this deck row."""
    if (head, reading) in KANA_HEADWORDS:
        return SPELLED.get((head, reading), reading)
    if entry is None or KANA.match(head):
        return head
    tags = entry["kinfo"].get(head, set())
    if IRREGULAR_OKURIGANA in tags and entry["ks"]:
        return entry["ks"][0]
    if tags & UNWRITTEN:
        # Nobody writes this form. Kana if the word is usually kana; else
        # the spelling JMdict lists first (朝御飯 → 朝ごはん).
        return reading if entry["uk"] or not entry["ks"] else entry["ks"][0]
    # Same kanji, older okurigana (落着く, 終る, 曲る, 入口): JMdict's first
    # form is the one written today. Different kanji (貼る/張る, 速い/早い)
    # is a different choice, and the deck's stands.
    first = entry["ks"][0] if entry["ks"] else head
    if first != head and kanji_in(first) == kanji_in(head):
        return first
    return head


def kanji_in(s):
    return {c for c in s if "\u4e00" <= c <= "\u9fff"}


def safe_form(alt, entry):
    """A spelling worth mapping. Short kana are what inflection looks like
    (てる, ます, で), so a one-kana form is never kept and a two-kana one only
    for a word that is itself usually written in kana."""
    if not KANA.match(alt):
        return True
    if len(alt) <= 1:
        return False
    if len(alt) == 2:
        return bool(entry and entry["uk"])
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    args = ap.parse_args()
    by_kanji, by_reading = load_jmdict(args.src)

    level_of = {}                 # canonical -> level
    readings_of = defaultdict(list)  # canonical -> kana readings, easiest level first
    forms = defaultdict(set)      # spelling -> {canonical}
    dropped = 0
    for level, head, reading in deck_rows(args.src):
        if not WORD.match(head):  # affixes (～円, お～) are grammar, not words
            dropped += 1
            continue
        entry = entry_for(head, reading, by_kanji, by_reading)
        canon = canonical(head, reading, entry)
        if canon not in level_of or RANK[level] < RANK[level_of[canon]]:
            level_of[canon] = level
        if KANA.match(reading) and reading != canon:
            # Easiest level first; within a level, JMdict's own order, which
            # puts the common reading first (日本: にほん before にっぽん).
            order = entry["rs"].index(reading) if entry and reading in entry["rs"] else 99
            readings_of[canon].append((RANK[level], order, reading))
        for alt in {head, reading} | (set(entry["ks"]) | set(entry["rs"]) if entry else set()):
            if alt != canon and WORD.match(alt) and safe_form(alt, entry):
                forms[alt].add(canon)

    # A line without a tab is skipped by both loaders, which is where the
    # attribution the licences ask for lives — there is no credits screen.
    credit = ("# Japanese wordlist. JLPT N5–N1 vocabulary by Jonathan Waller "
              "(tanos.co.uk, CC BY 4.0) via open-anki-jlpt-decks (MIT); "
              "spellings settled with JMdict (EDRDG, CC BY-SA 4.0). "
              "Built by scripts/build-ja-wordlist.py.\n")
    words = sorted(level_of.items(), key=lambda kv: (RANK[kv[1]], kv[0]))
    with open(os.path.join(OUT, "cefr_words_ja.tsv"), "w", encoding="utf-8") as f:
        f.write(credit)
        for head, level in words:
            seen, ordered = set(), []
            for _, _, r in sorted(readings_of[head]):
                if r not in seen:
                    seen.add(r)
                    ordered.append(r)
            reading = "・".join(ordered) if not KANA.match(head) else ""
            f.write(f"{head}\t{level}\t{reading}\n" if reading else f"{head}\t{level}\n")

    kept = sorted((alt, next(iter(c))) for alt, c in forms.items()
                  if len(c) == 1 and alt not in level_of)
    with open(os.path.join(OUT, "ja_forms.tsv"), "w", encoding="utf-8") as f:
        f.write(credit)
        for alt, head in kept:
            f.write(f"{alt}\t{head}\n")

    by_level = defaultdict(int)
    for _, level in words:
        by_level[level] += 1
    ambiguous = sum(1 for c in forms.values() if len(c) > 1)
    print(f"{len(words)} headwords {dict(by_level)} · {len(kept)} forms "
          f"({ambiguous} ambiguous spellings left out) · {dropped} affix entries dropped",
          file=sys.stderr)


if __name__ == "__main__":
    main()

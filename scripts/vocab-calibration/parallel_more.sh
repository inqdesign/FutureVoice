#!/bin/bash
# Tatoeba en–ko / en–ja / en–es / en–fr pairs read exactly as the phone reads them,
# for parallel_cuts_more.py. Compiles the app's own KoreanMorph, JapaneseMorph,
# SpanishMorph, FrenchMorph, WordClass and VocabSophistication (copied, bundle lookups
# pointed at FutureVoice/Resources) with small stand-ins for the rest; the
# English side is NLTagger lemma|Class, as parallel_pairs.swift writes it.
#
# Inputs (CC BY 2.0 FR) from https://downloads.tatoeba.org/exports/per_language/,
# decompressed side by side in ONE directory: eng_sentences.tsv (from eng/),
# kor_sentences.tsv + kor-eng_links.tsv (kor/), jpn_sentences.tsv +
# jpn-eng_links.tsv (jpn/), spa_sentences.tsv + spa-eng_links.tsv (spa/),
# fra_sentences.tsv + fra-eng_links.tsv (fra/);
# ~150 MB in all. Needs the profiles from VocabSophistication.swift in place.
#
# usage: [LANGS="fr"] scripts/vocab-calibration/parallel_more.sh <tatoeba dir> <out dir>
#   writes <out dir>/pairs_{ko,ja,es,fr}.tsv (ja, es and fr take a few minutes each)
# then:  python3 scripts/vocab-calibration/parallel_cuts_more.py FutureVoice/Resources \
#            FutureVoice/Services/VocabSophistication.swift ko <out dir>/pairs_ko.tsv
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$(cd "$1" && pwd)"; mkdir -p "$2"; OUT="$(cd "$2" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
for f in KoreanMorph JapaneseMorph SpanishMorph FrenchMorph WordClass VocabSophistication; do
  sed -e 's/Bundle\.main\.url(forResource: /resURL(/' -e 's/, withExtension: "tsv")/)/' \
    "$REPO/FutureVoice/Services/$f.swift" > "$WORK/$f.swift"
done
cat > "$WORK/Stubs.swift" <<'SWIFT'
import Foundation
import NaturalLanguage
// Stand-ins for the app types the copied files touch. Levels and the pool
// come from the same TSVs the app bundles.
var RES = ""
var ACTIVE = "ko"
func resURL(_ name: String) -> URL? {
    let p = RES + "/" + name + ".tsv"
    return FileManager.default.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
}
enum CEFRLevel: String, CaseIterable { case a1, a2, b1, b2, c1, c2 }
enum LanguageCatalog {
    struct L { let code: String }
    static func language(_ c: String) -> L? { L(code: base(c)) }
    static func base(_ c: String) -> String { String(c.split(separator: "-").first ?? Substring(c)) }
}
final class TextMemo<Value>: @unchecked Sendable {
    private var table: [String: Value] = [:]
    init(cap: Int = 8000) {}
    func value(for text: String, language: NLLanguage, compute: () -> Value) -> Value {
        let k = language.rawValue + "\u{1}" + text
        if let h = table[k] { return h }
        let v = compute(); table[k] = v; return v
    }
}
enum CoreVocabulary {
    static var levelByWord: [String: CEFRLevel] = [:]
    static var set: Set<String> = []
    static var morphRank: [String: Int] = [:]
    static func load(_ code: String) {
        let file = code == "en" ? "cefr_words" : "cefr_words_\(code)"
        levelByWord = [:]
        for line in (try! String(contentsOf: resURL(file)!, encoding: .utf8)).split(whereSeparator: \.isNewline) {
            let p = line.split(separator: "\t")
            guard p.count >= 2, let l = CEFRLevel(rawValue: p[1].lowercased()) else { continue }
            let w = String(p[0]).lowercased()
            if levelByWord[w] == nil { levelByWord[w] = l }
        }
        set = Set(levelByWord.keys)
        if code == "ko", let u = resURL("ko_morph_rank") {
            for line in (try! String(contentsOf: u, encoding: .utf8)).split(whereSeparator: \.isNewline) {
                let p = line.split(separator: "\t")
                guard p.count >= 2, let l = CEFRLevel(rawValue: p[1].lowercased()) else { continue }
                morphRank[String(p[0])] = levelRank(l)
            }
        }
    }
    static func level(of w: String) -> CEFRLevel? { levelByWord[w.lowercased()] }
    static func koreanRank(_ w: String) -> Int? { morphRank[w] ?? level(of: w).map(levelRank) }
    static func levelRank(_ l: CEFRLevel) -> Int { CEFRLevel.allCases.firstIndex(of: l) ?? 0 }
}
SWIFT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import NaturalLanguage
// usage: pairs <ko|ja|es|fr> <Resources dir> <tatoeba dir> <out.tsv>
// Writes: target id, English lemma|Class (NLTagger, as parallel_pairs.swift),
// the target's content headwords as VocabSophistication reads them on device
// (stop words NOT yet removed), English text, target text.
let a = CommandLine.arguments
let lang = a[1]; RES = a[2]; let dir = a[3]
ACTIVE = lang
CoreVocabulary.load(lang)
let t3 = ["ko": "kor", "ja": "jpn", "es": "spa", "fr": "fra"][lang]!
func read(_ p: String) -> String { String(decoding: FileManager.default.contents(atPath: p)!, as: UTF8.self) }
var tgt: [Substring: Substring] = [:], en: [Substring: Substring] = [:]
let tText = read("\(dir)/\(t3)_sentences.tsv"), links = read("\(dir)/\(t3)-eng_links.tsv")
for l in tText.split(separator: "\n") { let p = l.split(separator: "\t", maxSplits: 2); if p.count == 3 { tgt[p[0]] = p[2] } }
let pairs = links.split(separator: "\n").map { $0.split(separator: "\t") }.filter { $0.count == 2 }
var want = Set<Substring>(); for p in pairs { want.insert(p[1]) }
let enText = read("\(dir)/eng_sentences.tsv")
for l in enText.split(separator: "\n") { let p = l.split(separator: "\t", maxSplits: 2); if p.count == 3, want.contains(p[0]) { en[p[0]] = p[2] } }
let te = NLTagger(tagSchemes: [.lemma, .lexicalClass])
func lem(_ s: String) -> String {
    var o: [String] = []
    te.string = s; te.setLanguage(.english, range: s.startIndex..<s.endIndex)
    te.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace, .omitOther]) { cls, r in
        let tag = te.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0
        let w = (tag?.rawValue ?? String(s[r])).lowercased()
        if w.count > 1, w.rangeOfCharacter(from: .letters) != nil { o.append(w + "|" + (cls?.rawValue ?? "?")) }
        return true
    }
    return o.joined(separator: " ")
}
let reader: VocabSophistication.Reader = lang == "ko" ? .korean : lang == "ja" ? .japanese : lang == "fr" ? .french : .spanish
let profile = VocabSophistication.Profile(a2: 0, b1: 0, nativeLike: 0, reader: reader, stopWords: [])
let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
var seen = Set<Substring>(); var out = ""
for p in pairs {
    guard let t = tgt[p[0]], let e = en[p[1]], !seen.contains(p[0]) else { continue }
    seen.insert(p[0])
    let heads = VocabSophistication.contentLemmas(String(t), profile: profile, tagger: tagger, lexicon: CoreVocabulary.set)
    out += "\(p[0])\t\(lem(String(e)))\t\(heads.joined(separator: " "))\t\(e)\t\(t)\n"
}
FileManager.default.createFile(atPath: a[4], contents: out.data(using: .utf8))
SWIFT
(cd "$WORK" && swiftc -O -o pairs Stubs.swift KoreanMorph.swift JapaneseMorph.swift SpanishMorph.swift FrenchMorph.swift \
  WordClass.swift VocabSophistication.swift main.swift)
for l in ${LANGS:-ko ja es fr}; do
  "$WORK/pairs" "$l" "$REPO/FutureVoice/Resources" "$DATA" "$OUT/pairs_$l.tsv"
  echo "$OUT/pairs_$l.tsv: $(wc -l < "$OUT/pairs_$l.tsv") pairs"
done

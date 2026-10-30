// Tatoeba en–de pairs (CC BY 2.0 FR), every word as lemma|LexicalClass, for
// parallel_cuts.py. Inputs from https://downloads.tatoeba.org/exports/per_language/:
// de_src/deu_sentences.tsv, de_src/eng_sentences.tsv, de_src/deu-eng_links.tsv.
// usage: swift -O parallel_pairs.swift   (writes pairs_cls.tsv)
import Foundation
import NaturalLanguage
func read(_ p: String) -> String { String(decoding: FileManager.default.contents(atPath: p)!, as: UTF8.self) }
var de: [Substring: Substring] = [:], en: [Substring: Substring] = [:]
let deText = read("de_src/deu_sentences.tsv"), enText = read("de_src/eng_sentences.tsv"), links = read("de_src/deu-eng_links.tsv")
for l in deText.split(separator: "\n") { let p = l.split(separator: "\t", maxSplits: 2); if p.count == 3 { de[p[0]] = p[2] } }
var want = Set<Substring>()
let pairs = links.split(separator: "\n").map { $0.split(separator: "\t") }.filter { $0.count == 2 }
for p in pairs { want.insert(p[1]) }
for l in enText.split(separator: "\n") { let p = l.split(separator: "\t", maxSplits: 2); if p.count == 3, want.contains(p[0]) { en[p[0]] = p[2] } }
let te = NLTagger(tagSchemes: [.lemma, .lexicalClass]), td = NLTagger(tagSchemes: [.lemma, .lexicalClass])
func lem(_ s: String, _ t: NLTagger, _ lang: NLLanguage) -> String {
    var o: [String] = []
    t.string = s; t.setLanguage(lang, range: s.startIndex..<s.endIndex)
    t.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace, .omitOther]) { cls, r in
        let tag = t.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0
        let w = (tag?.rawValue ?? String(s[r])).lowercased()
        if w.count > 1, w.rangeOfCharacter(from: .letters) != nil { o.append(w + "|" + (cls?.rawValue ?? "?")) }
        return true
    }
    return o.joined(separator: " ")
}
var seen = Set<Substring>()
var out = ""
for p in pairs {
    guard let d = de[p[0]], let e = en[p[1]], !seen.contains(p[0]) else { continue }
    seen.insert(p[0])
    out += "\(p[0])\t\(lem(String(e), te, .english))\t\(lem(String(d), td, .german))\t\(e)\t\(d)\n"
}
FileManager.default.createFile(atPath: "pairs_cls.tsv", contents: out.data(using: .utf8))

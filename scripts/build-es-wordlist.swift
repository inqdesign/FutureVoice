// Builds FutureVoice/Resources/cefr_words_es.tsv + word_classes_es.tsv.
//
// No CEFR-graded Spanish list can ship in a paid app (ELELex, the only one,
// is CC BY-NC-SA), so the level is a FREQUENCY band — the same honest proxy
// the Korean list uses within its grades. Two corpora, because each alone is
// skewed: OpenSubtitles (spoken, but a crime drama's vocabulary — matar,
// policía, arma) and Tatoeba (everyday sentences, but a textbook's). A
// lemma's rank is the geometric mean of its ranks in the two.
//
// The headword is what Apple's NLTagger calls the lemma IN CONTEXT, because
// that is exactly what `VocabStore.lemmas(in:)` produces from a learner's
// speech at runtime; a dictionary's headword the tagger never emits would be
// a word nobody can ever be credited for. So every Tatoeba sentence is tagged
// whole, each surface form takes its majority lemma + class from those
// contexts, and the subtitle counts are carried through that map.
//
// Inputs (not committed — download into one directory):
//   es_50k.txt  github.com/hermitdave/FrequencyWords content/2018/es (CC BY-SA 4.0)
//   spa.tsv     downloads.tatoeba.org/exports/per_language/spa/spa_sentences.tsv.bz2 (CC BY 2.0 FR)
//
// On top of the frequency bands sits a hand-written A1/A2 core
// (scripts/es-core-a1a2.txt): a core word is graded no higher than its line
// says, because subtitles bury the calendar and the kitchen under police
// procedurals (diciembre came out B1, arma A1). Every headword must also pass
// macOS's Spanish spell checker, which is what keeps the tagger's invented
// lemmas out (abajar, from "abajo").
//
// Run: swift scripts/build-es-wordlist.swift <dir-with-inputs> FutureVoice/Resources

import Foundation
import NaturalLanguage
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: build-es-wordlist.swift <inputs> <out>"); exit(1) }
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])

let content: Set<String> = [NLTag.noun.rawValue, NLTag.verb.rawValue,
                            NLTag.adjective.rawValue, NLTag.adverb.rawValue]

// Left out ON PURPOSE (mirrors CoreVocabulary.ungradedByLanguage["es"]):
// auxiliaries, modals, quantifiers and indefinites a tagger still calls
// content words, and spoken fillers.
let ungraded: Set<String> = [
    "ser", "estar", "haber", "tener", "ir", "hacer", "poder", "deber", "querer", "soler",
    "mucho", "poco", "tanto", "otro", "todo", "nada", "algo", "alguien", "nadie",
    "cada", "mismo", "tal", "más", "menos", "muy", "así", "también", "tampoco",
    "sí", "no", "ya", "bueno", "vale", "eh", "em", "este", "pues", "oye", "mira",
    "okay", "ok", "hola", "adiós", "gracias", "tan",
]

// Not Spanish words, or not words: English that slipped through subtitles
// (dog, bro), interjections a tagger files as nouns (hmm, shh), and the
// tagger's own fragments (huí, dan, cha). Found reading the output.
let junk: Set<String> = [
    "hey", "bah", "hmm", "shh", "ups", "boy", "dog", "cat", "bro", "per", "pos",
    "non", "gil", "cha", "dan", "huí", "mas", "ton", "pro", "app", "bug",
]

// Tagger slips found reading the output; the in-context majority still
// lands on a wrong lemma for these few.
let fixes: [String: String] = ["podar": "poder"]

struct Seen { var lemmas: [String: Int] = [:]; var classes: [String: Int] = [:]; var midCaps = 0; var total = 0 }
var byForm: [String: Seen] = [:]
var tatoebaLemmaCount: [String: Int] = [:]

// MARK: Tatoeba, in context
let tsv = try String(contentsOf: inDir.appendingPathComponent("spa.tsv"), encoding: .utf8)
let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass, .nameType])
var n = 0
for line in tsv.split(separator: "\n") {
    let cols = line.split(separator: "\t", maxSplits: 2)
    guard cols.count == 3 else { continue }
    let s = String(cols[2])
    tagger.string = s
    tagger.setLanguage(.spanish, range: s.startIndex..<s.endIndex)
    var first = true
    tagger.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .lexicalClass,
                         options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
        let surface = String(s[range])
        let form = surface.lowercased()
        var seen = byForm[form, default: Seen()]
        seen.total += 1
        if !first, surface.first?.isUppercase == true { seen.midCaps += 1 }
        first = false
        let name = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType).0
        let cls = (name != nil && name != .otherWord) ? "Name" : (tag?.rawValue ?? "Other")
        seen.classes[cls, default: 0] += 1
        let lemma = (tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? form).lowercased()
        seen.lemmas[lemma, default: 0] += 1
        byForm[form] = seen
        tatoebaLemmaCount[lemma, default: 0] += 1
        return true
    }
    n += 1
    if n % 50000 == 0 { FileHandle.standardError.write("tagged \(n)\n".data(using: .utf8)!) }
}

func majority(_ d: [String: Int]) -> String? { d.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key }

// A form read out of context, for subtitle words Tatoeba never used.
let lone = NLTagger(tagSchemes: [.lemma, .lexicalClass])
func standalone(_ w: String) -> (String, String) {
    lone.string = w
    lone.setLanguage(.spanish, range: w.startIndex..<w.endIndex)
    let l = lone.tag(at: w.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased() ?? w
    let c = lone.tag(at: w.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue ?? "Other"
    return (l, c)
}

// MARK: subtitles, through the map
var subsLemmaCount: [String: Int] = [:]
var lemmaClass: [String: [String: Int]] = [:]
let subs = try String(contentsOf: inDir.appendingPathComponent("es_50k.txt"), encoding: .utf8)
for line in subs.split(separator: "\n") {
    let parts = line.split(separator: " ")
    guard parts.count == 2, let count = Int(parts[1]) else { continue }
    let form = String(parts[0]).lowercased()
    guard form.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { continue }
    var lemma: String, cls: String
    if let seen = byForm[form], seen.total >= 2 {
        // Capitalized mid-sentence most of the time = a name (Tom, María).
        if seen.midCaps * 2 > seen.total { continue }
        lemma = majority(seen.lemmas) ?? form
        cls = majority(seen.classes) ?? "Other"
    } else {
        (lemma, cls) = standalone(form)
    }
    lemma = fixes[lemma] ?? lemma
    subsLemmaCount[lemma, default: 0] += count
    lemmaClass[lemma, default: [:]][cls, default: 0] += count
}

// MARK: rank
func ranks(_ d: [String: Int]) -> [String: Int] {
    var r: [String: Int] = [:]
    for (i, kv) in d.sorted(by: { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }).enumerated() { r[kv.key] = i + 1 }
    return r
}
let rs = ranks(subsLemmaCount), rt = ranks(tatoebaLemmaCount)
let subsForms: Set<String> = Set(subs.split(separator: "\n").compactMap { $0.split(separator: " ").first.map { String($0).lowercased() } })

let speller = NSSpellChecker.shared
func spelledRight(_ w: String) -> Bool {
    speller.checkSpelling(of: w, startingAt: 0, language: "es", wrap: false,
                          inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
}

var candidates: [String: (score: Double, cls: String)] = [:]
for (lemma, subsRank) in rs {
    guard lemma.count >= 3,
          lemma.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
          !ungraded.contains(lemma), !junk.contains(lemma),
          let cls = majority(lemmaClass[lemma] ?? [:]), content.contains(cls),
          let tatRank = rt[lemma], (tatoebaLemmaCount[lemma] ?? 0) >= 3,   // a real lemma, seen in context
          subsForms.contains(lemma),                                        // and said as itself
          spelledRight(lemma)
    else { continue }
    // A verb lemma is an infinitive; anything else is the tagger giving up
    // on a gerund or a participle ("repitiendo").
    if cls == NLTag.verb.rawValue,
       !["ar", "er", "ir", "ír", "se"].contains(where: { lemma.hasSuffix($0) }) { continue }
    // Tatoeba weighs a little more: subtitles are spoken, but they are
    // crime and romance; Tatoeba is the everyday.
    candidates[lemma] = (pow(Double(subsRank), 0.4) * pow(Double(tatRank), 0.6), cls)
}
// One headword per word: a reflexive (comerse) folds into its verb, a
// feminine adjective (cansada) into its masculine, when both are here. Only
// adjectives: for nouns -a and -o are usually two words (casa/caso,
// puerta/puerto, cuenta/cuento). `merged` carries the fold to the form table.
var merged: [String: String] = [:]
for lemma in Array(candidates.keys) {
    guard let gone = candidates[lemma] else { continue }
    var base: String?
    if lemma.hasSuffix("se"), gone.cls == NLTag.verb.rawValue { base = String(lemma.dropLast(2)) }
    else if lemma.hasSuffix("a"), gone.cls == NLTag.adjective.rawValue { base = String(lemma.dropLast()) + "o" }
    if let b = base, let kept = candidates[b] {
        candidates[b] = (min(kept.score, gone.score), kept.cls)
        candidates[lemma] = nil
        merged[lemma] = b
    }
}
// The tagger also emits a reflexive lemma for a verb whose plain form made
// the list on its own ("comí" after "me" → comerse): fold every one.
for lemma in rs.keys where lemma.hasSuffix("se") {
    let b = String(lemma.dropLast(2))
    if candidates[b] != nil, candidates[lemma] == nil { merged[lemma] = b }
}

// The hand core, normalized through the same tagger so it says what speech says.
var coreLevel: [String: String] = [:]
let coreText = try String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().appendingPathComponent("es-core-a1a2.txt"), encoding: .utf8)
for line in coreText.split(separator: "\n") where !line.hasPrefix("#") {
    let p = line.split(separator: "\t")
    guard p.count == 2 else { continue }
    // The word's own in-context lemma first: out of context the tagger
    // reads "marido" as a form of "maridar".
    let word = String(p[0])
    let (lone, cls) = standalone(word)
    let lemma = byForm[word].flatMap { majority($0.lemmas) } ?? lone
    let level = String(p[1])
    if let have = coreLevel[lemma], have <= level { continue }
    coreLevel[lemma] = level
    if candidates[lemma] == nil {
        let c = content.contains(cls) ? cls : NLTag.noun.rawValue
        candidates[lemma] = (.infinity, c)
    }
}
var scored = candidates.map { ($0.key, $0.value.score, $0.value.cls) }
scored.sort { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }

// Band sizes follow the English list's shape (cefr_words.tsv).
let bands: [(String, Int)] = [("A1", 900), ("A2", 1200), ("B1", 2100), ("B2", 2400), ("C1", 900), ("C2", 800)]
var rows: [(String, String, String)] = []
var i = 0
let order = bands.map(\.0)
for (band, size) in bands {
    for (lemma, _, cls) in scored[i..<min(i + size, scored.count)] {
        // The core caps the level; never raises it.
        var level = band
        if let cap = coreLevel[lemma], order.firstIndex(of: cap)! < order.firstIndex(of: band)! { level = cap }
        rows.append((lemma, level, cls))
    }
    i += size
    if i >= scored.count { break }
}
// Core words the bands never reached (the .infinity scores past the end).
let placed = Set(rows.map(\.0))
for (lemma, level) in coreLevel where !placed.contains(lemma) {
    rows.append((lemma, level, candidates[lemma]?.cls ?? NLTag.noun.rawValue))
}

let header = "# Spanish wordlist. Levels are frequency bands under a hand-written A1/A2 core, not CEFR judgments: lemmas ranked by the geometric mean of their rank in OpenSubtitles 2018 (FrequencyWords by Hermit Dave, CC BY-SA 4.0) and in Tatoeba (CC BY 2.0 FR), lemmatized in context by Apple NLTagger. Built by scripts/build-es-wordlist.swift.\n"
var words = header, classes = "# Word classes for cefr_words_es.tsv, the majority NLTagger class of each lemma in context. Built by scripts/build-es-wordlist.swift.\n"
let classWord = [NLTag.noun.rawValue: "noun", NLTag.verb.rawValue: "verb",
                 NLTag.adjective.rawValue: "adjective", NLTag.adverb.rawValue: "adverb"]
for band in bands.map(\.0) {
    for r in rows.filter({ $0.1 == band }).sorted(by: { $0.0 < $1.0 }) {
        words += "\(r.0)\t\(r.1)\n"
        classes += "\(r.0)\t\(classWord[r.2]!)\n"
    }
}
try words.write(to: outDir.appendingPathComponent("cefr_words_es.tsv"), atomically: true, encoding: .utf8)
try classes.write(to: outDir.appendingPathComponent("word_classes_es.tsv"), atomically: true, encoding: .utf8)

// MARK: forms
// iOS ships no Spanish lemma model (measured 2026-10-15: NLTagger on the
// simulator returns nil for every word, and requestAssets has none to
// download), so the app cannot do on a phone what this script did on a Mac.
// It reads this table instead (`SpanishMorph`): every content-word form seen
// in either corpus, with the lemma it took in context and its class. A form
// not in the table is its own lemma and has no class.
var forms = "# Spanish surface forms → headword + class, for SpanishMorph (iOS has no Spanish lemmatizer). Built by scripts/build-es-wordlist.swift from the same corpora as cefr_words_es.tsv.\n"
var formRows: [String: (String, String)] = [:]
func addForm(_ form: String, _ rawLemma: String, _ cls: String) {
    guard content.contains(cls), form.count >= 2,
          form.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return }
    var lemma = fixes[rawLemma] ?? rawLemma
    lemma = merged[lemma] ?? lemma
    guard lemma.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return }
    formRows[form] = (lemma, classWord[cls]!)
}
for line in subs.split(separator: "\n") {
    guard let f = line.split(separator: " ").first else { continue }
    let form = String(f).lowercased()
    if let seen = byForm[form], seen.total >= 2 {
        if seen.midCaps * 2 > seen.total { continue }
        addForm(form, majority(seen.lemmas) ?? form, majority(seen.classes) ?? "Other")
    } else {
        let (l, c) = standalone(form)
        addForm(form, l, c)
    }
}
for (form, seen) in byForm where formRows[form] == nil && seen.total >= 2 && seen.midCaps * 2 <= seen.total {
    addForm(form, majority(seen.lemmas) ?? form, majority(seen.classes) ?? "Other")
}
// Every headword resolves to itself with its own class, whatever its forms said.
for r in rows { formRows[r.0] = (r.0, classWord[r.2]!) }
for form in formRows.keys.sorted() {
    let (lemma, cls) = formRows[form]!
    forms += lemma == form ? "\(form)\t\t\(cls)\n" : "\(form)\t\(lemma)\t\(cls)\n"
}
try forms.write(to: outDir.appendingPathComponent("es_forms.tsv"), atomically: true, encoding: .utf8)
print("wrote \(formRows.count) forms")
print("wrote \(rows.count) headwords")

// Inflected form → headword, and the headwords that are not content words,
// for a language Android has no tagger for — decided by the SAME tagger iOS
// asks at runtime (NLTagger `.lemma` / `.lexicalClass`), so both apps agree
// on what a word is.
//
//   swift scripts/android/gen-forms.swift en
//
// Reads  android/app/src/main/assets/wordlists/cefr_words.tsv (headwords)
// Writes android/app/src/main/assets/wordlists/en_forms.tsv   form<TAB>headword
//
// Forms are CANDIDATES built by spelling rules plus an irregular table, and a
// candidate is kept only when the tagger lemmatizes it to that headword — the
// rules propose, NLTagger decides. A candidate that is itself a headword is
// skipped: "abandoned" is its own B2 entry, not a form of "abandon".
//
// No closed-class list comes out of this: a word tagged ALONE is labelled
// Interjection for ~1,170 plain content words (measured — "abandon",
// "accountant"), so the tagger's class can't be trusted without context.
// Closed classes stay the hand list in `CoreVocabulary.ungradedByLanguage`.
import Foundation
import NaturalLanguage

let lang = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "en"
guard lang == "en" else { fatalError("only en is generated so far") }
let dir = URL(fileURLWithPath: "android/app/src/main/assets/wordlists")
let source = try! String(contentsOf: dir.appendingPathComponent("cefr_words.tsv"), encoding: .utf8)
let heads: [String] = source.split(separator: "\n").compactMap { line in
    let cols = line.split(separator: "\t")
    return cols.count >= 2 ? String(cols[0]).lowercased() : nil
}
let headSet = Set(heads)

let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
/// The tag of `word` inside `carrier` (where `_` stands for it). A word alone
/// is mostly tagged OtherWord with no lemma; a short sentence gives the tagger
/// the context it has at runtime on iOS.
func tag(_ word: String, in carrier: String = "_") -> (lemma: String?, cls: NLTag?) {
    let s = carrier.replacingOccurrences(of: "_", with: word)
    tagger.string = s
    tagger.setLanguage(.english, range: s.startIndex..<s.endIndex)
    guard let r = s.range(of: word) else { return (nil, nil) }
    let lemma = tagger.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
    let cls = tagger.tag(at: r.lowerBound, unit: .word, scheme: .lexicalClass).0
    return (lemma, cls)
}
/// A form is kept when ANY carrier lemmatizes it to the headword: one reads
/// it as a noun, one as a verb, one as an adjective.
let carriers = ["I saw the _ yesterday.", "They _ every day.", "We were _ it.", "It is _ than before.", "_"]
func lemma(of form: String) -> Set<String> {
    Set(carriers.compactMap { tag(form, in: $0).lemma })
}

let vowels = Set("aeiou")
func isVowel(_ c: Character) -> Bool { vowels.contains(c) }
func candidates(_ w: String) -> Set<String> {
    var out = Set<String>()
    let chars = Array(w)
    guard chars.count >= 2, w.allSatisfy({ $0.isLetter }) else { return out }
    let last = chars[chars.count - 1], prev = chars[chars.count - 2]
    // -s / -es / -ies
    if last == "y" && !isVowel(prev) { out.insert(String(w.dropLast()) + "ies") }
    else if w.hasSuffix("s") || w.hasSuffix("x") || w.hasSuffix("z") || w.hasSuffix("ch")
                || w.hasSuffix("sh") || w.hasSuffix("o") { out.insert(w + "es") }
    else { out.insert(w + "s") }
    if w.hasSuffix("f") { out.insert(String(w.dropLast()) + "ves") }
    if w.hasSuffix("fe") { out.insert(String(w.dropLast(2)) + "ves") }
    // -ed / -ing / -er / -est
    let doubled = chars.count >= 3 && !isVowel(last) && isVowel(prev) && !isVowel(chars[chars.count - 3])
        && !"wxy".contains(last)
    if last == "e" {
        out.insert(w + "d"); out.insert(String(w.dropLast()) + "ing")
        out.insert(w + "r"); out.insert(w + "st")
    } else if last == "y" && !isVowel(prev) {
        out.insert(String(w.dropLast()) + "ied"); out.insert(w + "ing")
        out.insert(String(w.dropLast()) + "ier"); out.insert(String(w.dropLast()) + "iest")
    } else {
        out.insert(w + "ed"); out.insert(w + "ing"); out.insert(w + "er"); out.insert(w + "est")
        if doubled {
            let d = w + String(last)
            out.insert(d + "ed"); out.insert(d + "ing"); out.insert(d + "er"); out.insert(d + "est")
        }
    }
    if w.hasSuffix("ie") { out.insert(String(w.dropLast(2)) + "ying") }
    return out
}

// Irregular forms spelling rules can't reach. The tagger still decides.
let irregular: [String: [String]] = [
    "be": ["am", "is", "are", "was", "were", "been", "being"], "have": ["has", "had", "having"],
    "do": ["does", "did", "done", "doing"], "go": ["goes", "went", "gone", "going"],
    "get": ["got", "gotten", "getting"], "make": ["made"], "say": ["said"], "see": ["saw", "seen"],
    "come": ["came"], "take": ["took", "taken"], "know": ["knew", "known"], "think": ["thought"],
    "give": ["gave", "given"], "find": ["found"], "tell": ["told"], "become": ["became"],
    "leave": ["left"], "feel": ["felt"], "bring": ["brought"], "begin": ["began", "begun"],
    "keep": ["kept"], "hold": ["held"], "write": ["wrote", "written"], "stand": ["stood"],
    "hear": ["heard"], "let": ["letting"], "mean": ["meant"], "set": ["setting"], "meet": ["met"],
    "run": ["ran"], "pay": ["paid"], "sit": ["sat"], "speak": ["spoke", "spoken"], "lie": ["lay", "lain", "lying"],
    "lead": ["led"], "read": ["reading"], "grow": ["grew", "grown"], "lose": ["lost"], "fall": ["fell", "fallen"],
    "send": ["sent"], "build": ["built"], "understand": ["understood"], "draw": ["drew", "drawn"],
    "break": ["broke", "broken"], "spend": ["spent"], "cut": ["cutting"], "rise": ["rose", "risen"],
    "drive": ["drove", "driven"], "buy": ["bought"], "wear": ["wore", "worn"], "choose": ["chose", "chosen"],
    "seek": ["sought"], "throw": ["threw", "thrown"], "catch": ["caught"], "deal": ["dealt"],
    "win": ["won"], "forget": ["forgot", "forgotten"], "sell": ["sold"], "fight": ["fought"],
    "teach": ["taught"], "eat": ["ate", "eaten"], "sing": ["sang", "sung"], "drink": ["drank", "drunk"],
    "swim": ["swam", "swum"], "fly": ["flew", "flown", "flies"], "sleep": ["slept"], "wake": ["woke", "woken"],
    "ride": ["rode", "ridden"], "hide": ["hid", "hidden"], "bite": ["bit", "bitten"], "shake": ["shook", "shaken"],
    "steal": ["stole", "stolen"], "freeze": ["froze", "frozen"], "feed": ["fed"], "bleed": ["bled"],
    "fit": ["fitting"], "hang": ["hung"], "shoot": ["shot"], "shut": ["shutting"], "light": ["lit"],
    "stick": ["stuck"], "strike": ["struck"], "swing": ["swung"], "spin": ["spun"], "dig": ["dug"],
    "lend": ["lent"], "bend": ["bent"], "bet": ["betting"], "bind": ["bound"], "blow": ["blew", "blown"],
    "forgive": ["forgave", "forgiven"], "hit": ["hitting"], "hurt": ["hurting"], "quit": ["quitting"],
    "ring": ["rang", "rung"], "shine": ["shone"], "sink": ["sank", "sunk"], "slide": ["slid"],
    "tear": ["tore", "torn"], "undergo": ["underwent", "undergone"], "withdraw": ["withdrew", "withdrawn"],
    "arise": ["arose", "arisen"], "bear": ["bore", "born", "borne"], "overcome": ["overcame"],
    "good": ["better", "best"], "bad": ["worse", "worst"], "far": ["further", "furthest", "farther"],
    "child": ["children"], "man": ["men"], "woman": ["women"], "person": ["people"],
    "foot": ["feet"], "tooth": ["teeth"], "mouse": ["mice"], "life": ["lives"], "wife": ["wives"],
    "knife": ["knives"], "leaf": ["leaves"], "half": ["halves"], "shelf": ["shelves"],
]

var forms: [(String, String)] = []
var seen = Set<String>()
// The words the graded list leaves out ON PURPOSE (iOS `CoreVocabulary`
// ungraded set) get their forms too, so "going" and "went" resolve to a word
// the app already knows to skip instead of passing as new vocabulary.
let ungraded = ["be", "have", "do", "go", "will", "would", "shall", "should", "can", "could",
                "may", "might", "must", "get", "make", "say", "take", "come", "see", "know"]
for head in heads + ungraded.filter({ !headSet.contains($0) }) {
    var cands = candidates(head)
    for f in irregular[head] ?? [] { cands.insert(f) }
    for c in cands.sorted() where !headSet.contains(c) && !seen.contains(c) {
        if lemma(of: c).contains(head) { forms.append((c, head)); seen.insert(c) }
    }
}
let header = "# \(lang) forms: inflected form<TAB>headword. Generated by scripts/android/gen-forms.swift (NLTagger)."
try! ([header] + forms.map { "\($0.0)\t\($0.1)" }).joined(separator: "\n")
    .appending("\n").write(to: dir.appendingPathComponent("\(lang)_forms.tsv"), atomically: true, encoding: .utf8)
print("\(lang): \(heads.count) headwords · \(forms.count) forms")

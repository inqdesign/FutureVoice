import Foundation

/// Judging a sound by COMPARISON (2026-11-19).
///
/// Azure's score for a word ("how good was this, 0–100") cannot be held to a
/// bar outside English: on real native Korean (FLEURS, 1,087 words) a bar of
/// 50 let 951 of 1,087 wrong consonants pass, a bar of 85 failed one native
/// word in nine, and a native speaker was drilled on "예쁜" at 37. The
/// model's bias on a word is the same whatever it is told to expect, though,
/// so the same take is read twice: against the sentence as written and
/// against the sentence with the lesson's sound swapped for the one it is
/// confused with ("빵을" → "방을"). Whichever spelling scores higher on that
/// word is what was said. On the same 1,087 words: right 926, wrong 11, and
/// 150 within `margin` — too close to call, which passes. A take is never
/// failed on a guess.
///
/// Only sounds measured this way are offered (`isOffered`).
enum PronunciationContrast {
    /// A spelling must beat the other by more than this on the word. Per
    /// language, set where a native reading is almost never taken for the
    /// other sound: Korean 5, Spanish and French 10, Japanese and German 15
    /// (at 5 a native っ was "not yet" 9 times in 160, at 15 three).
    static func margin(locale: String) -> Int {
        switch locale.prefix(2) {
        case "ko": return 5
        case "ja", "de": return 15
        default: return 10
        }
    }
    static let maxAlternates = 2

    /// Topics judged by comparison. A topic is added once its own swap has
    /// been measured on native recordings.
    static func isOffered(topicId: String) -> Bool {
        swaps(topicId: topicId) != nil || wordRules(topicId: topicId) != nil
            || occurrenceRule(topicId: topicId) != nil || tone(topicId: topicId) != nil
    }

    /// The languages with at least one such topic.
    static func isOffered(language: String) -> Bool {
        ["ko", "es", "fr", "ja", "de", "zh"].contains(LanguageCatalog.base(language))
    }

    // MARK: - Spanish, French, German: a swap inside a word

    /// A spelling swap inside one word. `minLength` keeps it off the short
    /// function words it was not measured on.
    private struct WordRule {
        let pattern: String
        let template: String
        var minLength = 3
    }

    /// One list per alternate. Measured on FLEURS native recordings at a
    /// margin of 10, as native said the lesson sound (right / wrong / of) and
    /// native said the other sound (caught / missed as right / of):
    /// rr 21 / 1 / 35 and 78 / 2 / 110 · single r the same two the other way
    /// round · ñ 24 / 0 / 27 and 87 / 0 / 110 · j 88 / 3 / 110 and 32 / 1 /
    /// 40 · French u 58 / 1 / 105 and 33 / 1 / 77 · eu 56 / 0 / 80 and 67 /
    /// 2 / 80 · an 55 / 1 / 104, on 73 / 1 / 103. German at 15: ü 52 / 2 /
    /// 91 (words of four letters up: "für" alone was 8 of the 10 wrong) and
    /// 75 / 1 / 110 · ö 63 / 2 / 81 and 65 / 2 / 110 · ei 82 / 1 / 110, ie
    /// 54 / 2 / 110 · the ich-sound 99 / 1 / 110 and 45 / 10 / 91. Not
    /// offered: é/è (15 right of 99), in/an (6 wrong of 73 at 5), German
    /// long/short vowels (7 wrong of 110) and z (4 wrong of 77).
    private static func wordRules(topicId: String) -> [[WordRule]]? {
        let v = "aeiouáéíóú"
        switch topicId {
        case "es.rr": return [[WordRule(pattern: "rr", template: "r")]]
        case "es.r": return [[WordRule(pattern: "(?<=[\(v)])r(?=[\(v)])", template: "rr")]]
        case "es.ny": return [[WordRule(pattern: "ñ", template: "n")]]
        case "es.j": return [[WordRule(pattern: "j(?=[\(v)])|g(?=[eiéí])", template: "y")]]
        case "fr.u": return [[WordRule(pattern: "(?<![aeoqgé])u(?![inmeé])", template: "ou", minLength: 4)]]
        case "fr.eu": return [[WordRule(pattern: "(?<![aœ])eu(?![xi])", template: "ou", minLength: 4)]]
        case "de.ue": return [[WordRule(pattern: "ü", template: "u", minLength: 4)]]
        case "de.oe": return [[WordRule(pattern: "ö", template: "o")]]
        case "de.eiie":
            return [[WordRule(pattern: "ei", template: "ie")], [WordRule(pattern: "ie", template: "ei")]]
        case "de.ich": return [[WordRule(pattern: "(?<=[eiäöülnr])ch(?!s)", template: "sch")]]
        case "fr.nasal":
            return [[WordRule(pattern: "an(?![aeiouynm])", template: "on", minLength: 4)],
                    [WordRule(pattern: "on(?![aeiouynm])", template: "an", minLength: 4)]]
        default: return nil
        }
    }

    private static func applying(_ rules: [WordRule], to word: String) -> String {
        var out = word
        for rule in rules where out.count >= rule.minLength {
            guard let re = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: rule.template)
        }
        return out
    }

    // MARK: - Japanese: one beat taken out

    /// The beat the lesson is about, removed: one occurrence per alternate
    /// (Japanese has no spaces, so two swaps in one sentence could not be
    /// told apart). The long mark only after katakana, where it is written.
    /// Measured at a margin of 15: っ kept by a native 89 right / 3 wrong of
    /// 160, dropped 132 caught / 1 of 160; ー 84 / 2 of 133 and 27 / 3 of 42.
    /// Not offered: つ/す (10 wrong of 62).
    private static func occurrenceRule(topicId: String) -> String? {
        switch topicId {
        case "ja.long": return "(?<=[ァ-ヴ])ー"
        case "ja.tsu": return "[っッ]"
        default: return nil
        }
    }

    // MARK: - Korean

    private static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let tenseToPlain: [Character: Character] =
        ["ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ"]
    private static let aspiratedToPlain: [Character: Character] =
        ["ㅋ": "ㄱ", "ㅌ": "ㄷ", "ㅍ": "ㅂ", "ㅊ": "ㅈ"]
    private static func reversed(_ t: [Character: Character]) -> [Character: Character] {
        Dictionary(uniqueKeysWithValues: t.map { ($1, $0) })
    }

    /// One alternate: the lesson's consonants and vowels → what each is
    /// swapped for. Vowels by their index in a syllable (ㅓ 4, ㅗ 8, ㅜ 13,
    /// ㅡ 18).
    private struct Swap {
        var consonants: [Character: Character] = [:]
        var vowels: [Int: Int] = [:]
    }

    /// Every swap here was measured the same day on FLEURS (right / wrong /
    /// within the margin): tense ↔ plain 926 / 11 / 150, aspirated ↔ plain
    /// 180 / 2 / 20, tense ↔ aspirated 743 / 15 / 126, ㅓ ↔ ㅗ 279 / 1 / 18,
    /// ㅡ ↔ ㅜ 244 / 2 / 21. A consonant lesson is compared with BOTH other
    /// kinds: with plain alone, an aspirated consonant read tense passed
    /// (the founder's first try on a phone, the same evening).
    private static func swaps(topicId: String) -> [Swap]? {
        let tenseToAspirated: [Character: Character] = ["ㄲ": "ㅋ", "ㄸ": "ㅌ", "ㅃ": "ㅍ", "ㅉ": "ㅊ"]
        switch topicId {
        case "ko.tense": return [Swap(consonants: tenseToPlain), Swap(consonants: tenseToAspirated)]
        case "ko.asp": return [Swap(consonants: aspiratedToPlain), Swap(consonants: reversed(tenseToAspirated))]
        case "ko.three":
            // Each of the three turned one way round, then the other:
            // plain → tense → aspirated → plain, and back. ㅅ and ㅆ have
            // no aspirated partner and swap with each other both times.
            let forward = reversed(tenseToPlain).merging(tenseToAspirated) { a, _ in a }
                .merging(aspiratedToPlain) { a, _ in a }.merging(["ㅆ": "ㅅ"]) { _, b in b }
            let back = reversed(aspiratedToPlain).merging(reversed(tenseToAspirated)) { a, _ in a }
                .merging(tenseToPlain) { a, _ in a }.merging(["ㅅ": "ㅆ"]) { _, b in b }
            return [Swap(consonants: forward), Swap(consonants: back)]
        case "ko.eoo": return [Swap(vowels: [4: 8, 8: 4])]
        case "ko.eu": return [Swap(vowels: [18: 13])]
        default: return nil
        }
    }

    private static func parts(_ c: Character) -> (initial: Int, vowel: Int, final: Int)? {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1,
              (0xAC00...0xD7A3).contains(v) else { return nil }
        let i = Int(v - 0xAC00)
        return (i / 588, (i % 588) / 28, i % 28)
    }

    private static func syllable(_ initial: Int, _ vowel: Int, _ final: Int) -> Character {
        Character(UnicodeScalar(UInt32(0xAC00 + initial * 588 + vowel * 28 + final))!)
    }

    /// The syllable before leaves the consonant as written: no final
    /// consonant, or ㄴ ㅁ ㅇ. After any other final a plain consonant is
    /// said tense anyway ("짝궁" and "짝꿍" sound the same), so there is
    /// nothing to compare.
    private static func leavesNextAsWritten(_ c: Character?) -> Bool {
        guard let c else { return true }
        guard let p = parts(c) else { return false }
        return [0, 4, 16, 21].contains(p.final)
    }

    private static func swapped(_ word: String, previousWord: String?, table: Swap) -> String {
        var out = ""
        var before: Character? = previousWord?.last(where: { parts($0) != nil })
        for c in word {
            defer { if parts(c) != nil { before = c } }
            guard let p = parts(c), leavesNextAsWritten(before) else {
                out.append(c)
                continue
            }
            let initial = table.consonants[initials[p.initial]].flatMap { initials.firstIndex(of: $0) } ?? p.initial
            out.append(syllable(initial, table.vowels[p.vowel] ?? p.vowel, p.final))
        }
        return out
    }

    // MARK: - Chinese: one character said in another tone

    /// The four tone topics. A tone is a character, so the swap is another
    /// character of the same syllable (买 mǎi → 卖 mài), from the app's own
    /// HSK list (`ChineseToneTable`). One character per alternate. Measured
    /// at a margin of 10 on FLEURS, the character's own sound score: tone 1
    /// 119 right / 2 wrong of 151, tone 2 133 / 3 of 175, tone 3 150 / 3 of
    /// 167, tone 4 145 / 2 of 169. Only where Azure reads the character with
    /// the table's tone (不 and 一 change theirs, 长 has two readings).
    private static func tone(topicId: String) -> Int? {
        switch topicId {
        case "zh.t1": return 1
        case "zh.t2": return 2
        case "zh.t3": return 3
        case "zh.t4": return 4
        default: return nil
        }
    }

    private static let chineseTones: (byCharacter: [Character: (syllable: String, tone: Int)],
                                      bySyllable: [String: [Int: Character]]) = {
        var byCharacter: [Character: (syllable: String, tone: Int)] = [:]
        var bySyllable: [String: [Int: Character]] = [:]
        for entry in ChineseToneTable.data.split(separator: ";") {
            guard let c = entry.first, let tone = entry.last?.wholeNumberValue else { continue }
            let syllable = String(entry.dropFirst().dropLast())
            byCharacter[c] = (syllable, tone)
            // The first of a syllable and tone is the most basic word.
            if bySyllable[syllable]?[tone] == nil { bySyllable[syllable, default: [:]][tone] = c }
        }
        return (byCharacter, bySyllable)
    }()

    /// The tone a learner is most likely to say instead, first.
    private static let confusedWith: [Int: [Int]] = [1: [4, 2, 3], 2: [3, 1, 4], 3: [2, 4, 1], 4: [1, 2, 3]]

    private static func toneAlternates(for text: String, tone: Int) -> [String] {
        var out: [String] = []
        let characters = Array(text)
        for (i, c) in characters.enumerated() where out.count < maxAlternates {
            guard let entry = chineseTones.byCharacter[c], entry.tone == tone,
                  let other = confusedWith[tone]?.lazy.compactMap({ chineseTones.bySyllable[entry.syllable]?[$0] }).first
            else { continue }
            var swapped = characters
            swapped[i] = other
            out.append(String(swapped))
        }
        return out
    }

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.first.map { (0x4E00...0x9FFF).contains($0.value) } ?? false
    }

    /// One character of the take that fit another tone better. Each read is
    /// laid out character by character with that character's own score (the
    /// word's, when the sounds don't line up with the characters).
    private static func toneMiss(reference: [PronunciationResult.Word],
                                 other: [PronunciationResult.Alternate.Scored], margin: Int) -> Miss? {
        struct Piece { let character: Character; let score: Int?; let name: String?; let word: String }
        var mine: [Piece] = []
        for w in reference {
            let han = w.word.filter(isHan)
            let perCharacter = w.phonemes.count == han.count
            for (i, c) in han.enumerated() {
                mine.append(Piece(character: c,
                                  score: w.isJudged ? (perCharacter ? w.phonemes[i].accuracy : w.accuracy) : nil,
                                  name: perCharacter ? w.phonemes[i].phoneme : nil, word: w.word))
            }
        }
        var theirs: [(Character, Int?)] = []
        for w in other {
            let han = w.word.filter(isHan)
            let scores = w.phonemes ?? []
            for (i, c) in han.enumerated() {
                theirs.append((c, w.error == "Omission" ? nil : (scores.count == han.count ? scores[i] : w.accuracy)))
            }
        }
        guard mine.count == theirs.count else { return nil }
        for (m, t) in zip(mine, theirs) where m.character != t.0 {
            guard let score = m.score, let otherScore = t.1, otherScore - score > margin else { return nil }
            // Azure must have read the character with the tone the swap was
            // made from, or the two spellings were never that tone against
            // another.
            if let name = m.name, let expected = chineseTones.byCharacter[m.character]?.tone,
               name.last?.wholeNumberValue != expected { return nil }
            return Miss(word: m.word, cameOutAs: String(t.0), gap: otherScore - score)
        }
        return nil
    }

    // MARK: - The alternates

    /// `text` with the topic's sound swapped in every word that carries it:
    /// one sentence per swap, the same number of words as `text`. Empty when
    /// the topic isn't judged this way or `text` has nothing to swap.
    static func alternates(for text: String, topicId: String) -> [String] {
        if let tone = tone(topicId: topicId) { return toneAlternates(for: text, tone: tone) }
        if let pattern = occurrenceRule(topicId: topicId) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .prefix(maxAlternates).compactMap { m in
                    Range(m.range, in: text).map { text.replacingCharacters(in: $0, with: "") }
                }
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        if let lists = wordRules(topicId: topicId) {
            for rules in lists.prefix(maxAlternates) {
                let alt = words.map { applying(rules, to: $0) }.joined(separator: " ")
                if alt != text, !out.contains(alt) { out.append(alt) }
            }
            return out
        }
        guard let tables = swaps(topicId: topicId) else { return [] }
        for table in tables.prefix(maxAlternates) {
            let alt = words.enumerated().map { i, w in
                swapped(w, previousWord: i > 0 ? words[i - 1] : nil, table: table)
            }.joined(separator: " ")
            if alt != text, !out.contains(alt) { out.append(alt) }
        }
        return out
    }

    // MARK: - The verdict

    /// A word of the take that fit another spelling better.
    struct Miss: Equatable {
        let word: String
        /// The spelling it fit ("방을").
        let cameOutAs: String
        let gap: Int
    }

    /// Every word where an alternate beat the reference by more than
    /// `margin`, the widest gap first.
    static func misses(in result: PronunciationResult) -> [Miss] {
        let reference = result.referenceWords
        let margin = margin(locale: result.locale)
        if result.locale.hasPrefix("zh") {
            return (result.alternates ?? []).compactMap {
                toneMiss(reference: reference, other: $0.words.filter { $0.error != "Insertion" }, margin: margin)
            }.sorted { $0.gap > $1.gap }
        }
        if result.locale.hasPrefix("ja") {
            return (result.alternates ?? []).compactMap {
                unspacedMiss(reference: reference, other: $0.words.filter { $0.error != "Insertion" },
                             margin: margin)
            }.sorted { $0.gap > $1.gap }
        }
        var best: [Int: Miss] = [:]
        for alt in result.alternates ?? [] {
            let other = alt.words.filter { $0.error != "Insertion" }
            // The two reads must line up word for word, or there is nothing
            // to compare.
            guard other.count == reference.count else { continue }
            for (i, (r, a)) in zip(reference, other).enumerated() {
                guard PronunciationJudge.key(r.word) != PronunciationJudge.key(a.word),
                      r.isJudged, a.error != "Omission",
                      let mine = r.accuracy, let theirs = a.accuracy else { continue }
                let gap = theirs - mine
                if gap > margin, gap > (best[i]?.gap ?? 0) {
                    best[i] = Miss(word: r.word, cameOutAs: a.word, gap: gap)
                }
            }
        }
        return best.values.sorted { $0.gap > $1.gap }
    }

    /// A language written without spaces: the two reads are cut into words
    /// differently ("立っ · て" against "立て"), so they are lined up by
    /// letter. Everything before and after the one change is the same in
    /// both; the words that cover the change are compared, the lowest score
    /// on each side.
    private static func unspacedMiss(reference: [PronunciationResult.Word],
                                     other: [PronunciationResult.Alternate.Scored],
                                     margin: Int) -> Miss? {
        let mine = reference.map { (Array(PronunciationJudge.key($0.word)), $0.word, $0.isJudged ? $0.accuracy : nil) }
        let theirs = other.map { (Array(PronunciationJudge.key($0.word)), $0.word, $0.error == "Omission" ? nil : $0.accuracy) }
        let t = mine.flatMap(\.0), a = theirs.flatMap(\.0)
        guard t != a, !t.isEmpty, !a.isEmpty else { return nil }
        var p = 0
        while p < min(t.count, a.count), t[p] == a[p] { p += 1 }
        var s = 0
        while s < min(t.count, a.count) - p, t[t.count - 1 - s] == a[a.count - 1 - s] { s += 1 }
        func covering(_ words: [([Character], String, Int?)], _ lo: Int, _ hi: Int) -> (String, Int)? {
            var position = 0
            var text = ""
            var lowest: Int?
            for (letters, word, accuracy) in words {
                let start = position, end = position + letters.count
                position = end
                let hit = hi > lo ? (start < hi && end > lo) : (start < lo && lo <= end) || (lo == 0 && start == 0)
                guard hit else { continue }
                guard let accuracy else { return nil }
                text += word
                lowest = min(lowest ?? accuracy, accuracy)
            }
            return lowest.map { (text, $0) }
        }
        guard let (word, score) = covering(mine, p, t.count - s),
              let (otherWord, otherScore) = covering(theirs, p, a.count - s),
              otherScore - score > margin else { return nil }
        return Miss(word: word, cameOutAs: otherWord, gap: otherScore - score)
    }

    /// Off script, a word left out, or the lesson's sound said as the other
    /// one. Nothing else stops a reading: no score is held to a bar.
    static func verdict(result: PronunciationResult?, only: Set<String>? = nil,
                        excluding: Set<String> = []) -> PronunciationJudge.Verdict {
        guard let result else { return .unheard }
        if (result.completeness ?? 100) < PronunciationJudge.completenessBar { return .offScript }
        func inScope(_ word: String) -> Bool {
            let k = PronunciationJudge.key(word)
            return !excluding.contains(k) && (only?.contains(k) ?? true)
        }
        if let miss = misses(in: result).first(where: { inScope($0.word) }) {
            return .notYet(word: miss.word, sound: nil, score: result.soundScore, heard: miss.cameOutAs)
        }
        if let left = result.referenceWords.first(where: { $0.isOmission && inScope($0.word) }) {
            return .notYet(word: left.word, sound: nil, score: result.soundScore, heard: nil)
        }
        return .pass(score: result.soundScore)
    }
}

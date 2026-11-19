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
    /// A spelling must beat the other by more than this on the word.
    static let margin = 5
    static let maxAlternates = 2

    /// Topics judged by comparison. A topic is added once its own swap has
    /// been measured on native recordings.
    static func isOffered(topicId: String) -> Bool {
        swaps(topicId: topicId) != nil
    }

    /// The languages with at least one such topic.
    static func isOffered(language: String) -> Bool {
        LanguageCatalog.base(language) == "ko"
    }

    // MARK: - Korean

    private static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let tenseToPlain: [Character: Character] =
        ["ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ"]

    /// Each alternate is one table: the lesson's consonant → what it is
    /// swapped for.
    private static func swaps(topicId: String) -> [[Character: Character]]? {
        switch topicId {
        case "ko.tense": return [tenseToPlain]
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

    private static func swapped(_ word: String, previousWord: String?,
                                table: [Character: Character]) -> String {
        var out = ""
        var before: Character? = previousWord?.last(where: { parts($0) != nil })
        for c in word {
            defer { if parts(c) != nil { before = c } }
            guard let p = parts(c), let to = table[initials[p.initial]],
                  let toIndex = initials.firstIndex(of: to), leavesNextAsWritten(before) else {
                out.append(c)
                continue
            }
            out.append(syllable(toIndex, p.vowel, p.final))
        }
        return out
    }

    // MARK: - The alternates

    /// `text` with the topic's sound swapped in every word that carries it:
    /// one sentence per swap, the same number of words as `text`. Empty when
    /// the topic isn't judged this way or `text` has nothing to swap.
    static func alternates(for text: String, topicId: String) -> [String] {
        guard let tables = swaps(topicId: topicId) else { return [] }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
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

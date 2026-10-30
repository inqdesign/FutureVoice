import Foundation
import NaturalLanguage

/// The vocabulary level, read from WHICH words a learner reaches for rather
/// than how many advanced words they have ever said.
///
/// The count it replaced (C2 at 15 distinct words over 90 days) rose with
/// the amount of talk alone: measured on the NICT JLE corpus (1,277 learners
/// of English in the same 15-minute SST interview at nine levels, plus 20
/// natives doing the same task), six pooled ≈A2 interviews read B2 197 times
/// in 200. Advanced words are rare in conversation for everyone.
///
/// The measure is the MEAN LEVEL (A1 = 0 … C2 = 5) of the graded CONTENT
/// words said (nouns, verbs, adjectives, adverbs), repeats counted. Two
/// things were learned the hard way (2026-10-30):
/// - Function words have to go. A first cut counted every graded token, and
///   the list grades `that` B2 and auxiliary `will` as the noun — so half of
///   a native's "B2+ share" was the word `that`, and the measure was mostly
///   counting relative clauses. Content words only, minus `stopWords`.
/// - Above B1 vocabulary in speech stops separating learners. Medians by
///   SST level, one interview: 3 → 0.23, 4 → 0.27, 5 → 0.29, 6 → 0.33,
///   7–9 → 0.32–0.34, natives 0.38. So the measure reads A1 / A2 / B1 and
///   "native-like range"; B2–C2 come from the weekly assessment's read of
///   word PRECISION (`WeeklyReport.lexicalPrecision`), and C1/C2 also need
///   the native-like range.
///
/// German's cuts were carried over from English through 240k held-out
/// Tatoeba en–de sentence pairs (pooled means correlate 0.88): PROVISIONAL —
/// no German learner speech with levels was available to check them on.
/// `scripts/vocab-calibration/` reruns all of it.
enum VocabSophistication {

    struct Profile {
        /// Lower edges of A2, B1 and the native-like range (B2 without a
        /// precision read; the floor for C1/C2 with one).
        let a2: Double, b1: Double, nativeLike: Double
        let tagger: NLLanguage
        /// Auxiliaries, modals and homographs the pool grades by a rare
        /// sense (`will` the noun, `found` = establish).
        let stopWords: Set<String>
    }

    static let profiles: [String: Profile] = [
        "en": Profile(a2: 0.25, b1: 0.31, nativeLike: 0.36, tagger: .english,
                      stopWords: ["be", "have", "do", "will", "would", "can", "could", "may", "might",
                                  "shall", "should", "must", "ought", "that", "found", "mine", "plus"]),
        "de": Profile(a2: 0.55, b1: 0.58, nativeLike: 0.61, tagger: .german,
                      stopWords: ["sein", "haben", "werden", "tun", "können", "müssen", "sollen",
                                  "dürfen", "mögen", "wollen", "möchten"]),
    ]

    static func isCalibrated(_ languageCode: String) -> Bool { profiles[languageCode] != nil }

    /// Graded content words needed before a band is read — about an hour of
    /// a learner's own speech (an SST interview carries 200–480).
    static let minGradedTokens = 300
    /// The newest talks are read until this many: three or four interviews'
    /// worth, where one level's spread narrows to ±0.03.
    static let windowGradedTokens = 1200

    struct Read: Equatable {
        /// Graded content words in the window.
        var graded: Int
        /// The sum of their levels (A1 = 0 … C2 = 5).
        var levelSum: Int
        /// Talks the window reached back over.
        var talks: Int
        var mean: Double { graded > 0 ? Double(levelSum) / Double(graded) : 0 }
    }

    enum Ceiling: Equatable {
        /// B1 or the native-like range is measured; above it needs the
        /// assessment's precision read, which isn't there yet.
        case needsPrecision
        /// The precision read set the band.
        case precision(CEFRLevel)
    }

    /// The band, or nil while the sample is too small.
    static func level(_ read: Read, profile: Profile, precision: CEFRLevel?)
        -> (level: CEFRLevel, ceiling: Ceiling?)? {
        guard read.graded >= minGradedTokens else { return nil }
        let m = read.mean
        if m < profile.a2 { return (.a1, nil) }
        if m < profile.b1 { return (.a2, nil) }
        let measured: CEFRLevel = m >= profile.nativeLike ? .b2 : .b1
        guard let precision else { return (measured, .needsPrecision) }
        // Precision decides above B1, never below it (B1 is measured), and
        // C1/C2 also need the range a native speaker's words have.
        var set = rank(precision) < rank(.b1) ? CEFRLevel.b1 : precision
        if rank(set) > rank(.b2), m < profile.nativeLike { set = .b2 }
        return (set, .precision(precision))
    }

    /// Walks talks NEWEST FIRST (`texts` per talk, the learner's own evidence
    /// lines) until `windowGradedTokens`.
    static func read(talksNewestFirst: [[String]], profile: Profile,
                     level gradeOf: (String) -> CEFRLevel?) -> Read {
        var out = Read(graded: 0, levelSum: 0, talks: 0)
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        for texts in talksNewestFirst {
            guard out.graded < windowGradedTokens else { break }
            let before = out.graded
            for text in texts {
                for lemma in contentLemmas(text, profile: profile, tagger: tagger) {
                    guard let lv = gradeOf(lemma) else { continue }
                    out.graded += 1
                    out.levelSum += rank(lv)
                }
            }
            if out.graded > before { out.talks += 1 }
        }
        return out
    }

    private static let contentClasses: Set<NLTag> = [.noun, .verb, .adjective, .adverb]

    /// Every content word's lemma, in order — repeats counted, because a
    /// token mean is what was calibrated.
    static func contentLemmas(_ text: String, profile: Profile, tagger: NLTagger) -> [String] {
        var out: [String] = []
        tagger.string = text
        tagger.setLanguage(profile.tagger, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { cls, range in
            guard let cls, contentClasses.contains(cls) else { return true }
            let lemma = (tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                         ?? String(text[range])).lowercased()
            if lemma.count > 1, !profile.stopWords.contains(lemma) { out.append(lemma) }
            return true
        }
        return out
    }

    private static func rank(_ l: CEFRLevel) -> Int { CoreVocabulary.levelRank(l) }
}

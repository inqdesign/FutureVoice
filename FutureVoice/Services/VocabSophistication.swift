import Foundation
import NaturalLanguage

/// The vocabulary level, read as WHICH words a learner reaches for rather
/// than how many advanced words they have ever said.
///
/// The rule this replaced took the highest band with a fixed number of
/// distinct words (C2 at 15) over 90 days, and it rose with talk alone:
/// measured on the NICT JLE corpus (1,277 learners of English, the same
/// 15-minute SST interview, nine graded levels, plus 20 native speakers doing
/// the same task — 2026-10-30), pooling six interviews of SST 4 (≈A2) read B2
/// 197 times in 200, and twelve native interviews read C1. Advanced words are
/// rare in conversation for everyone — natives used one or two C1/C2 words in
/// fifteen minutes — so a count of them is a count of minutes spoken.
///
/// What does separate levels is the SHARE of graded word tokens at B2 and
/// above: the basic words are the floor everyone stands on (90%+ of what
/// anyone says), and the difference lives in the tail. Medians by SST level:
/// 3 → 2.1%, 4 → 3.1%, 5 → 3.7%, 6 → 4.5%, 7 → 4.6%, 8 → 5.5%, 9 → 5.3%,
/// natives 6.5% — and the share holds still as the sample grows (SST 4 reads
/// ~3.3% over one interview or twelve). The cuts below come from those
/// medians; `scripts/vocab-calibration/` reruns the measurement.
///
/// Two limits, both deliberate:
/// - Above B2 the share stops separating (SST 8 ≈ SST 9, natives +1pt), so
///   C1 and C2 need a second witness: the weekly assessment's read of word
///   PRECISION (`WeeklyReport.lexicalPrecision` — did they pick the precise
///   word where a general one would do). Without one the band stops at B2.
/// - Calibrated for ENGLISH only. Other languages keep the old count until
///   they have their own measurement (and Korean/Spanish their own lists).
enum VocabSophistication {

    /// Graded tokens needed before a band is read — about an hour of a
    /// learner's own speech. Below it one talk's topic decides the number.
    static let minGradedTokens = 400
    /// The newest talks are read until this many graded tokens: enough for a
    /// stable share (±1pt at the 10th–90th percentile), recent enough to be
    /// today's vocabulary rather than last spring's.
    static let windowGradedTokens = 1500

    /// Lower edge of each band, in percent of graded tokens at B2+.
    static let cuts: [(level: CEFRLevel, from: Double)] = [
        (.c2, 7.0), (.c1, 6.0), (.b2, 5.0), (.b1, 4.1), (.a2, 2.6), (.a1, 0)
    ]

    static func isCalibrated(_ languageCode: String) -> Bool { languageCode == "en" }

    struct Read: Equatable {
        /// Graded word tokens in the window.
        var graded: Int
        /// Of those, at B2 or above.
        var advanced: Int
        /// Talks the window reached back over.
        var talks: Int
        var share: Double { graded > 0 ? Double(advanced) / Double(graded) * 100 : 0 }
    }

    enum Ceiling: Equatable {
        /// The share alone reads C1+; no assessment has judged precision yet.
        case needsPrecision
        /// The assessment's precision read held the band down.
        case precision(CEFRLevel)
    }

    /// The band, or nil while the sample is too small.
    static func level(_ read: Read, precision: CEFRLevel?)
        -> (level: CEFRLevel, ceiling: Ceiling?)? {
        guard read.graded >= minGradedTokens else { return nil }
        let byShare = cuts.first { read.share >= $0.from }?.level ?? .a1
        guard rank(byShare) > rank(.b2) else { return (byShare, nil) }
        guard let precision else { return (.b2, .needsPrecision) }
        // Precision can hold C1+ down, never below what the share already
        // shows — B2 range is measured, not judged.
        let capped = rank(precision) < rank(byShare)
            ? (rank(precision) > rank(.b2) ? precision : .b2) : byShare
        return capped == byShare ? (byShare, nil) : (capped, .precision(precision))
    }

    /// Walks talks NEWEST FIRST (`texts` per talk, the learner's own evidence
    /// lines) until `windowGradedTokens`, counting every graded token.
    static func read(talksNewestFirst: [[String]],
                     level gradeOf: (String) -> CEFRLevel?) -> Read {
        var out = Read(graded: 0, advanced: 0, talks: 0)
        let tagger = NLTagger(tagSchemes: [.lemma])
        for texts in talksNewestFirst {
            guard out.graded < windowGradedTokens else { break }
            let before = out.graded
            for text in texts {
                for lemma in lemmaTokens(text, tagger: tagger) {
                    guard let lv = gradeOf(lemma) else { continue }
                    out.graded += 1
                    if rank(lv) >= rank(.b2) { out.advanced += 1 }
                }
            }
            if out.graded > before { out.talks += 1 }
        }
        return out
    }

    /// Every word token's lemma, in order — repeats counted, unlike
    /// `VocabStore.lemmas(in:)`, because a share of TOKENS is what was
    /// calibrated (a type share keeps rising with sample size).
    static func lemmaTokens(_ text: String, tagger: NLTagger) -> [String] {
        var out: [String] = []
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
            let lemma = (tag?.rawValue ?? String(text[range])).lowercased()
            if lemma.count > 1 { out.append(lemma) }
            return true
        }
        return out
    }

    private static func rank(_ l: CEFRLevel) -> Int { CoreVocabulary.levelRank(l) }
}

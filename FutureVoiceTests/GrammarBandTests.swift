import XCTest
@testable import FutureVoice

/// The ≈Grammar band on Progress is the LOWER of two reads — accuracy
/// (verified slip density) and range (the structures actually produced).
/// Reported 2026-09-24: an A1–A2 learner who only said easy things read C2,
/// because easy sentences carry no slips. These pin the rule.
final class GrammarBandTests: XCTestCase {

    private func band(slips: Double, score: Int = 0, scored: Int = 3,
                      range: CEFRLevel? = nil, vocab: CEFRLevel? = nil)
        -> (level: CEFRLevel, ceiling: ProgressTab.GrammarCeiling?)? {
        ProgressTab.grammarBand(slipsPer100Words: slips, grammarScore: score,
                                scoredCount: scored, range: range, vocabLevel: vocab)
    }

    /// The reported case: no slips, simple sentences. Range decides.
    func testSimpleAccurateSpeechReadsItsRangeNotC2() {
        let r = band(slips: 0, score: 96, range: .a2)
        XCTAssertEqual(r?.level, .a2)
        XCTAssertEqual(r?.ceiling, .range(.a2))
    }

    /// Range never RAISES the band: a wide range spoken with many slips
    /// still reads by its slips.
    func testRangeIsACeilingNotAFloor() {
        let r = band(slips: 6, range: .c1)
        XCTAssertEqual(r?.level, .a2)
        XCTAssertNil(r?.ceiling)
    }

    /// Accuracy and range agree → the accuracy read stands, uncapped.
    func testAccurateWideSpeechReadsHigh() {
        let r = band(slips: 0.7, range: .c1)
        XCTAssertEqual(r?.level, .c1)
        XCTAssertNil(r?.ceiling)
    }

    /// Talks summarized before the range field: the graded vocabulary plus
    /// one band stands in, and the ceiling says so.
    func testLegacyTalksAreCappedByVocabulary() {
        let r = band(slips: 0, score: 96, vocab: .a1)
        XCTAssertEqual(r?.level, .a2)
        XCTAssertEqual(r?.ceiling, .vocabulary(.a2))
        XCTAssertEqual(band(slips: 0, score: 96, vocab: .c2)?.level, .c2)
    }

    /// A measured range outranks the vocabulary stand-in.
    func testRangeWinsOverVocabularyStandIn() {
        XCTAssertEqual(band(slips: 0, score: 96, range: .b1, vocab: .a1)?.level, .b1)
    }

    /// Nothing measured → no band, never a guess.
    func testNoEvidenceIsNoBand() {
        XCTAssertNil(band(slips: 0, score: 0, range: .a1))
        XCTAssertNil(band(slips: 0, score: 90, scored: 0))
    }
}

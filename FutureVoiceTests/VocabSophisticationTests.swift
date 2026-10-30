import XCTest
@testable import FutureVoice

/// The vocabulary level reads the SHARE of advanced word tokens, not a count
/// of advanced words. Reported 2026-10-29: a few C2 words made the level C2,
/// and the old count rose with the amount of talk alone (NICT JLE: six ≈A2
/// interviews pooled read B2). These pin the rule and its calibration.
final class VocabSophisticationTests: XCTestCase {

    private func read(graded: Int, share: Double) -> VocabSophistication.Read {
        .init(graded: graded, advanced: Int((Double(graded) * share / 100).rounded()), talks: 3)
    }

    func testTooLittleSpeechReadsNoLevel() {
        XCTAssertNil(VocabSophistication.level(read(graded: 399, share: 9), precision: .c2))
    }

    /// The cuts are the NICT JLE medians: SST 3 ≈2.1%, SST 4–5 ≈3.1–3.7%,
    /// SST 6–7 ≈4.5%, SST 8 ≈5.5%.
    func testBandsFollowTheCalibration() {
        let cases: [(Double, CEFRLevel)] = [(2.1, .a1), (3.3, .a2), (4.5, .b1), (5.5, .b2)]
        for (share, expected) in cases {
            XCTAssertEqual(VocabSophistication.level(read(graded: 1000, share: share),
                                                     precision: nil)?.level, expected, "\(share)%")
        }
    }

    /// Above B2 the share no longer separates levels: no precision read, no C1.
    func testC1ShareWithoutPrecisionStopsAtB2() {
        let r = VocabSophistication.level(read(graded: 1000, share: 6.5), precision: nil)
        XCTAssertEqual(r?.level, .b2)
        XCTAssertEqual(r?.ceiling, .needsPrecision)
    }

    func testPrecisionHoldsTheTopDown() {
        let r = VocabSophistication.level(read(graded: 1000, share: 7.5), precision: .c1)
        XCTAssertEqual(r?.level, .c1)
        XCTAssertEqual(r?.ceiling, .precision(.c1))
    }

    /// Precision never pulls a measured B2 range below B2.
    func testLowPrecisionNeverGoesBelowB2() {
        let r = VocabSophistication.level(read(graded: 1000, share: 6.5), precision: .a2)
        XCTAssertEqual(r?.level, .b2)
    }

    /// Precision can't RAISE the band either.
    func testPrecisionNeverRaises() {
        let r = VocabSophistication.level(read(graded: 1000, share: 6.2), precision: .c2)
        XCTAssertEqual(r?.level, .c1)
        XCTAssertNil(r?.ceiling)
    }

    private let toyLevels: [String: CEFRLevel] = [
        "go": .a1, "shop": .a1, "buy": .a1, "bread": .a1, "negotiate": .b2, "ephemeral": .c2
    ]

    /// Repeats count (a token share), and talking more about the same thing
    /// doesn't move the share — the property the old count lacked.
    func testShareIsStableAsTalkGrows() {
        let talk = ["I go to the shop and buy bread", "I negotiate the price"]
        let once = VocabSophistication.read(talksNewestFirst: [talk], level: { self.toyLevels[$0] })
        let tenTimes = VocabSophistication.read(talksNewestFirst: Array(repeating: talk, count: 10),
                                                level: { self.toyLevels[$0] })
        XCTAssertEqual(once.graded, 5)
        XCTAssertEqual(once.advanced, 1)
        XCTAssertEqual(once.share, tenTimes.share, accuracy: 0.001)
        XCTAssertEqual(tenTimes.talks, 10)
    }

    /// The window reads the newest talks only, until it has enough.
    func testWindowStopsOnceFull() {
        let talk = Array(repeating: "go shop buy bread", count: 200)   // 800 graded
        let r = VocabSophistication.read(talksNewestFirst: Array(repeating: talk, count: 5),
                                         level: { self.toyLevels[$0] })
        XCTAssertEqual(r.talks, 2)
        XCTAssertEqual(r.graded, 1600)
    }
}

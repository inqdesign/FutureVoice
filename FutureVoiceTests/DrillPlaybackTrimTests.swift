import XCTest
@testable import FutureVoice

/// The drill card quotes only the sentence a correction fixed, and its play
/// button now trims the turn recording to that same slice. The trim is only
/// honest if the fragment's words can be located inside the timed words of
/// the WHOLE turn — these cover that lookup.
final class DrillPlaybackTrimTests: XCTestCase {

    // MARK: - matchWords

    func testMatchWordsNormalizesCaseAndPunctuation() {
        XCTAssertEqual(DrillStore.matchWords(of: "Sure, I went — there!"),
                       ["sure", "i", "went", "there"])
    }

    func testPunctuationOnlyTokensAreDropped() {
        XCTAssertEqual(DrillStore.matchWords(of: "well — yes"), ["well", "yes"])
    }

    // MARK: - fragmentSpan

    func testFindsSentenceInsideLongerTurn() {
        let words = DrillStore.matchWords(of:
            "So yesterday was crazy. I go to store yesterday. Anyway it was fine.")
        let fragment = DrillStore.matchWords(of: "I go to store yesterday")
        XCTAssertEqual(DrillStore.fragmentSpan(of: fragment, in: words), 4...8)
    }

    func testWholeTurnFragmentSpansEverything() {
        let words = DrillStore.matchWords(of: "I go to store yesterday.")
        let fragment = DrillStore.matchWords(of: "I go to store yesterday")
        XCTAssertEqual(DrillStore.fragmentSpan(of: fragment, in: words), 0...4)
    }

    /// `relevantFragment`'s fallback is `prefix(maxChars) + "…"`, which can
    /// cut MID-WORD — the last fragment word then only prefix-matches.
    func testHardPrefixCutMatchesLastWordAsPrefix() {
        let words = DrillStore.matchWords(of: "I was talking about something else")
        let fragment = DrillStore.matchWords(of: "talking about somethin…")
        XCTAssertEqual(DrillStore.fragmentSpan(of: fragment, in: words), 2...4)
    }

    /// A prefix match is allowed ONLY on the last word — an interior word
    /// must match exactly or the run isn't the quoted fragment.
    func testInteriorWordMustMatchExactly() {
        let words = DrillStore.matchWords(of: "I was talking about something else")
        let fragment = DrillStore.matchWords(of: "talk about something")
        XCTAssertNil(DrillStore.fragmentSpan(of: fragment, in: words))
    }

    func testMissingFragmentReturnsNil() {
        let words = DrillStore.matchWords(of: "I go to store yesterday")
        let fragment = DrillStore.matchWords(of: "went to the shop")
        XCTAssertNil(DrillStore.fragmentSpan(of: fragment, in: words))
    }

    func testFragmentLongerThanTurnReturnsNil() {
        XCTAssertNil(DrillStore.fragmentSpan(of: ["a", "b", "c"], in: ["a", "b"]))
    }

    /// The repeated-stretch case: STT sometimes writes a phrase twice. The
    /// FIRST occurrence wins — deterministic, and the timings of either take
    /// play the same words.
    func testRepeatedPhraseTakesFirstOccurrence() {
        let words = DrillStore.matchWords(of: "I mean I go to store I go to store today")
        let fragment = DrillStore.matchWords(of: "I go to store")
        XCTAssertEqual(DrillStore.fragmentSpan(of: fragment, in: words), 2...5)
    }
}

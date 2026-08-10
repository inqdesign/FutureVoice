import XCTest
@testable import FutureVoice

/// Karaoke timing is only honest if it comes from the audio that actually
/// plays. These cover the two halves of that: matching the recognizer's words
/// to the target's, and turning that into a timeline with no gaps or
/// backwards jumps.
final class LocalAlignmentTests: XCTestCase {

    private func spans(_ pairs: [(Double, Double)]) -> [(start: Double, end: Double)] {
        pairs.map { (start: $0.0, end: $0.1) }
    }

    // MARK: - align

    func testEveryWordAnchorsOnAPerfectRecognition() {
        let pairing = LocalAlignment.align(expected: ["i", "went", "there"],
                                           heard: ["i", "went", "there"])
        XCTAssertEqual(pairing, [0, 1, 2])
    }

    /// The old code bailed entirely on any count mismatch, which is why most
    /// lines fell through to the estimate.
    func testDroppedWordStillAnchorsItsNeighbours() {
        let pairing = LocalAlignment.align(expected: ["i", "went", "there", "yesterday"],
                                           heard: ["i", "there", "yesterday"])
        XCTAssertEqual(pairing, [0, nil, 1, 2])
    }

    func testExtraRecognizedWordIsSkipped() {
        let pairing = LocalAlignment.align(expected: ["i", "went", "there"],
                                           heard: ["i", "uh", "went", "there"])
        XCTAssertEqual(pairing, [0, 2, 3])
    }

    /// A substitution means the recognizer heard a DIFFERENT word there, so
    /// its timestamp isn't trustworthy for the target word.
    func testSubstitutionDoesNotAnchor() {
        let pairing = LocalAlignment.align(expected: ["i", "went", "there"],
                                           heard: ["i", "want", "there"])
        XCTAssertEqual(pairing, [0, nil, 2])
    }

    func testNothingRecognizedAnchorsNothing() {
        XCTAssertEqual(LocalAlignment.align(expected: ["i", "went"], heard: []),
                       [nil, nil])
    }

    func testNormalizationIgnoresCaseAndPunctuation() {
        XCTAssertEqual(LocalAlignment.normalized("Sure,"), LocalAlignment.normalized("sure"))
        XCTAssertEqual(LocalAlignment.normalized("좋아요!"), "좋아요")
    }

    // MARK: - fill

    func testAnchoredWordsKeepTheirRecognizedTimes() {
        let out = LocalAlignment.fill(
            expected: ["one", "two"], pairing: [0, 1],
            heardSpans: spans([(0.0, 0.5), (0.6, 1.2)]), durationMs: 1200)
        XCTAssertEqual(out.map(\.startMs), [0, 600])
        XCTAssertEqual(out.map(\.endMs), [500, 1200])
        XCTAssertEqual(out.map(\.word), ["one", "two"])
    }

    func testUnanchoredWordSplitsTheGapBetweenNeighbours() {
        // "two" wasn't recognized; it owns the 500→1000ms gap.
        let out = LocalAlignment.fill(
            expected: ["one", "two", "three"], pairing: [0, nil, 1],
            heardSpans: spans([(0.0, 0.5), (1.0, 1.5)]), durationMs: 1500)
        XCTAssertEqual(out[1].startMs, 500)
        XCTAssertEqual(out[1].endMs, 1000)
    }

    /// A trailing run with no anchor after it runs to the end of the FILE, not
    /// to the last recognized word — otherwise the highlight freezes early.
    func testTrailingRunReachesTheEndOfTheAudio() {
        let out = LocalAlignment.fill(
            expected: ["one", "two"], pairing: [0, nil],
            heardSpans: spans([(0.0, 0.5)]), durationMs: 2000)
        XCTAssertEqual(out.last?.endMs, 2000)
    }

    func testLeadingRunStartsAtZero() {
        let out = LocalAlignment.fill(
            expected: ["one", "two"], pairing: [nil, 0],
            heardSpans: spans([(1.0, 1.5)]), durationMs: 1500)
        XCTAssertEqual(out.first?.startMs, 0)
        XCTAssertEqual(out.first?.endMs, 1000)
    }

    func testTimelineIsAlwaysMonotonicAndNonEmpty() {
        // Deliberately out-of-order spans — the recognizer occasionally
        // reports these, and a backwards window makes the highlight jump.
        let out = LocalAlignment.fill(
            expected: ["a", "b", "c"], pairing: [0, 1, 2],
            heardSpans: spans([(0.5, 1.0), (0.2, 0.4), (1.1, 1.4)]), durationMs: 1400)
        for i in out.indices {
            XCTAssertLessThan(out[i].startMs, out[i].endMs, "word \(i) has no width")
            if i > 0 { XCTAssertGreaterThanOrEqual(out[i].startMs, out[i - 1].endMs) }
        }
    }

    // MARK: - stale-timing guard

    func testTimingsFromAnotherRenderAreRejected() {
        let t = [WordTiming(word: "hi", startMs: 0, endMs: 3400)]
        // Same line, but this take ran 3.4s and the file is 2.0s.
        XCTAssertFalse(ShadowDrillView.fits(t, durationMs: 2000))
    }

    func testTimingsThatMatchTheFileAreKept() {
        let t = [WordTiming(word: "hi", startMs: 0, endMs: 1950)]
        XCTAssertTrue(ShadowDrillView.fits(t, durationMs: 2000))
    }

    func testEmptyTimingsNeverFit() {
        XCTAssertFalse(ShadowDrillView.fits([], durationMs: 2000))
    }

    /// Unknown duration can't disprove anything — don't throw away good data.
    func testUnknownDurationKeepsTimings() {
        let t = [WordTiming(word: "hi", startMs: 0, endMs: 1950)]
        XCTAssertTrue(ShadowDrillView.fits(t, durationMs: 0))
    }

    // MARK: - attempt cutoff

    /// The headroom has to grow with the line. A flat margin covered a 3s
    /// line and cut a 20s one off mid-sentence.
    func testHeadroomGrowsWithTheLine() {
        let shortHeadroom = ShadowDrillView.attemptCutoffMs(targetMs: 3_000) - 3_000
        let longHeadroom = ShadowDrillView.attemptCutoffMs(targetMs: 20_000) - 20_000
        XCTAssertGreaterThan(longHeadroom, shortHeadroom * 3)
    }

    /// A learner running 40% slower than the model line must still fit.
    func testAttemptFortyPercentSlowerThanTheLineFits() {
        for targetMs in [3_000, 8_000, 20_000, 45_000] {
            let realisticAttempt = Int(Double(targetMs) * 1.4)
            XCTAssertGreaterThan(ShadowDrillView.attemptCutoffMs(targetMs: targetMs),
                                 realisticAttempt,
                                 "a 40%-slower attempt on a \(targetMs)ms line is cut off")
        }
    }

    /// A duration lookup that failed must not collapse into a 3-second cap.
    func testUnknownDurationFallsBackToTextLength() {
        let line = "I have been thinking about that for a while and honestly it changed my mind"
        let fallback = ShadowDrillView.durationFromText(line)
        XCTAssertGreaterThan(ShadowDrillView.attemptCutoffMs(targetMs: fallback), 8_000)
    }

    /// The hint list grows with the line; the recognizer's limit does not.
    func testRecognitionHintsAreCapped() {
        let long = (0..<400).map { "word\($0)" }.joined(separator: " ")
        let hints = ShadowDrillView.recognitionHints(for: long)
        XCTAssertLessThanOrEqual(hints.count, ShadowDrillView.maxRecognitionHints)
        XCTAssertEqual(hints.first, long, "the whole line is the most useful hint")
    }
}

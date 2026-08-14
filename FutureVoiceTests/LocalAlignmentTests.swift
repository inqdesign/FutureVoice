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

    // MARK: - fits

    /// THE REGRESSION. `fill` ends its timeline at the last WORD, so a render
    /// with a silent tail legitimately stops short of the file. The old
    /// symmetric tolerance rejected exactly that — and because the estimate it
    /// fell back to spreads words across the FULL duration, the highlight
    /// trailed the voice and the timeline outran the speech.
    func testAlignmentEndingAtTheLastWordSurvivesASilentTail() {
        // Three words spoken over 3.2s, inside a 4.0s file: an 800ms tail.
        let timings = LocalAlignment.fill(
            expected: ["i", "went", "there"],
            pairing: [0, 1, 2],
            heardSpans: spans([(0.0, 0.9), (1.0, 2.0), (2.2, 3.2)]),
            durationMs: 4_000)
        XCTAssertEqual(timings.last?.endMs, 3_200)
        XCTAssertTrue(ShadowDrillView.fits(timings, durationMs: 4_000),
                      "a real alignment must never be thrown away for its silent tail")
    }

    /// The guard's actual job: a timeline from a DIFFERENT render, whose words
    /// keep going after this file has ended.
    func testTimelineRunningPastTheFileIsRejected() {
        let foreign = [WordTiming(word: "i", startMs: 0, endMs: 1_500),
                       WordTiming(word: "went", startMs: 1_500, endMs: 5_200)]
        XCTAssertFalse(ShadowDrillView.fits(foreign, durationMs: 4_000),
                       "words cannot end after the audio does")
    }

    /// Undershoot is tolerated, but not without limit — timings covering a
    /// sliver of the file describe some other, shorter line.
    func testTimelineCoveringAlmostNoneOfTheFileIsRejected() {
        let stub = [WordTiming(word: "i", startMs: 0, endMs: 900)]
        XCTAssertFalse(ShadowDrillView.fits(stub, durationMs: 4_000))
    }

    /// The write side must agree with the read side, or the cache never
    /// converges: `recoverTimings` persists only what a reload will accept.
    /// Anything `fill` produces from real spans has to clear that bar.
    func testFillOutputIsAcceptedAcrossRealisticTailLengths() {
        for tailMs in [0, 150, 400, 800] {
            let speechEnd = 3.2
            let durationMs = Int(speechEnd * 1000) + tailMs
            let timings = LocalAlignment.fill(
                expected: ["i", "went", "there"],
                pairing: [0, 1, 2],
                heardSpans: spans([(0.0, 0.9), (1.0, 2.0), (2.2, speechEnd)]),
                durationMs: durationMs)
            XCTAssertTrue(ShadowDrillView.fits(timings, durationMs: durationMs),
                          "a \(tailMs)ms tail would re-trigger alignment on every open")
        }
    }

    /// An unknown duration can't judge anything — keep what we have rather
    /// than drop to the estimate on a failed lookup.
    func testUnknownDurationAcceptsStoredTimings() {
        let timings = [WordTiming(word: "i", startMs: 0, endMs: 900)]
        XCTAssertTrue(ShadowDrillView.fits(timings, durationMs: 0))
        XCTAssertFalse(ShadowDrillView.fits([], durationMs: 0), "empty is never usable")
    }

    // MARK: - dropPreBeatWords

    /// The scored WAV opens before the 3-2-1, so anything said during the
    /// countdown used to score as insertions against the target line.
    func testWordsSpokenDuringTheCountdownAreDropped() {
        let timings = [WordTiming(word: "wait", startMs: 200, endMs: 700),      // countdown
                       WordTiming(word: "i", startMs: 2_500, endMs: 2_800),     // attempt
                       WordTiming(word: "went", startMs: 2_800, endMs: 3_300)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "wait i went", timings: timings, preRollMs: 2_450)
        XCTAssertEqual(out.timings.map(\.word), ["i", "went"])
        XCTAssertEqual(out.text, "i went")
    }

    /// A silent countdown — the overwhelmingly common case — must come
    /// through completely untouched, punctuation included.
    func testSilentCountdownLeavesTheTranscriptAlone() {
        let timings = [WordTiming(word: "i", startMs: 2_500, endMs: 2_800),
                       WordTiming(word: "went", startMs: 2_800, endMs: 3_300)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "I went.", timings: timings, preRollMs: 2_450)
        XCTAssertEqual(out.text, "I went.", "no drop must mean no rebuild")
        XCTAssertEqual(out.timings.count, 2)
    }

    /// Dropping a real first word is the failure the hot-mic start exists to
    /// prevent, so a word straddling the beat is kept.
    func testWordStraddlingTheBeatIsKept() {
        let timings = [WordTiming(word: "i", startMs: 2_300, endMs: 2_600),
                       WordTiming(word: "went", startMs: 2_600, endMs: 3_100)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "i went", timings: timings, preRollMs: 2_450)
        XCTAssertEqual(out.timings.map(\.word), ["i", "went"])
    }

    /// Only a LEADING run is cut — a mid-attempt word can never predate the
    /// beat, and filtering the whole array would desync it from the diff
    /// steps `analyzeRhythm` walks in lockstep.
    func testOnlyTheLeadingRunIsDropped() {
        let timings = [WordTiming(word: "um", startMs: 100, endMs: 500),
                       WordTiming(word: "i", startMs: 2_500, endMs: 2_800),
                       WordTiming(word: "eh", startMs: 2_900, endMs: 3_000),
                       WordTiming(word: "went", startMs: 3_100, endMs: 3_400)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "um i eh went", timings: timings, preRollMs: 2_450)
        XCTAssertEqual(out.timings.map(\.word), ["i", "eh", "went"])
    }

    /// No stamps (an older attempt, or a recorder that failed to open) means
    /// no cut — never guess at a pre-roll.
    func testMissingPreRollLeavesEverything() {
        let timings = [WordTiming(word: "i", startMs: 0, endMs: 300)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "i", timings: timings, preRollMs: 0)
        XCTAssertEqual(out.timings.count, 1)
        XCTAssertEqual(out.text, "i")
    }

    /// A learner who says nothing but clears their throat during the 3-2-1
    /// scores an empty attempt, not a wrong one.
    func testCountdownOnlySpeechLeavesNothingBehind() {
        let timings = [WordTiming(word: "ahem", startMs: 200, endMs: 700)]
        let out = ShadowDrillView.dropPreBeatWords(
            text: "ahem", timings: timings, preRollMs: 2_450)
        XCTAssertTrue(out.timings.isEmpty)
        XCTAssertEqual(out.text, "")
    }
}

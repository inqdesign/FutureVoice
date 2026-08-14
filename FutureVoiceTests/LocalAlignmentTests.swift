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

    // MARK: - recorder start boundary

    /// `prepare` must not capture anything. Shadow calls it before its 3-2-1
    /// so session activation and file setup are paid up front; if it started
    /// the file too, the countdown would land in the scored audio AND in the
    /// take the learner plays back — which is exactly the bug.
    @MainActor
    func testPrepareDoesNotStartCapturing() throws {
        let rec = AudioRecorder()
        defer { _ = rec.stop() }
        let url = try rec.prepare(quality: .sttOptimal)
        XCTAssertFalse(rec.isRecording, "prepare must arm, never record")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "the file is created up front so record() stays cheap")
    }

    /// And the beat actually starts it.
    @MainActor
    func testBeginPreparedStartsCapturing() throws {
        let rec = AudioRecorder()
        defer { _ = rec.stop() }
        _ = try rec.prepare(quality: .sttOptimal)
        try rec.beginPrepared()
        XCTAssertTrue(rec.isRecording)
    }

    /// `beginPrepared` runs on the go beat, which a learner can reach twice if
    /// an attempt is restarted — it must not throw away what is being captured.
    @MainActor
    func testBeginPreparedIsIdempotent() throws {
        let rec = AudioRecorder()
        defer { _ = rec.stop() }
        _ = try rec.prepare(quality: .sttOptimal)
        try rec.beginPrepared()
        XCTAssertNoThrow(try rec.beginPrepared())
        XCTAssertTrue(rec.isRecording)
    }
}

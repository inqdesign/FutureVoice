import XCTest
@testable import FutureVoice

/// The scored words now come from one reader and the word times from another,
/// so the join between them is the new load-bearing part: `analyzeRhythm`
/// refuses to run unless there is exactly one timing per word of the scored
/// text, in order.
final class ShadowTranscriberTests: XCTestCase {

    private func timing(_ word: String, _ startMs: Int, _ endMs: Int) -> WordTiming {
        WordTiming(word: word, startMs: startMs, endMs: endMs)
    }

    /// A word the recognizer dropped still gets a time, carried from the
    /// anchors around it — and the words it DID hear keep their real ones.
    func testWordsTheRecognizerMissedStillGetTimes() {
        let device = [timing("soak", 0, 400), timing("all", 600, 800),
                      timing("in", 800, 1_000), timing("right", 1_200, 1_500)]
        let words = ["Soak", "it", "all", "in,", "right?"]
        let out = ShadowTranscriber.realigned(words: words, onto: device)

        XCTAssertEqual(out.map(\.word), words)
        XCTAssertEqual(out.first?.startMs, 0)         // anchored on "soak"
        XCTAssertEqual(out.last?.startMs, 1_200)      // anchored on "right"
        XCTAssertEqual(out.last?.endMs, 1_500)
        // "it" was never recognized: it sits in the gap, in order, no overlap.
        XCTAssertGreaterThanOrEqual(out[1].startMs, 400)
        XCTAssertLessThanOrEqual(out[1].endMs, 600)
        for (a, b) in zip(out, out.dropFirst()) {
            XCTAssertLessThanOrEqual(a.endMs, b.startMs)
            XCTAssertLessThan(a.startMs, a.endMs)
        }
    }

    /// The reported case — "Soak it all in, right?" recognized as "So right".
    /// The audio reader supplies the words, but two timestamps cannot place
    /// five of them, so the rhythm card is dropped rather than graded against
    /// interpolation. It used to be graded against "So right" itself, which
    /// was a number about a sentence the learner never said.
    func testTheReportedCaseKeepsTheWordsAndDropsTheRhythm() {
        let device = [timing("So", 0, 300), timing("right", 1_200, 1_500)]
        XCTAssertTrue(
            ShadowTranscriber.realigned(words: ["Soak", "it", "all", "in,", "right?"],
                                        onto: device).isEmpty)
    }

    /// Punctuation and case must not stop a word from anchoring — the audio
    /// reader writes "in," where the recognizer segment is "in".
    func testPunctuationDoesNotBlockAnAnchor() {
        let device = [timing("soak", 0, 400), timing("it", 400, 550),
                      timing("all", 550, 700), timing("in", 700, 900)]
        let out = ShadowTranscriber.realigned(words: ["Soak", "it", "all", "in,"], onto: device)
        XCTAssertEqual(out.map(\.startMs), [0, 400, 550, 700])
    }

    /// Under half the words anchoring means the timeline is mostly
    /// interpolation, and rhythm graded against interpolation is invented.
    /// Empty is the honest answer — the card just stays hidden.
    func testTooLittleAnchoringReturnsNothing() {
        let device = [timing("completely", 0, 500), timing("different", 500, 900)]
        XCTAssertTrue(
            ShadowTranscriber.realigned(words: ["Soak", "it", "all", "in,", "right?"],
                                        onto: device).isEmpty)
    }

    func testNoDeviceTimingsReturnsNothing() {
        XCTAssertTrue(ShadowTranscriber.realigned(words: ["one", "two"], onto: []).isEmpty)
    }

    // MARK: - The headline number

    /// The complaint that started this: every word right, every beat late.
    /// The word score cannot see it at all, so the headline used to be 100.
    func testPerfectWordsOffTheBeatNoLongerScoresPerfect() {
        XCTAssertEqual(ShadowEngine.overallScore(match: 100, rhythm: 100), 100)
        XCTAssertEqual(ShadowEngine.overallScore(match: 100, rhythm: 40), 79)
    }

    /// nil is "we could not measure it", never zero — grading someone on a
    /// measurement the app failed to take is worse than not grading it.
    func testUnmeasurableRhythmLeavesTheWordScoreAlone() {
        XCTAssertEqual(ShadowEngine.overallScore(match: 89, rhythm: nil), 89)
        XCTAssertNotEqual(ShadowEngine.overallScore(match: 89, rhythm: nil),
                          ShadowEngine.overallScore(match: 89, rhythm: 0))
    }

    /// Words still lead: a take with the wrong words is wrong however
    /// beautifully it was timed.
    func testWordsOutweighRhythm() {
        XCTAssertLessThan(ShadowEngine.overallScore(match: 40, rhythm: 100),
                          ShadowEngine.overallScore(match: 100, rhythm: 40))
    }

    /// Every attempt on a phone today predates `rhythmScore`, so none of
    /// their saved numbers may move.
    func testAttemptsSavedBeforeRhythmKeepTheirScore() {
        let old = ShadowAttempt(turnId: UUID(), targetText: "Soak it all in, right?",
                                learnerTranscript: "Soak it all in, right?",
                                recordingFilename: nil, matchScore: 92, rhythmScore: nil,
                                pronunciation: "", pacing: "", fix: "")
        XCTAssertEqual(old.overallScore, 92)
    }

    /// The split has to be whitespace-only: `ShadowEngine.tokenSpans` assumes
    /// it, and a word map that disagrees with the diff's token stream is what
    /// makes `analyzeRhythm` return nil.
    func testWordSplitMatchesTheDiffsWordUnit() {
        let text = "Speech-to-text  isn't\nperfect"
        XCTAssertEqual(ShadowTranscriber.words(of: text),
                       ["Speech-to-text", "isn't", "perfect"])
        XCTAssertEqual(ShadowEngine.tokenSpans(for: ShadowTranscriber.words(of: text)).count, 3)
    }
}

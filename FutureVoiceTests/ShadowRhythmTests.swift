import XCTest
@testable import FutureVoice

/// The rhythm card may only grade a beat somebody measured. Every target
/// timeline for a live-call line starts as a character-count estimate, and
/// both alignments share out unrecognized words across gaps — none of which
/// used to be distinguishable from a measurement once it reached
/// `analyzeRhythm`.
final class ShadowRhythmTests: XCTestCase {

    private func t(_ word: String, _ start: Int, measured: Bool = true) -> WordTiming {
        WordTiming(word: word, startMs: start, endMs: start + 200, isMeasured: measured)
    }

    private func steps(_ words: [String]) -> [ShadowEngine.DiffStep] {
        words.map { .init(op: .match, target: $0, learner: $0) }
    }

    private let line = ["one", "two", "three", "four", "five"]

    /// A perfectly-timed take against a measured target scores 100 and every
    /// word is judged.
    func testMeasuredOnBothSidesIsGraded() {
        let r = ShadowEngine.analyzeRhythm(
            steps: steps(line),
            targetTimings: line.enumerated().map { t($1, $0 * 500) },
            learnerTimings: line.enumerated().map { t($1, 1_000 + $0 * 700) })
        XCTAssertEqual(r?.score, 100)
        XCTAssertEqual(r?.words.filter(\.isMeasured).count, 5)
    }

    /// The reported case: a line from a live call has no stored timings, so
    /// the karaoke runs on the estimate — and the card used to grade against
    /// it. An estimate throughout is no rhythm at all.
    func testEstimatedTargetYieldsNoRhythm() {
        let target = ShadowDrillView.estimatedTimings(for: line.joined(separator: " "),
                                                      durationMs: 2_500)
        XCTAssertTrue(target.allSatisfy { !$0.isMeasured })
        let r = ShadowEngine.analyzeRhythm(
            steps: steps(line),
            targetTimings: target,
            learnerTimings: line.enumerated().map { t($1, $0 * 500) })
        XCTAssertNil(r)
        // …and `overallScore` then leaves the word score alone.
        XCTAssertEqual(ShadowEngine.overallScore(match: 80, rhythm: r?.score), 80)
    }

    /// A word the learner's recognizer never placed is drawn but carries no
    /// credit and no verdict — however far off its interpolated onset lands.
    func testInterpolatedLearnerWordIsPlacedButNotJudged() {
        var learner = line.enumerated().map { t($1, $0 * 500) }
        learner[2] = t("three", 1_400, measured: false)   // 400 ms "late", never measured
        let r = ShadowEngine.analyzeRhythm(
            steps: steps(line),
            targetTimings: line.enumerated().map { t($1, $0 * 500) },
            learnerTimings: learner)
        XCTAssertEqual(r?.words.count, 5)
        XCTAssertEqual(r?.words[2].isMeasured, false)
        XCTAssertEqual(r?.score, 100)
        XCTAssertEqual(ShadowEngine.renderRhythmForPrompt(r), "all words on beat")
    }

    /// Three measured pairs is the two that pin the normalization plus ONE
    /// judged word; the bar is four.
    func testNeedsFourMeasuredPairs() {
        func run(measured: Int) -> ShadowEngine.RhythmAnalysis? {
            let target = line.enumerated().map { t($1, $0 * 500, measured: $0 < measured) }
            return ShadowEngine.analyzeRhythm(
                steps: steps(line), targetTimings: target,
                learnerTimings: line.enumerated().map { t($1, $0 * 500) })
        }
        XCTAssertNil(run(measured: 3))
        XCTAssertNotNil(run(measured: 4))
    }

    /// The normalization is pinned on measured words only — an interpolated
    /// first word must not become the zero both timelines are read from.
    func testUnmeasuredEndsDoNotPinTheNormalization() {
        var target = line.enumerated().map { t($1, $0 * 500) }
        target[0] = t("one", 0, measured: false)
        var learner = line.enumerated().map { t($1, 2_000 + $0 * 500) }
        learner[0] = t("one", 900, measured: false)   // a wild guess, 1.1 s early
        let r = ShadowEngine.analyzeRhythm(steps: steps(line),
                                           targetTimings: target, learnerTimings: learner)
        XCTAssertEqual(r?.score, 100)
        XCTAssertEqual(r?.words[1].targetOnsetMs, 0)
        XCTAssertEqual(r?.words[1].learnerOnsetMs, 0)
    }

    /// Timings cached before the flag existed decode as measured — they
    /// passed the anchor gate when they were written, and refusing them
    /// would hide the card on every line already on disk.
    func testTimingsFromDiskDefaultToMeasured() throws {
        let json = #"[{"word":"hi","startMs":0,"endMs":300}]"#.data(using: .utf8)!
        let out = try JSONDecoder().decode([WordTiming].self, from: json)
        XCTAssertEqual(out.first?.isMeasured, true)
        let round = try JSONDecoder().decode(
            [WordTiming].self,
            from: JSONEncoder().encode([WordTiming(word: "hi", startMs: 0, endMs: 300, isMeasured: false)]))
        XCTAssertEqual(round.first?.isMeasured, false)
    }
}

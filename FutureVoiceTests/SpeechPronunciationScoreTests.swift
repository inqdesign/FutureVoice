import XCTest
@testable import FutureVoice

/// 2026-11-04: pronunciation is a quarter of a speech take's overall.
final class SpeechPronunciationScoreTests: XCTestCase {

    private let script = "Sound is a wave of tiny changes in pressure. It travels through the air to your ears."
    private let env = SpeechAnalyzer.Envelope(firstVoice: 0, lastVoice: 6.5, silences: [0.4],
                                              phrases: [(-20, -21), (-20, -22)])

    func testWithoutPronunciationTheOldWeightingStands() {
        let m = SpeechAnalyzer.analyze(script: script, transcript: script, language: "en", envelope: env)
        XCTAssertNil(m.pronunciation)
        XCTAssertEqual(m.scoring, SpeechAnalyzer.scoringWithoutPronunciation)
        let old = Int((0.40 * Double(m.accuracy) + 0.20 * Double(m.paceScore) + 0.15 * Double(m.pauseScore)
                       + 0.10 * Double(m.fillerScore) + 0.15 * Double(m.steadiness)).rounded())
        XCTAssertEqual(m.overall, old)
    }

    func testPronunciationIsAQuarterOfTheOverall() {
        let m = SpeechAnalyzer.analyze(script: script, transcript: script, language: "en",
                                       envelope: env, pronunciation: 80)
        XCTAssertEqual(m.pronunciation, 80)
        XCTAssertEqual(m.scoring, SpeechAnalyzer.scoringVersion)
        let expected = Int((0.30 * Double(m.accuracy) + 0.25 * 80 + 0.15 * Double(m.paceScore)
                            + 0.10 * Double(m.pauseScore) + 0.10 * Double(m.fillerScore)
                            + 0.10 * Double(m.steadiness)).rounded())
        XCTAssertEqual(m.overall, expected)
    }

    func testAPerfectReadNeedsPerfectSoundsForAHundred() {
        // Every other part full: 96 on the sounds is 99, not 100.
        XCTAssertEqual(SpeechAnalyzer.overall(accuracy: 100, pace: 100, pause: 100, filler: 100,
                                              steadiness: 100, coverage: 1, pronunciation: 96), 99)
        XCTAssertEqual(SpeechAnalyzer.overall(accuracy: 100, pace: 100, pause: 100, filler: 100,
                                              steadiness: 100, coverage: 1, pronunciation: 80), 95)
        XCTAssertEqual(SpeechAnalyzer.overall(accuracy: 100, pace: 100, pause: 100, filler: 100,
                                              steadiness: 100, coverage: 1, pronunciation: 100), 100)
    }

    func testPronunciationIsScaledByCoverageLikeDelivery() {
        // Half the script read: only the accuracy part is whole.
        let half = SpeechAnalyzer.overall(accuracy: 50, pace: 100, pause: 100, filler: 100,
                                          steadiness: 100, coverage: 0.5, pronunciation: 100)
        XCTAssertEqual(half, Int((0.30 * 50 + 0.5 * 70).rounded()))
    }
}

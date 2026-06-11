import XCTest
@testable import FutureVoice

final class ShadowEngineTests: XCTestCase {

    func testPerfectMatchScores100() {
        let a = ShadowEngine.analyze(target: "hello world how are you",
                                     learner: "hello world how are you")
        XCTAssertEqual(a.score, 100)
        XCTAssertEqual(a.matchCount, 5)
        XCTAssertTrue(a.steps.allSatisfy { $0.op == .match })
    }

    func testCaseAndPunctuationInsensitive() {
        let a = ShadowEngine.analyze(target: "Hello, world!", learner: "hello world")
        XCTAssertEqual(a.score, 100)
    }

    func testEmptyLearnerScoresZero() {
        let a = ShadowEngine.analyze(target: "hello world", learner: "")
        XCTAssertEqual(a.score, 0)
        XCTAssertEqual(a.matchCount, 0)
        XCTAssertTrue(a.steps.allSatisfy { $0.op == .del })
    }

    func testSingleSubstitutionDetected() {
        let a = ShadowEngine.analyze(target: "I went to the bank",
                                     learner: "I go to the bank")
        XCTAssertEqual(a.matchCount, 4)
        // sqrt(4/5) * 100 ≈ 89
        XCTAssertEqual(a.score, 89)
        let subs = a.steps.filter { $0.op == .sub }
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.target, "went")
        XCTAssertEqual(subs.first?.learner, "go")
    }

    func testInsertionAndDeletionOps() {
        let a = ShadowEngine.analyze(target: "the weather is nice today",
                                     learner: "the weather nice today actually")
        XCTAssertTrue(a.steps.contains { $0.op == .del && $0.target == "is" })
        XCTAssertTrue(a.steps.contains { $0.op == .ins && $0.learner == "actually" })
    }

    func testSqrtCurveSoftensBottom() {
        // 1 of 4 matched: raw 0.25 → curved 0.5 → 50, not 25.
        let a = ShadowEngine.analyze(target: "alpha beta gamma delta",
                                     learner: "alpha xx yy zz")
        XCTAssertEqual(a.score, 50)
    }
}

final class ScorecardMetricsTests: XCTestCase {

    private func turn(_ role: TurnRole, _ text: String, ms: Int = 0,
                      suggestion: TurnSuggestion? = nil) -> Turn {
        Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
             durationMs: ms, timestamp: Date(), suggestion: suggestion)
    }

    func testWordsPerMinuteAndCounts() {
        // 6 user words over 6 seconds of speech = 60 wpm.
        let turns = [
            turn(.user, "one two three", ms: 3000),
            turn(.fluentSelf, "this should not count", ms: 9999),
            turn(.user, "four five six", ms: 3000),
        ]
        let m = ScorecardMetrics.compute(turns: turns)
        XCTAssertEqual(m.userTurnCount, 2)
        XCTAssertEqual(m.userWordCount, 6)
        XCTAssertEqual(m.uniqueWordCount, 6)
        XCTAssertEqual(m.wordsPerMinute, 60, accuracy: 0.01)
        XCTAssertEqual(m.typeTokenRatio, 1.0, accuracy: 0.001)
    }

    func testSuggestionRate() {
        let s = TurnSuggestion(alternative: "I went there", reason: "past tense")
        let turns = [
            turn(.user, "I go there yesterday", suggestion: s),
            turn(.user, "that was fun"),
        ]
        let m = ScorecardMetrics.compute(turns: turns)
        XCTAssertEqual(m.suggestionCount, 1)
        XCTAssertEqual(m.suggestionRate, 0.5, accuracy: 0.001)
    }

    func testNoTimingMeansZeroWpm() {
        let m = ScorecardMetrics.compute(turns: [turn(.user, "hello there", ms: 0)])
        XCTAssertEqual(m.wordsPerMinute, 0)
    }
}

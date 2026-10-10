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

    /// A model-written target carries a typographic apostrophe; every
    /// recognizer writes the ASCII one. Both must expand to the same tokens
    /// or "I’m" against "I'm" is a substitution the learner never made.
    func testCurlyApostropheMatchesAsciiContraction() {
        let a = ShadowEngine.analyze(target: "I\u{2019}m building it, don\u{2019}t worry",
                                     learner: "I'm building it, don't worry")
        XCTAssertEqual(a.score, 100, "\(a.steps)")
        let b = ShadowEngine.analyze(target: "I\u{2019}m building it",
                                     learner: "I am building it")
        XCTAssertEqual(b.score, 100, "\(b.steps)")
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

    // Korean is scored by eojeol (scripts/shadow-ko-probe.py, 2026-10-10).
    func testKoreanDroppedWordCostsAWord() {
        let a = ShadowEngine.analyze(target: "어제 친구랑 같이 영화를 봤어요.",
                                     learner: "어제 친구랑 영화를 봤어요", language: "ko")
        XCTAssertEqual(a.score, 89)   // 4 of 5 words; by syllable it read 92
    }

    func testKoreanWrongParticleFailsItsWord() {
        let a = ShadowEngine.analyze(target: "어제 친구랑 같이 영화를 봤어요.",
                                     learner: "어제 친구랑 같이 영화가 봤어요", language: "ko")
        XCTAssertEqual(a.score, 89)   // by syllable it read 96
    }

    func testKoreanSpacingIsStillTheRecognizers() {
        let a = ShadowEngine.analyze(target: "커피 한잔 할래?",
                                     learner: "커피 한 잔 할래", language: "ko")
        XCTAssertEqual(a.score, 100)
        let b = ShadowEngine.analyze(target: "커피 한 잔 할래?",
                                     learner: "커피 한잔할래", language: "ko")
        XCTAssertEqual(b.score, 100)
    }

    func testKoreanExtraSpeechCountsAgainst() {
        let a = ShadowEngine.analyze(target: "학교 끝나고 갈 거야",
                                     learner: "학교 수업 끝나고 갈 거야", language: "ko")
        XCTAssertLessThan(a.score, 100)
        XCTAssertGreaterThan(a.score, 80)
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

import XCTest
@testable import FutureVoice

/// The goodbye's facts are decided in code so the model can't praise a line
/// that carried a mistake or set a slip already fixed as homework — the two
/// things the first samples got wrong (2026-11-12).
@MainActor
final class CallGoodbyeTests: XCTestCase {

    private func turn(_ text: String, role: TurnRole = .user, fixes: [TurnFix]? = []) -> Turn {
        let suggestion = fixes.map { TurnSuggestion(alternative: text, reason: "", fixes: $0) }
        return Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
                    durationMs: 0, timestamp: Date(), suggestion: suggestion)
    }

    private func fix(_ was: String, _ now: String) -> TurnFix {
        TurnFix(was: was, now: now, why: "")
    }

    func testASlipSaidRightLaterIsPraiseNotATip() {
        let turns = [
            turn("I always look for ways to help before I even asked",
                 fixes: [fix("before I even asked", "before I'm even asked")]),
            turn("before I'm even asked, I always look for ways to help"),
            turn("If passenger get frustrated I will listen calmly",
                 fixes: [fix("I will listen calmly", "I'd listen calmly")]),
        ]
        let facts = CallGoodbye.facts(turns: turns, wordsUsed: [], target: "en")
        XCTAssertEqual(facts?.fixedSlips.map(\.now), ["before I'm even asked"])
        XCTAssertEqual(facts?.openSlips.map(\.now), ["I'd listen calmly"])
    }

    /// A line with a correction is never offered as praise; a clean one of
    /// five words or more is.
    func testOnlyCleanLinesCanBePraised() {
        let turns = [
            turn("We actually do with the language tech",
                 fixes: [fix("do with the language tech", "use language tech")]),
            turn("I'm a solo founder based in Munich"),
            turn("Yes okay"),
        ]
        let facts = CallGoodbye.facts(turns: turns, wordsUsed: [], target: "en")
        XCTAssertEqual(facts?.cleanLines, ["I'm a solo founder based in Munich"])
    }

    /// A turn whose correction never arrived says nothing either way.
    func testAnUncheckedTurnIsNeitherCleanNorASlip() {
        let turns = [
            turn("I went to the market yesterday morning", fixes: nil),
            turn("and I bought some fresh bread there", fixes: nil),
            turn("it was really good and cheap too", fixes: nil),
        ]
        XCTAssertNil(CallGoodbye.facts(turns: turns, wordsUsed: [], target: "en"))
        let withWord = CallGoodbye.facts(turns: turns, wordsUsed: ["fresh"], target: "en")
        XCTAssertEqual(withWord?.wordsUsed, ["fresh"])
        XCTAssertEqual(withWord?.cleanLines, [])
    }

    func testTooShortACallGetsNoGoodbye() {
        let turns = [turn("I'm a solo founder based in Munich"), turn("hello there friend how are you", role: .fluentSelf)]
        XCTAssertNil(CallGoodbye.facts(turns: turns, wordsUsed: [], target: "en"))
    }

    func testQuestionsAreCut() {
        XCTAssertEqual(CallGoodbye.withoutQuestions("You got it right. Want to try again next time? Bye!"),
                       "You got it right. Bye!")
        XCTAssertEqual(CallGoodbye.withoutQuestions("よくできたね。また練習する？じゃあね。"),
                       "よくできたね。じゃあね。")
        XCTAssertEqual(CallGoodbye.withoutQuestions("Want to go again?"), "")
    }
}

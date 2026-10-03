import XCTest
@testable import FutureVoice

/// The beginner question rules ride only on A1/A2 prompts; every other
/// level's prompt is unchanged (2026-10-03).
final class BeginnerQuestionTests: XCTestCase {

    private func prompt(_ level: CEFRLevel) -> String {
        ConversationEngine.conversationSystemPrompt(
            targetLanguage: "en", nativeLanguage: "ko", level: level,
            topPatterns: [], weakVocabAreas: [], topic: "")
    }

    func testBeginnersGetTheQuestionRules() {
        XCTAssertTrue(prompt(.a1).contains("THIS LEARNER IS A BEGINNER (A1)"))
        XCTAssertTrue(prompt(.a2).contains("THIS LEARNER IS A BEGINNER (A2)"))
    }

    func testOtherLevelsAreUntouched() {
        for level in [CEFRLevel.b1, .b2, .c1, .c2] {
            XCTAssertFalse(prompt(level).contains("BEGINNER"))
            XCTAssertTrue(prompt(level).hasSuffix("(1) is only about not monologuing."))
        }
    }
}

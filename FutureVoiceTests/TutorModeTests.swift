import XCTest
@testable import FutureVoice

/// Tutor mode rides only on a call that turned it on; every other prompt is
/// unchanged (2026-10-13).
final class TutorModeTests: XCTestCase {

    private func prompt(_ lang: String, tutor: Bool, level: CEFRLevel = .b1) -> String {
        ConversationEngine.conversationSystemPrompt(
            targetLanguage: lang, nativeLanguage: "ko", level: level,
            topPatterns: [], weakVocabAreas: [], topic: "", tutor: tutor)
    }

    func testOffLeavesThePromptAlone() {
        let off = prompt("en", tutor: false)
        XCTAssertFalse(off.contains("TUTOR MODE"))
        XCTAssertTrue(off.contains("Never correct the user mid-conversation."))
        XCTAssertTrue(off.hasSuffix("(1) is only about not monologuing."))
    }

    func testOnReplacesTheNoCorrectionRuleAndComesLast() {
        for level in [CEFRLevel.a2, .b1] {
            let on = prompt("en", tutor: true, level: level)
            XCTAssertFalse(on.contains("Never correct the user mid-conversation."))
            XCTAssertTrue(on.contains("TUTOR MODE"))
            // Last, after the beginner rules it outranks.
            XCTAssertTrue(on.hasSuffix("All of it in English only, like everything else."))
        }
    }

    func testCarriesTheLanguageGuards() {
        XCTAssertTrue(prompt("ko", tutor: true).contains("ASR SPACING GUARD"))
        XCTAssertTrue(prompt("ko", tutor: true).contains("SPEECH LEVEL is the learner's choice"))
    }
}

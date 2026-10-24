import XCTest
@testable import FutureVoice

/// Tutor mode rides only on a call that turned it on; every other prompt is
/// unchanged (2026-10-13).
final class TutorModeTests: XCTestCase {

    private func prompt(_ lang: String, tutor: Bool, level: CEFRLevel = .b1,
                        lesson: TutorLesson? = nil, ticked: Bool = false,
                        fixes: [String] = []) -> String {
        ConversationEngine.conversationSystemPrompt(
            targetLanguage: lang, nativeLanguage: "ko", level: level,
            topPatterns: [], weakVocabAreas: [], topic: "", tutor: tutor,
            tutorLesson: lesson, tutorJustTicked: ticked, tutorLastFixes: fixes)
    }

    private func lesson(done: Int, of total: Int = 3) -> TutorLesson {
        TutorLesson(id: UUID(), title: "자기소개", titleTarget: "Introducing yourself",
                    language: "en",
                    challenges: (0..<total).map { i in
                        .init(id: UUID(), goal: "goal \(i)", task: "Task \(i)",
                              example: "Example \(i).", doneAt: i < done ? Date() : nil,
                              line: i < done ? "line \(i)" : nil)
                    },
                    createdAt: Date())
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

    func testNoLessonAsksForATopicAndDropsTheFreeTalkBlocks() {
        let on = prompt("en", tutor: true)
        XCTAssertTrue(on.contains("NO TOPIC YET"))
        XCTAssertFalse(on.contains("THEY CALLED YOU"))
    }

    func testLessonMarksTheCurrentChallengeAndTheTick() {
        let mid = prompt("en", tutor: true, lesson: lesson(done: 1), ticked: true,
                         fixes: ["\"I am live\" → \"I live\""])
        XCTAssertTrue(mid.contains("[DONE] 1. Task 0"))
        XCTAssertTrue(mid.contains("[NOW ] 2. Task 1"))
        XCTAssertTrue(mid.contains("You are on challenge 2"))
        XCTAssertTrue(mid.contains("just checked off challenge 1"))
        XCTAssertTrue(mid.contains("I am live"))
        let quiet = prompt("en", tutor: true, lesson: lesson(done: 1))
        XCTAssertFalse(quiet.contains("just checked off"))
    }

    func testFinishedLessonSaysGoodbye() {
        let l = lesson(done: 3)
        XCTAssertTrue(l.isFinished)
        XCTAssertEqual(l.record.done.count, 3)
        XCTAssertTrue(prompt("en", tutor: true, lesson: l).contains("ALL DONE"))
    }
}

import XCTest
@testable import FutureVoice

/// Tutor mode rides only on a call that turned it on; every other prompt is
/// unchanged (2026-10-13).
final class TutorModeTests: XCTestCase {

    private func prompt(_ lang: String, tutor: Bool, level: CEFRLevel = .b1,
                        lesson: TutorLesson? = nil, ticked: Bool = false,
                        fixes: [String] = [], planning: Bool = false) -> String {
        ConversationEngine.conversationSystemPrompt(
            targetLanguage: lang, nativeLanguage: "ko", level: level,
            topPatterns: [], weakVocabAreas: [], topic: "", tutor: tutor,
            tutorLesson: lesson, tutorJustTicked: ticked, tutorLastFixes: fixes,
            tutorPlanning: planning)
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
        var l = lesson(done: 3)
        l.finishedAt = Date()
        XCTAssertTrue(l.isFinished)
        XCTAssertEqual(l.record.done.count, 3)
        let p = prompt("en", tutor: true, lesson: l)
        XCTAssertTrue(p.contains("ALL DONE"))
        XCTAssertTrue(p.contains("never call it great, perfect or flawless"))
    }

    /// Every challenge ticked is not the end: the final check is
    /// (founder, 2026-10-28). The tutor asks for it all, gives nothing, and
    /// waits for the app's verdict.
    func testLastTickOpensTheFinalCheck() {
        let l = lesson(done: 3)
        XCTAssertFalse(l.isFinished)
        XCTAssertTrue(l.inFinalCheck)
        let p = prompt("en", tutor: true, lesson: l, ticked: true)
        XCTAssertTrue(p.contains("Now the FINAL CHECK"))
        XCTAssertTrue(p.contains("They can't skip it"))
        XCTAssertTrue(p.contains("start the FINAL CHECK above"))
        XCTAssertFalse(p.contains("ALL DONE"))
    }

    /// Only a try is judged; talking and asking for help are answered as
    /// conversation, and an answer from an older judge with no kind is a try.
    func testJudgeTellsATryFromTalkAndHelp() throws {
        func kind(_ json: String) throws -> TutorJudge.Verdict.Kind {
            try JSONDecoder().decode(TutorJudge.Verdict.self, from: Data(json.utf8)).turnKind
        }
        XCTAssertEqual(try kind(#"{"kind":"talk","done":false}"#), .talk)
        XCTAssertEqual(try kind(#"{"kind":"help","done":false}"#), .help)
        XCTAssertEqual(try kind(#"{"kind":"try","done":true}"#), .attempt)
        XCTAssertEqual(try kind(#"{"done":false}"#), .attempt)
    }

    func testTutorIsAConversationPartnerFirst() {
        let p = prompt("en", tutor: true, lesson: lesson(done: 1))
        XCTAssertTrue(p.contains("be a real conversation partner"))
        XCTAssertTrue(p.contains("Not a try (the note says so)"))
        XCTAssertFalse(p.contains("Don't wander off the lesson"))
    }

    func testFinalCheckOutcome() {
        typealias V = TutorFinalCheck.Verdict
        func o(_ v: V, slips: Int = 0, used: Bool = false) -> TutorFinalCheck.Outcome {
            TutorFinalCheck.outcome(v, slips: slips, onceMoreUsed: used)
        }
        XCTAssertEqual(o(V(attempt: false)), .notAnAttempt)
        XCTAssertEqual(o(V(attempt: true, missing: [2], understood: true)), .notYet)
        XCTAssertEqual(o(V(attempt: true, missing: [], understood: false)), .notYet)
        // A clean first try passes.
        XCTAssertEqual(o(V(attempt: true, missing: [], understood: true, shaky: false)), .pass)
        // Not perfect the first time (any slip, or shaky) asks once more, once.
        XCTAssertEqual(o(V(attempt: true, understood: true, shaky: false), slips: 1), .onceMore)
        XCTAssertEqual(o(V(attempt: true, understood: true, shaky: true)), .onceMore)
        // The second try passes with slips; they are named, not failed.
        XCTAssertEqual(o(V(attempt: true, understood: true, shaky: false), slips: 2, used: true), .pass)
        XCTAssertEqual(o(V(attempt: true, understood: true, shaky: true), used: true), .pass)
    }

    func testCurriculumNextPrefersAnOpenCheckThenLitTopics() {
        XCTAssertEqual(TutorCurriculum.chapters.count, 10)
        XCTAssertEqual(Set(TutorCurriculum.chapters.flatMap { $0.topics.map(\.id) }).count, 100)
        XCTAssertEqual(TutorCurriculum.next(progress: [:], level: .a1)?.topic.id, "meet.intro")
        var p: [String: TutorTopicProgress] = ["meet.intro": .init(passedAt: Date(), rounds: 1, touchedAt: Date())]
        XCTAssertEqual(TutorCurriculum.next(progress: p, level: .a1)?.topic.id, "meet.work")
        p["cafe.order"] = .init(startedAt: Date(), lessonDoneAt: Date(), touchedAt: Date())
        XCTAssertEqual(TutorCurriculum.next(progress: p, level: .a1)?.topic.id, "cafe.order")
        let stepUp = TutorCurriculum.topic("cafe.wrong")!.topic
        XCTAssertTrue(TutorCurriculum.isStepUp(stepUp, level: .a2))
        XCTAssertFalse(TutorCurriculum.isStepUp(stepUp, level: .b1))
    }

    /// While the next round is written, the finished lesson's "ask more or
    /// another topic" must not stand: the tutor ran a round of its own and
    /// the ready note sent it back to the start (2026-10-28).
    func testNextRoundBeingPlannedHoldsTheTutor() {
        var passed = lesson(done: 3)
        passed.finishedAt = Date()
        let p = prompt("en", tutor: true, lesson: passed, ticked: true, planning: true)
        XCTAssertTrue(p.contains("BEING SET UP"))
        XCTAssertTrue(p.contains("next round of \"Introducing yourself\""))
        XCTAssertFalse(p.contains("ALL DONE"))
        XCTAssertFalse(p.contains("has just checked off"))
    }

    // MARK: - What a tutor call counts (2026-10-28)

    private func line(_ text: String, _ role: TutorTurnRole?) -> Turn {
        var t = Turn(id: UUID(), role: .user, audioURL: nil, transcript: text,
                     durationMs: 2000, timestamp: Date(), suggestion: nil)
        t.tutorRole = role
        return t
    }

    private func session(_ turns: [Turn], coached: Bool? = nil) -> Session {
        Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                topic: nil, startedAt: Date(), endedAt: Date(), turns: turns,
                summary: nil, coached: coached)
    }

    func testOnlyTheFinalCheckIsEvidence() {
        XCTAssertFalse(line("My name is Min.", .drill).isEvidence)
        XCTAssertTrue(line("Hi, I'm Min, from Seoul, I work in design.", .check).isEvidence)
        XCTAssertTrue(line("Just talking.", nil).isEvidence)
    }

    func testATutorCallIsScoredOnlyOnceItReachedTheCheck() {
        let drills = session([line("My name is Min.", .drill), line("I'm from Seoul.", .drill)])
        XCTAssertTrue(drills.isPractice)
        XCTAssertFalse(drills.isLevelEvidence)

        let checked = session([line("My name is Min.", .drill),
                               line("Hi, I'm Min, I'm from Seoul.", .check)])
        XCTAssertFalse(checked.isPractice)
        XCTAssertTrue(checked.isLevelEvidence)
        XCTAssertEqual(ScorecardMetrics.compute(turns: checked.turns).userTurnCount, 1)

        // A tutor call saved before the per-line rule stays practice.
        XCTAssertTrue(session(checked.turns, coached: true).isPractice)
    }

    func testDrillLinesAreLabelledForTheSummary() {
        let text = ConversationEngine.formatTranscript([line("My name is Min.", .drill),
                                                        line("Hi, I'm Min.", .check)])
        XCTAssertEqual(text, "[USER_DRILL] My name is Min.\n[USER] Hi, I'm Min.")
    }

    func testTutorRoleRoundTrips() throws {
        let data = try JSONEncoder().encode(line("Hi.", .check))
        XCTAssertEqual(try JSONDecoder().decode(Turn.self, from: data).tutorRole, .check)
        let plain = try JSONEncoder().encode(line("Hi.", nil))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("tutorRole"))
    }
}

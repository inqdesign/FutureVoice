import XCTest
@testable import FutureVoice

/// `TeleprompterScript` decides what the learner reads on their own turn.
/// Three things it must never get wrong: a turn's own correction outranks
/// everything, a phrase fix goes back where it was SAID (not onto the end of
/// the line), and only a line that is review material carries the id a
/// passing read is filed under.
@MainActor
final class TeleprompterScriptTests: XCTestCase {

    private func turn(_ text: String,
                      role: TurnRole = .user,
                      suggestion: TurnSuggestion? = nil,
                      misheard: Bool = false,
                      id: UUID = UUID()) -> Turn {
        var t = Turn(id: id, role: role, audioURL: nil, transcript: text,
                     durationMs: 0, timestamp: Date(), suggestion: suggestion)
        t.excludedFromScoring = misheard
        return t
    }

    private func session(_ turns: [Turn], fixes: [PhraseFeedback] = []) -> Session {
        let summary = SessionSummary(phrasesUsed: fixes, newPatternsDetected: [],
                                     suggestedDrills: [], overallNote: "",
                                     scorecard: nil)
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                       mode: .conversation, topic: "Interview",
                       startedAt: Date().addingTimeInterval(-300),
                       endedAt: Date(), turns: turns,
                       summary: fixes.isEmpty ? nil : summary)
    }

    // MARK: - What lands on the prompter

    func testTurnCorrectionIsWhatTheLearnerReads() {
        let id = UUID()
        let steps = TeleprompterScript.build(session: session([
            turn("it go really well",
                 suggestion: TurnSuggestion(alternative: "it went really well",
                                            reason: "past tense"),
                 id: id)
        ]))
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].text, "it went really well")
        XCTAssertEqual(steps[0].said, "it go really well")
        XCTAssertTrue(steps[0].isCorrected)
        XCTAssertEqual(steps[0].note, "past tense")
        // Material: a passing read has to master the book's own correction.
        XCTAssertEqual(steps[0].attemptId, TalkCurriculum.correctionId(for: id))
    }

    func testAPhraseFixIsSplicedBackWhereItWasSaid() {
        let steps = TeleprompterScript.build(session: session(
            [turn("Honestly, it go really well and I felt prepared.")],
            fixes: [PhraseFeedback(userSaid: "it go really well",
                                   fluentAlternative: "it went really well",
                                   reason: "past tense")]))
        XCTAssertEqual(steps[0].text, "Honestly, it went really well and I felt prepared.")
        XCTAssertTrue(steps[0].isCorrected)
        // A summary correction's curriculum item is minted with a fresh id on
        // every build, so no shadow attempt could ever be matched to it.
        XCTAssertNil(steps[0].attemptId)
    }

    func testTurnCorrectionOutranksThePhraseFix() {
        let steps = TeleprompterScript.build(session: session(
            [turn("it go really well",
                  suggestion: TurnSuggestion(alternative: "it went really well — I was ready",
                                             reason: "past tense"))],
            fixes: [PhraseFeedback(userSaid: "it go really well",
                                   fluentAlternative: "it went really well",
                                   reason: "past tense")]))
        XCTAssertEqual(steps[0].text, "it went really well — I was ready")
        XCTAssertNotNil(steps[0].attemptId)
    }

    func testAnUncorrectedTurnIsReadBackAsSaid() {
        let steps = TeleprompterScript.build(session: session([
            turn("I felt prepared.")
        ]))
        XCTAssertEqual(steps[0].text, "I felt prepared.")
        XCTAssertFalse(steps[0].isCorrected)
        XCTAssertEqual(steps[0].said, "")
        XCTAssertNil(steps[0].attemptId)
    }

    // MARK: - What never reaches it

    func testAMisheardTurnIsDroppedButTheAnswerToItStays() {
        let steps = TeleprompterScript.build(session: session([
            turn("So — how did it go?", role: .fluentSelf),
            turn("show me the clock once",
                 suggestion: TurnSuggestion(alternative: "show me the clock",
                                            reason: "article"),
                 misheard: true),
            turn("Glad to hear it.", role: .fluentSelf),
        ]))
        XCTAssertEqual(steps.map { $0.isSpoken }, [false, false])
        XCTAssertEqual(steps.map { $0.text }, ["So — how did it go?", "Glad to hear it."])
    }

    func testAnEmptyTurnIsNotAStep() {
        let steps = TeleprompterScript.build(session: session([
            turn("   "), turn("Real line."),
        ]))
        XCTAssertEqual(steps.count, 1)
    }

    func testStepIdIsTheTurnIdSoStoredAudioStillResolves() {
        let id = UUID()
        let steps = TeleprompterScript.build(session: session([
            turn("So — how did it go?", role: .fluentSelf, id: id)
        ]))
        XCTAssertEqual(steps[0].id, id)
    }

    // MARK: - A Watch scene

    func testASceneReadsTheLearnersSideAndPlaysTheOther() {
        let mine = DialogueEngineTurn(speaker: "user", text: "Could I get it with oat milk?")
        let theirs = DialogueEngineTurn(speaker: "counterpart", text: "Sure, anything else?")
        let steps = TeleprompterScript.build(scene: [theirs, mine], shadowLines: [])
        XCTAssertEqual(steps.map { $0.isSpoken }, [false, true])
        // Written fluent — nothing is marked as a fix.
        XCTAssertFalse(steps[1].isCorrected)
        // Ids are the scene's own turn ids, so a replay lines up with them.
        XCTAssertEqual(steps.map { $0.id }, [theirs.id, mine.id])
    }

    func testASceneLineIsFiledUnderTheBooksShadowItem() {
        let mine = DialogueEngineTurn(speaker: "user", text: "Could I get it with oat milk?")
        let item = ScenarioCurriculum.Item(text: "could I get it with oat milk", note: "")
        let steps = TeleprompterScript.build(scene: [mine], shadowLines: [item])
        // Case and punctuation don't separate a line from its chapter item —
        // a passing read has to master the Shadow chapter.
        XCTAssertEqual(steps[0].attemptId, item.id)
    }

    func testTheCounterpartsLinesAreNeverFiled() {
        let theirs = DialogueEngineTurn(speaker: "counterpart", text: "Sure, anything else?")
        let item = ScenarioCurriculum.Item(text: "Sure, anything else?", note: "")
        let steps = TeleprompterScript.build(scene: [theirs], shadowLines: [item])
        XCTAssertNil(steps[0].attemptId)
    }

    // MARK: - The splice itself

    func testAFixThatChangesNothingIsNotACorrection() {
        let out = TeleprompterScript.applyPhraseFixes(
            to: "I went to the bank.",
            fixes: [PhraseFeedback(userSaid: "I went to the bank",
                                   fluentAlternative: "I Went to the Bank",
                                   reason: "")])
        XCTAssertFalse(out.changed)
    }

    func testAQuoteFromAnotherTurnIsIgnored() {
        let out = TeleprompterScript.applyPhraseFixes(
            to: "I felt prepared.",
            fixes: [PhraseFeedback(userSaid: "it go really well",
                                   fluentAlternative: "it went really well",
                                   reason: "")])
        XCTAssertEqual(out.text, "I felt prepared.")
        XCTAssertFalse(out.changed)
    }

    func testSeveralFixesInOneLineAllLand() {
        let out = TeleprompterScript.applyPhraseFixes(
            to: "it go well and I is happy",
            fixes: [PhraseFeedback(userSaid: "it go well", fluentAlternative: "it went well", reason: "a"),
                    PhraseFeedback(userSaid: "I is happy", fluentAlternative: "I was happy", reason: "b")])
        XCTAssertEqual(out.text, "it went well and I was happy")
        XCTAssertTrue(out.changed)
        // The first fix's reason is the one shown — one line under the
        // prompter, not a stack of them.
        XCTAssertEqual(out.note, "a")
    }
}

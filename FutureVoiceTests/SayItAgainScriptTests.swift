import XCTest
@testable import FutureVoice

/// `SayItAgainScript` decides what the learner reads on their own turn.
/// Three things it must never get wrong: a turn's own correction outranks
/// everything, a phrase fix goes back where it was SAID (not onto the end of
/// the line), and only a line that is review material carries the id a
/// passing read is filed under.
@MainActor
final class SayItAgainScriptTests: XCTestCase {

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
        let steps = SayItAgainScript.build(session: session([
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
        let steps = SayItAgainScript.build(session: session(
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
        let steps = SayItAgainScript.build(session: session(
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
        let steps = SayItAgainScript.build(session: session([
            turn("I felt prepared.")
        ]))
        XCTAssertEqual(steps[0].text, "I felt prepared.")
        XCTAssertFalse(steps[0].isCorrected)
        XCTAssertEqual(steps[0].said, "")
        XCTAssertNil(steps[0].attemptId)
    }

    // MARK: - The line has to be the whole turn (2026-09-27)

    /// The reported bug, as a test. `alternative` used to be specified as ONE
    /// sentence of at most 15 words, and this step swapped it in for the
    /// whole turn — so a 29-word utterance was read back as a 12-word clause
    /// and the re-run answered a question nobody had asked.
    func testALegacyFragmentDoesNotReplaceTheTurn() {
        let said = "Hey, um yeah, we can definitely do so, but I had a bad experience "
                 + "uh right uh before and checking if that is consistent uh issue or temporal issue."
        let steps = SayItAgainScript.build(session: session([
            // fixes == nil is what dates it: written before the whole-turn contract.
            turn(said, suggestion: TurnSuggestion(
                alternative: "I want to check if that is a consistent issue or a temporary issue.",
                reason: "관사와 단어 선택"))
        ]))
        XCTAssertEqual(steps[0].text, said, "the prompter must not lose the rest of the turn")
        XCTAssertEqual(steps[0].note,
                       "I want to check if that is a consistent issue or a temporary issue.",
                       "the better wording rides along instead of replacing the line")
        XCTAssertNil(steps[0].attemptId, "a fragment is not the book's correction")
    }

    // MARK: - A rewrite written afterwards (2026-10-06)

    /// A turn the call left with no whole-turn rewrite — the live correction
    /// failed, or it is a legacy fragment — reads the rewrite this screen
    /// asked for later, never the raw line with its fillers. It is practice
    /// text: nothing in the book is filed under it.
    func testARewriteWrittenLaterReplacesTheRawLine() {
        let id = UUID()
        let said = "Yeah, I think it it's really challenging. I it's yeah, how much do you trust it"
        let steps = SayItAgainScript.build(
            session: session([turn(said, id: id)]),
            rewrites: [id: .init(alternative: "Yeah, I think it's really challenging. How much do you trust it?",
                                 reason: "반복을 정리")])
        XCTAssertEqual(steps[0].text, "Yeah, I think it's really challenging. How much do you trust it?")
        XCTAssertEqual(steps[0].said, said)
        XCTAssertEqual(steps[0].note, "반복을 정리")
        XCTAssertNil(steps[0].attemptId)
    }

    func testTheCallsOwnRewriteOutranksOneWrittenLater() {
        let id = UUID()
        let steps = SayItAgainScript.build(
            session: session([turn("it go really well",
                                   suggestion: TurnSuggestion(alternative: "it went really well",
                                                              reason: "past tense", fixes: []),
                                   id: id)]),
            rewrites: [id: .init(alternative: "something else", reason: "")])
        XCTAssertEqual(steps[0].text, "it went really well")
        XCTAssertNotNil(steps[0].attemptId)
    }

    /// Asked and found clean: read as said.
    func testACleanAnswerLeavesTheLineAsSaid() {
        let id = UUID()
        let steps = SayItAgainScript.build(
            session: session([turn("I felt prepared for it.", id: id)]),
            rewrites: [id: .init(alternative: nil, reason: "")])
        XCTAssertEqual(steps[0].text, "I felt prepared for it.")
        XCTAssertFalse(steps[0].isCorrected)
    }

    func testAWholeTurnRewriteIsWhatTheLearnerReads() {
        let id = UUID()
        let said = "Hey, um yeah, we can definitely do so, but I had a bad experience "
                 + "uh right uh before and checking if that is consistent uh issue or temporal issue."
        let rewrite = "Hey, yeah, we can definitely do that, but I had a bad experience right "
                    + "before, and I'm checking if that's a consistent issue or a temporary issue."
        let steps = SayItAgainScript.build(session: session([
            turn(said, suggestion: TurnSuggestion(
                alternative: rewrite, reason: "더 자연스러운 흐름",
                fixes: [TurnFix(was: "temporal issue", now: "temporary issue",
                                why: "'temporal'은 시간에 관한 뜻이에요")]),
                 id: id)
        ]))
        XCTAssertEqual(steps[0].text, rewrite)
        XCTAssertEqual(steps[0].said, said)
        XCTAssertEqual(steps[0].attemptId, TalkCurriculum.correctionId(for: id))
    }

    /// A rewrite is legitimately much shorter when the turn was mostly
    /// hesitation — measured on the Korean probe, `어 그 그니까 그게 뭐냐면 좀
    /// 복잡해` comes back as `그게 뭐냐면 좀 복잡해`. Judging that by LENGTH calls
    /// it a fragment; the `fixes` marker gets it right.
    func testHesitationRemovalIsNotAFragment() {
        let steps = SayItAgainScript.build(session: session([
            turn("어 그 그니까 그게 뭐냐면 좀 복잡해.",
                 suggestion: TurnSuggestion(alternative: "그게 뭐냐면 좀 복잡해.",
                                            reason: "군더더기 없이", fixes: []))
        ]))
        XCTAssertEqual(steps[0].text, "그게 뭐냐면 좀 복잡해.")
        XCTAssertNotNil(steps[0].attemptId)
    }

    // MARK: - What never reaches it

    func testAMisheardTurnIsDroppedButTheAnswerToItStays() {
        let steps = SayItAgainScript.build(session: session([
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
        let steps = SayItAgainScript.build(session: session([
            turn("   "), turn("Real line."),
        ]))
        XCTAssertEqual(steps.count, 1)
    }

    func testStepIdIsTheTurnIdSoStoredAudioStillResolves() {
        let id = UUID()
        let steps = SayItAgainScript.build(session: session([
            turn("So — how did it go?", role: .fluentSelf, id: id)
        ]))
        XCTAssertEqual(steps[0].id, id)
    }

    // MARK: - A Watch scene

    func testASceneReadsTheLearnersSideAndPlaysTheOther() {
        let mine = DialogueEngineTurn(speaker: "user", text: "Could I get it with oat milk?")
        let theirs = DialogueEngineTurn(speaker: "counterpart", text: "Sure, anything else?")
        let steps = SayItAgainScript.build(scene: [theirs, mine], shadowLines: [])
        XCTAssertEqual(steps.map { $0.isSpoken }, [false, true])
        // Written fluent — nothing is marked as a fix.
        XCTAssertFalse(steps[1].isCorrected)
        // Ids are the scene's own turn ids, so a replay lines up with them.
        XCTAssertEqual(steps.map { $0.id }, [theirs.id, mine.id])
    }

    func testASceneLineIsFiledUnderTheBooksShadowItem() {
        let mine = DialogueEngineTurn(speaker: "user", text: "Could I get it with oat milk?")
        let item = ScenarioCurriculum.Item(text: "could I get it with oat milk", note: "")
        let steps = SayItAgainScript.build(scene: [mine], shadowLines: [item])
        // Case and punctuation don't separate a line from its chapter item —
        // a passing read has to master the Shadow chapter.
        XCTAssertEqual(steps[0].attemptId, item.id)
    }

    func testTheCounterpartsLinesAreNeverFiled() {
        let theirs = DialogueEngineTurn(speaker: "counterpart", text: "Sure, anything else?")
        let item = ScenarioCurriculum.Item(text: "Sure, anything else?", note: "")
        let steps = SayItAgainScript.build(scene: [theirs], shadowLines: [item])
        XCTAssertNil(steps[0].attemptId)
    }

    // MARK: - The splice itself

    func testAFixThatChangesNothingIsNotACorrection() {
        let out = SayItAgainScript.applyPhraseFixes(
            to: "I went to the bank.",
            fixes: [PhraseFeedback(userSaid: "I went to the bank",
                                   fluentAlternative: "I Went to the Bank",
                                   reason: "")])
        XCTAssertFalse(out.changed)
    }

    func testAQuoteFromAnotherTurnIsIgnored() {
        let out = SayItAgainScript.applyPhraseFixes(
            to: "I felt prepared.",
            fixes: [PhraseFeedback(userSaid: "it go really well",
                                   fluentAlternative: "it went really well",
                                   reason: "")])
        XCTAssertEqual(out.text, "I felt prepared.")
        XCTAssertFalse(out.changed)
    }

    func testSeveralFixesInOneLineAllLand() {
        let out = SayItAgainScript.applyPhraseFixes(
            to: "it go well and I is happy",
            fixes: [PhraseFeedback(userSaid: "it go well", fluentAlternative: "it went well", reason: "a"),
                    PhraseFeedback(userSaid: "I is happy", fluentAlternative: "I was happy", reason: "b")])
        XCTAssertEqual(out.text, "it went well and I was happy")
        XCTAssertTrue(out.changed)
        // The first fix's reason is the one shown — one line under the
        // prompter, not a stack of them.
        XCTAssertEqual(out.note, "a")
    }

    // MARK: - A cut-in is not a turn (2026-09-29)

    private func heard(_ text: String, id: UUID = UUID()) -> Turn {
        var t = turn(text, role: .fluentSelf, id: id)
        t.durationMs = 2400
        return t
    }

    private func cutIn(_ text: String) -> Turn {
        var t = turn(text, role: .fluentSelf)
        t.talkedOver = true
        t.durationMs = 800     // some audio arrived; the flag is what decides
        return t
    }

    func testTheTwoHalvesOfACutInSentenceAreOneLine() {
        let steps = SayItAgainScript.build(session: session([
            heard("How was the weekend?"),
            turn("I went to the"),
            cutIn("Oh nice, where did you go?"),
            turn("mountains with my sister."),
            heard("That sounds lovely."),
        ]), hasAudio: { _ in false })
        XCTAssertEqual(steps.map { $0.isSpoken }, [false, true, false])
        XCTAssertEqual(steps[1].text, "I went to the mountains with my sister.")
        XCTAssertEqual(steps[2].text, "That sounds lovely.")
    }

    func testALineWithNoAudioAtAllCountsAsUnheard() {
        // Talks saved before the flag: nothing played, so nothing recorded.
        let steps = SayItAgainScript.build(session: session([
            turn("I went to the"),
            turn("Where?", role: .fluentSelf),
            turn("mountains."),
        ]), hasAudio: { _ in false })
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].text, "I went to the mountains.")
    }

    func testAHeardAnswerStillSeparatesTwoLines() {
        let id = UUID()
        var answer = turn("Where?", role: .fluentSelf, id: id)
        answer.durationMs = 0   // duration lost, but its recording is on disk
        let steps = SayItAgainScript.build(session: session([
            turn("I went away."), answer, turn("To the mountains."),
        ]), hasAudio: { $0 == id })
        XCTAssertEqual(steps.count, 3)
    }

    func testAChainOfCutInsIsOneLine() {
        let steps = SayItAgainScript.build(session: session([
            turn("So I"), cutIn("Mm?"), turn("was thinking"), cutIn("Yes?"), turn("about moving."),
        ]), hasAudio: { _ in false })
        XCTAssertEqual(steps.map { $0.text }, ["So I was thinking about moving."])
    }

    func testMergedHalvesKeepTheirCorrectionsAndTheDiffCoversBoth() {
        let a = UUID()
        let steps = SayItAgainScript.build(session: session([
            turn("yesterday I go to",
                 suggestion: TurnSuggestion(alternative: "yesterday I went to",
                                            reason: "past tense"),
                 id: a),
            cutIn("Where to?"),
            turn("the museum."),
        ]), hasAudio: { _ in false })
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].text, "yesterday I went to the museum.")
        XCTAssertEqual(steps[0].said, "yesterday I go to the museum.")
        XCTAssertEqual(steps[0].note, "past tense")
        // Exactly one half was material, and the merged line contains it whole.
        XCTAssertEqual(steps[0].attemptId, TalkCurriculum.correctionId(for: a))
        XCTAssertEqual(steps[0].id, a)
    }

    func testAnUnspacedLanguageJoinsWithoutASpace() {
        var s = session([turn("昨日は"), cutIn("うん"), turn("山に行った。")])
        s = Session(id: s.id, userId: s.userId, targetLanguage: "ja", mode: s.mode,
                    topic: s.topic, startedAt: s.startedAt, endedAt: s.endedAt,
                    turns: s.turns, summary: nil)
        let steps = SayItAgainScript.build(session: s, hasAudio: { _ in false })
        XCTAssertEqual(steps.map { $0.text }, ["昨日は山に行った。"])
    }

    func testACutInAtTheEndOfTheCallIsLeftAlone() {
        let steps = SayItAgainScript.build(session: session([
            turn("I think"), cutIn("Go on?"),
        ]), hasAudio: { _ in false })
        XCTAssertEqual(steps.count, 2)
    }
}

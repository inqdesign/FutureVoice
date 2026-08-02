import XCTest
@testable import FutureVoice

/// The whole feature rests on never claiming a learner said something they
/// didn't — one bogus "you used this!" and every number on the page loses
/// credibility. So the false-positive cases below matter more than the
/// positive ones.
final class CarryoverDetectorTests: XCTestCase {

    private let sessionId = UUID()
    private let sessionStart = Date()

    private func userTurn(_ text: String, suggestion: TurnSuggestion? = nil,
                          excluded: Bool = false) -> Turn {
        var t = Turn(id: UUID(), role: .user, audioURL: nil, transcript: text,
                     durationMs: 1000, timestamp: sessionStart, suggestion: suggestion)
        t.excludedFromScoring = excluded
        return t
    }

    private func fluentTurn(_ text: String) -> Turn {
        Turn(id: UUID(), role: .fluentSelf, audioURL: nil, transcript: text,
             durationMs: 1000, timestamp: sessionStart, suggestion: nil)
    }

    private func card(_ target: String, createdAt: Date? = nil) -> DrillCard {
        DrillCard(sourcePhrase: "old version", targetPhrase: target,
                  reason: "more natural",
                  createdAt: createdAt ?? sessionStart.addingTimeInterval(-86_400),
                  nextReviewAt: sessionStart, box: 1, sourceSessionId: UUID())
    }

    private func detect(_ turns: [Turn], _ cards: [DrillCard],
                        bookmarked: [String] = [],
                        words: [String] = [],
                        book: [CarryoverDetector.CurriculumItem] = []) -> [Carryover] {
        CarryoverDetector.detect(in: turns, cards: cards,
                                 curriculumItems: book,
                                 studyingExpressions: bookmarked,
                                 studyingWords: words,
                                 sessionId: sessionId, sessionStartedAt: sessionStart)
    }

    private func bookItem(_ text: String, isWord: Bool) -> CarryoverDetector.CurriculumItem {
        CarryoverDetector.CurriculumItem(id: UUID(), text: text, isWord: isWord)
    }

    // MARK: - Cards produced live

    func testCardPhraseSaidVerbatimIsCredited() {
        let hits = detect([userTurn("I'd rather stay in tonight.")],
                          [card("I'd rather stay in tonight.")])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .drillCard)
        XCTAssertEqual(hits.first?.quote.contains("rather stay in tonight"), true)
    }

    func testPaddingAroundThePhraseStillCounts() {
        let hits = detect([userTurn("Honestly I'd rather just stay in tonight, if that's okay.")],
                          [card("I'd rather stay in tonight.")])
        XCTAssertEqual(hits.count, 1)
    }

    func testCasingAndPunctuationDriftStillCounts() {
        let hits = detect([userTurn("id rather stay in tonight")],
                          [card("I'd rather stay in tonight.")])
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - False-positive guards

    func testScatteredWordsAcrossALongRambleAreNotAPhrase() {
        let ramble = """
        I would rather not talk about work. Anyway we had to stay at my parents' \
        place because of the trains, and I only got home very late, so I didn't \
        do anything else that night. It was a long day honestly, and tonight I \
        just want to sleep.
        """
        let hits = detect([userTurn(ramble)], [card("I'd rather stay in tonight.")])
        XCTAssertTrue(hits.isEmpty, "words scattered across unrelated sentences must not match")
    }

    func testReorderedWordsDoNotMatch() {
        let hits = detect([userTurn("Tonight I will stay, rather at home actually no.")],
                          [card("I'd rather stay in tonight.")])
        XCTAssertTrue(hits.isEmpty, "order is what separates a phrase from a bag of words")
    }

    func testTooGenericAnItemIsNeverCredited() {
        // "how are you" is three words but only one of them carries meaning —
        // crediting it would cheapen every other row in the section.
        let hits = detect([userTurn("Hey, how are you doing today?")], [card("How are you?")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testIdiomsMadeOfFunctionWordsSurviveTheGenericnessGate() {
        // The gate counts content words but the MATCH counts every word —
        // otherwise idioms, which are mostly function words, would all be
        // thrown out as generic.
        let hits = detect([userTurn("Sorry, it totally slipped my mind.")],
                          [card("It slipped my mind.")])
        XCTAssertEqual(hits.count, 1)
    }

    func testFunctionWordsAreLoadBearingInTheMatch() {
        // Same content words, different phrase — must not collapse together.
        let hits = detect([userTurn("How do you say that in German?")], [card("How are you?")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testOnlyTheLearnersOwnTurnsAreSearched() {
        let hits = detect([fluentTurn("I'd rather stay in tonight.")],
                          [card("I'd rather stay in tonight.")])
        XCTAssertTrue(hits.isEmpty, "the fluent self saying it proves nothing")
    }

    func testMisheardTurnsAreExcluded() {
        let hits = detect([userTurn("I'd rather stay in tonight.", excluded: true)],
                          [card("I'd rather stay in tonight.")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testCardBornInThisSessionCannotBeCarriedIntoIt() {
        var c = card("I'd rather stay in tonight.",
                     createdAt: sessionStart.addingTimeInterval(600))
        c.sourceSessionId = sessionId
        XCTAssertTrue(detect([userTurn("I'd rather stay in tonight.")], [c]).isEmpty)
    }

    // MARK: - Notebook expressions produced live

    func testBookmarkedExpressionSaidIsCredited() {
        // Notebook keys are stored lowercased — matching must not care.
        let hits = detect([userTurn("It totally slipped my mind, sorry!")], [],
                          bookmarked: ["it slipped my mind"])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .studyingExpression)
    }

    func testBookmarkedExpressionNotSaidIsNotCredited() {
        let hits = detect([userTurn("Sorry, I completely forgot about the meeting.")], [],
                          bookmarked: ["it slipped my mind"])
        XCTAssertTrue(hits.isEmpty)
    }

    func testACardOutranksTheSameNotebookEntry() {
        let phrase = "It totally slipped my mind."
        let hits = detect([userTurn(phrase)], [card(phrase)], bookmarked: [phrase.lowercased()])
        XCTAssertEqual(hits.count, 1, "one item, credited once")
        XCTAssertEqual(hits.first?.source, .drillCard, "the heavier source wins")
    }

    // MARK: - Watch book material produced live

    func testBookExpressionSaidInAnUnrelatedTalkIsCredited() {
        // The point of this source: the book's own mastery pass only reads
        // talks whose topic matches the book title, so it would miss this.
        let item = bookItem("Could you box that up for me?", isWord: false)
        let hits = detect([userTurn("Great, could you box that up for me please?")], [], book: [item])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .curriculumItem)
        XCTAssertEqual(hits.first?.sourceId, item.id, "the item id is what masters the book entry")
    }

    func testBookWordUsesTheLemmaMatcher() {
        let hits = detect([userTurn("I commuted in every morning that week.")], [],
                          book: [bookItem("commute", isWord: true)])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .curriculumItem)
    }

    func testBookItemNotSaidIsNotCredited() {
        let hits = detect([userTurn("Thanks, that's everything for today.")], [],
                          book: [bookItem("Could you box that up for me?", isWord: false)])
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Notebook words produced live

    func testNotebookWordSaidInAnInflectedFormIsCredited() {
        // The notebook holds the headword; speech holds whatever form fits.
        let hits = detect([userTurn("I commuted for two hours every day back then.")],
                          [], words: ["commute"])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .studyingWord)
        XCTAssertEqual(hits.first?.item, "commute")
    }

    func testNotebookWordNotSaidIsNotCredited() {
        let hits = detect([userTurn("I drove to the office every day back then.")],
                          [], words: ["commute"])
        XCTAssertTrue(hits.isEmpty)
    }

    func testWordAlreadyInsideACreditedPhraseIsNotCountedTwice() {
        let hits = detect([userTurn("Sorry, it totally slipped my mind.")],
                          [card("It slipped my mind.")],
                          words: ["mind"])
        XCTAssertEqual(hits.count, 1, "the phrase already tells this story")
        XCTAssertEqual(hits.first?.source, .drillCard)
    }

    func testWordCarryoversAreCapped() {
        let sentence = "The deadline was tough but the commute and the interview went well, "
            + "and I stayed relaxed and prepared throughout."
        let notebook = ["deadline", "commute", "interview", "relaxed", "prepared", "tough", "well"]
        let hits = detect([userTurn(sentence)], [], words: notebook)
        XCTAssertLessThanOrEqual(hits.count, CarryoverDetector.maxWordCarryovers)
        XCTAssertTrue(hits.allSatisfy { $0.source == .studyingWord })
    }

    // MARK: - Suggestions adopted mid-call

    func testSuggestionAppliedInALaterTurnIsCredited() {
        let suggestion = TurnSuggestion(alternative: "I'm really looking forward to it.",
                                        reason: "more natural")
        let turns = [
            userTurn("I have much expectation.", suggestion: suggestion),
            fluentTurn("That sounds great — when is it?"),
            userTurn("Next Friday. I'm really looking forward to it."),
        ]
        let hits = detect(turns, [])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source, .suggestion)
    }

    func testSuggestionIsNotCreditedAgainstTheTurnThatEarnedIt() {
        // The turn carrying the suggestion happens to contain its wording —
        // that's the LLM rephrasing them, not the learner applying anything.
        let suggestion = TurnSuggestion(alternative: "I'm really looking forward to it.",
                                        reason: "more natural")
        let hits = detect([userTurn("I'm really looking forward to it.", suggestion: suggestion)], [])
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Lifetime aggregate (the Progress number)

    private func session(_ carryovers: [Carryover], endedAt: Date) -> Session {
        var summary = SessionSummary(phrasesUsed: [], newPatternsDetected: [],
                                     suggestedDrills: [], overallNote: "", scorecard: nil)
        summary.carryovers = carryovers
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: nil, startedAt: endedAt, endedAt: endedAt, turns: [],
                       summary: summary)
    }

    private func carryover(_ item: String, at date: Date,
                           source: Carryover.Source = .drillCard) -> Carryover {
        Carryover(sessionId: UUID(), source: source, item: item, quote: item,
                  turnId: UUID(), sourceId: nil, detectedAt: date)
    }

    func testTheSameItemSaidInManyTalksCountsOnce() {
        let old = sessionStart.addingTimeInterval(-30 * 86_400)
        let sessions = [
            session([carryover("I'd rather stay in tonight.", at: old)], endedAt: old),
            session([carryover("I'd rather stay in tonight.", at: sessionStart)],
                    endedAt: sessionStart),
        ]
        let summary = PracticeStats.carryoverSummary(sessions: sessions, now: sessionStart)
        XCTAssertEqual(summary.total, 1, "one thing learned, not two")
    }

    func testWeeklyCountUsesFirstUseNotRepetition() {
        // Said long ago, said again today — nothing NEW crossed over this week.
        let old = sessionStart.addingTimeInterval(-30 * 86_400)
        let sessions = [
            session([carryover("I'd rather stay in tonight.", at: old)], endedAt: old),
            session([carryover("I'd rather stay in tonight.", at: sessionStart)],
                    endedAt: sessionStart),
        ]
        let summary = PracticeStats.carryoverSummary(sessions: sessions, now: sessionStart)
        XCTAssertEqual(summary.thisWeek, 0)
    }

    func testSourceBreakdownCounts() {
        let sessions = [session([
            carryover("one phrase here", at: sessionStart, source: .drillCard),
            carryover("another phrase here", at: sessionStart, source: .curriculumItem),
            carryover("a third phrase here", at: sessionStart, source: .curriculumItem),
        ], endedAt: sessionStart)]
        let summary = PracticeStats.carryoverSummary(sessions: sessions, now: sessionStart)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.bySource[.curriculumItem], 2)
        XCTAssertEqual(summary.bySource[.drillCard], 1)
    }

    func testOneItemIsCreditedOnlyOnce() {
        let phrase = "I'd rather stay in tonight."
        let suggestion = TurnSuggestion(alternative: phrase, reason: "more natural")
        let turns = [
            userTurn("I want stay home.", suggestion: suggestion),
            userTurn(phrase),
        ]
        XCTAssertEqual(detect(turns, [card(phrase)]).count, 1)
    }
}

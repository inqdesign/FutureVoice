import XCTest
@testable import FutureVoice

/// The live chips make a promise the wrap-up has to keep: a chip that ticks
/// mid-call is claiming the learner said the thing, and the end-of-session
/// carryover pass will be asked the same question about the same transcript.
/// These tests pin the two halves of that — a tick is only ever the detector's
/// answer, and a chip is only ever offered if the detector could tick it.
@MainActor
final class TalkGoalChipsTests: XCTestCase {

    /// Lemma matching routes on the ACTIVE target language, which lives in
    /// UserDefaults — same trap as `CarryoverDetectorTests`.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("en", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private func userTurn(_ text: String, excluded: Bool = false) -> Turn {
        var t = Turn(id: UUID(), role: .user, audioURL: nil, transcript: text,
                     durationMs: 1000, timestamp: Date(), suggestion: nil)
        t.excludedFromScoring = excluded
        return t
    }

    private func word(_ w: String) -> TalkGoalItem {
        TalkGoalItem(key: CarryoverDetector.normalized(w), text: w, isWord: true)
    }

    private func phrase(_ p: String) -> TalkGoalItem {
        TalkGoalItem(key: CarryoverDetector.normalized(p), text: p, isWord: false)
    }

    // MARK: - Ticking

    func testWordTicksInAnyInflection() {
        let hits = TalkGoalPicker.hits(in: userTurn("I commuted for almost an hour."),
                                       among: [word("commute")])
        XCTAssertEqual(hits, ["commute"])
    }

    func testUnsaidWordDoesNotTick() {
        let hits = TalkGoalPicker.hits(in: userTurn("The interview went well."),
                                       among: [word("commute"), word("hectic")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testPhraseTicksWithPadding() {
        let hits = TalkGoalPicker.hits(in: userTurn("Sorry, it completely slipped my mind."),
                                       among: [phrase("it slipped my mind")])
        XCTAssertEqual(hits, ["it slipped my mind"])
    }

    /// The same words, scattered and reordered, are a coincidence — the phrase
    /// rules exist precisely to refuse this, and the chips inherit them.
    func testScatteredWordsDoNotTickAPhrase() {
        let turn = userTurn("My mind was elsewhere and the whole thing just slipped by.")
        XCTAssertTrue(TalkGoalPicker.hits(in: turn, among: [phrase("it slipped my mind")]).isEmpty)
    }

    /// Only the learner's own speech counts. The fluent self uses the target
    /// vocabulary constantly — crediting that would tick every chip in the row
    /// within two turns.
    func testFluentSelfTurnNeverTicks() {
        let turn = Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                        transcript: "I commuted for almost an hour.",
                        durationMs: 1000, timestamp: Date(), suggestion: nil)
        XCTAssertTrue(TalkGoalPicker.hits(in: turn, among: [word("commute")]).isEmpty)
    }

    func testMisheardTurnNeverTicks() {
        let turn = userTurn("I commuted for almost an hour.", excluded: true)
        XCTAssertTrue(TalkGoalPicker.hits(in: turn, among: [word("commute")]).isEmpty)
    }

    // MARK: - What may be offered

    /// A chip whose phrase can never clear the detector's token bars is a
    /// checkbox that cannot tick — the picker has to filter those out.
    func testTooShortOrTooThinPhraseIsNotCreditable() {
        XCTAssertFalse(CarryoverDetector.isCreditable("of course"))     // under minTokens
        XCTAssertFalse(CarryoverDetector.isCreditable("it is a"))       // no content words
        XCTAssertTrue(CarryoverDetector.isCreditable("it slipped my mind"))
    }

    // MARK: - A talk on a scenario book

    private func scenario(words: [(String, Date?)], expressions: [(String, Date?)] = []) -> Scenario {
        var s = Scenario(environment: "Pharmacy", role: "Pharmacist", notes: "")
        var c = ScenarioCurriculum()
        c.words = words.map { w, m in
            var item = ScenarioCurriculum.Item(text: w, note: "when you ask for it", example: "Do you have \(w)?")
            item.masteredAt = m
            return item
        }
        c.expressions = expressions.map { e, m in
            var item = ScenarioCurriculum.Item(text: e, note: "", example: nil)
            item.masteredAt = m
            return item
        }
        s.curriculum = c
        return s
    }

    private func talk(offered: [String]) -> Session {
        var summary = SessionSummary(phrasesUsed: [], newPatternsDetected: [],
                                     suggestedDrills: [], overallNote: "", scorecard: nil)
        summary.expressionsOffered = offered
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: nil, startedAt: Date(), endedAt: Date(), turns: [], summary: summary)
    }

    /// The book's still-unmastered words lead the row, its example rides on
    /// the chip, and a word already ticked off in the book is not asked for.
    func testScenarioTalkLeadsWithTheBooksUnmasteredWords() {
        let s = scenario(words: [("ointment", nil), ("prescription", Date()), ("dosage", nil)])
        let row = TalkGoalPicker.pick(forScenario: s, previousTalks: [], proficiency: .b1)
        let keys = row.map(\.key)
        XCTAssertEqual(Array(keys.prefix(2)), ["ointment", "dosage"])
        XCTAssertFalse(keys.contains("prescription"))
        XCTAssertEqual(row.first?.example, "Do you have ointment?")
        XCTAssertEqual(row.first?.note, "when you ask for it")
    }

    /// What the fluent self offered in an earlier run of the scene is related
    /// by construction, and comes before anything the global notebook deals.
    func testScenarioTalkOffersWhatPreviousRunsTaught() {
        let s = scenario(words: [("ointment", nil)])
        let row = TalkGoalPicker.pick(forScenario: s,
                                      previousTalks: [talk(offered: ["it should clear up in a week"])],
                                      proficiency: .b1)
        XCTAssertTrue(row.contains { $0.key == CarryoverDetector.normalized("it should clear up in a week") && !$0.isWord })
    }

    /// Each run leads with a different slice of what's left, so practising a
    /// scene four times doesn't put the same five words up front four times.
    func testScenarioRowRotatesWithTheNumberOfRuns() {
        let s = scenario(words: [("ointment", nil), ("dosage", nil), ("refill", nil)])
        let first = TalkGoalPicker.pick(forScenario: s, previousTalks: [], proficiency: .b1)
        let second = TalkGoalPicker.pick(forScenario: s, previousTalks: [talk(offered: [])], proficiency: .b1)
        XCTAssertEqual(first.first?.key, "ointment")
        XCTAssertEqual(second.first?.key, "dosage")
        XCTAssertEqual(Set(first.map(\.key)).intersection(["ointment", "dosage", "refill"]).count, 3)
    }
}

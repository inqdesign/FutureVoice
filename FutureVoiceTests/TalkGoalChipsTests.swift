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
}

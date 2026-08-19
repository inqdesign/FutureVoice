import XCTest
@testable import FutureVoice

/// The daily deck's "10 min · Tomorrow · 3 days" promise, at the data layer:
/// snoozes persist, gate due-ness, and clear on "Got it".
final class StudyScheduleStoreTests: XCTestCase {

    private var store: StudyScheduleStore!
    private let filename = "test-study-schedule.json"

    override func setUp() {
        super.setUp()
        store = StudyScheduleStore(filename: filename)
    }

    override func tearDown() {
        let url = LanguageScope.activeDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testUnscheduledIsDueImmediately() {
        XCTAssertNil(store.nextReview(.word, "appreciate"))
        XCTAssertTrue(store.isDue(.word, "appreciate"))
    }

    func testSnoozeGatesUntilDue() {
        let now = Date()
        let back = now.addingTimeInterval(10 * 60)
        store.snooze(.word, "Appreciate", until: back)

        // Key is case/whitespace-insensitive — the deck deals display casing.
        XCTAssertEqual(store.nextReview(.word, "appreciate"), back)
        XCTAssertFalse(store.isDue(.word, " appreciate ", now: now))
        // …and due again once the promise comes around.
        XCTAssertTrue(store.isDue(.word, "appreciate", now: back.addingTimeInterval(1)))
    }

    func testKindsDoNotCollide() {
        store.snooze(.word, "catch up on", until: Date().addingTimeInterval(3600))
        XCTAssertTrue(store.isDue(.expression, "catch up on"))
    }

    func testClearRestoresDueness() {
        store.snooze(.expression, "a bit of a stretch", until: Date().addingTimeInterval(3600))
        store.clear(.expression, "a bit of a stretch")
        XCTAssertTrue(store.isDue(.expression, "a bit of a stretch"))
        XCTAssertNil(store.nextReview(.expression, "a bit of a stretch"))
    }

    func testPersistsAcrossReloads() {
        let back = Date().addingTimeInterval(24 * 3600)
        store.snooze(.word, "nuanced", until: back)
        let reloaded = StudyScheduleStore(filename: filename)
        XCTAssertEqual(reloaded.nextReview(.word, "nuanced")?.timeIntervalSince1970 ?? 0,
                       back.timeIntervalSince1970, accuracy: 1)
    }

    func testAllNextReviewsFeedsTheReminder() {
        let a = Date().addingTimeInterval(600)
        let b = Date().addingTimeInterval(7200)
        store.snooze(.word, "one", until: a)
        store.snooze(.expression, "two", until: b)
        XCTAssertEqual(Set(store.allNextReviews().map { Int($0.timeIntervalSince1970) }),
                       Set([a, b].map { Int($0.timeIntervalSince1970) }))
    }
}

/// The two reminders have different jobs, and the split is what makes a short
/// snooze real:
///   • `ItemReminder` (per explicit drop) fires at the promised time — it asks
///     for its own fire date with `hasDueNow: false`, so the backlog can't
///     defer it.
///   • `DrillReminder` (the aggregate) still defers to tomorrow morning when
///     things are already due, so it doesn't double-fire alongside it.
@MainActor
final class StudyReminderPolicyTests: XCTestCase {

    func testPerItemCallbackFiresAtThePromisedTime() {
        let now = Date()
        let soon = now.addingTimeInterval(60)
        let fire = DrillReminder.fireDate(now: now, nextDue: soon, hasDueNow: false)
        XCTAssertEqual(fire, soon,
                       "a 1-minute promise must fire in 1 minute, not park until 9am")
    }

    func testAggregateStillDefersWhenABacklogIsAlreadyDue() {
        let now = Date()
        let fire = DrillReminder.fireDate(now: now,
                                          nextDue: now.addingTimeInterval(60),
                                          hasDueNow: true)
        XCTAssertNotEqual(fire, now.addingTimeInterval(60),
                          "the aggregate must not fire on top of the per-item callback")
        XCTAssertEqual(Calendar.current.component(.hour, from: fire!), 9)
    }
}

/// What a review reminder OPENS: only the items whose snooze actually ran
/// out, oldest promise first — never a fresh hand of unrelated material.
@MainActor
final class DueReviewDeckTests: XCTestCase {

    private var store: StudyScheduleStore!

    override func setUp() {
        super.setUp()
        store = StudyScheduleStore.shared
        for item in store.dueItems(now: .distantFuture) {
            store.clear(item.kind, item.text)
        }
    }

    override func tearDown() {
        for item in store.dueItems(now: .distantFuture) {
            store.clear(item.kind, item.text)
        }
        super.tearDown()
    }

    /// Unique per run so the shared VocabStore (which the app also writes)
    /// can't have pre-marked these as known — a known item is retired on
    /// purpose, and that's covered by its own test below.
    private func fresh(_ label: String) -> String {
        "zz-\(label)-\(UUID().uuidString.prefix(6))"
    }

    func testOnlyOverdueItemsAreDealt() {
        let now = Date()
        let old = fresh("old"), recent = fresh("recent"), waiting = fresh("waiting")
        store.snooze(.word, old, until: now.addingTimeInterval(-600))          // 10 min ago
        store.snooze(.expression, recent, until: now.addingTimeInterval(-60))
        store.snooze(.word, waiting, until: now.addingTimeInterval(3 * 86_400)) // still waiting

        let deck = DueReviewView.dueDeck(now: now)
        XCTAssertEqual(deck.map(\.text), [old, recent],
                       "oldest promise first; a 3-day snooze must stay out")
        XCTAssertEqual(deck.first?.kind, .word)
        XCTAssertEqual(deck.last?.kind, .expression)
    }

    func testNothingDueDealsNothing() {
        store.snooze(.word, fresh("later"), until: Date().addingTimeInterval(3600))
        XCTAssertTrue(DueReviewView.dueDeck().isEmpty)
    }

    /// The reminder and the deck must never disagree: an item marked known
    /// elsewhere is dropped from BOTH, schedule entry and all. Otherwise the
    /// notification promises items the deck won't deal.
    func testKnownItemsAreRetiredFromTheQueue() {
        let word = fresh("known")
        store.snooze(.word, word, until: Date().addingTimeInterval(-60))
        XCTAssertEqual(ReviewQueue.dueItems().map(\.text), [word])

        VocabStore.shared.markKnown(VocabStore.lookupKey(for: word))
        XCTAssertTrue(ReviewQueue.dueItems().isEmpty, "known item still dealt")
        XCTAssertNil(store.nextReview(.word, word), "stale schedule entry left behind")
        XCTAssertTrue(ReviewQueue.returnDates().isEmpty,
                      "the reminder would still count a retired item")

        VocabStore.shared.unmark(VocabStore.lookupKey(for: word))
    }
}

/// The notification's payload has to survive the round trip through
/// `userInfo` — a tap that can't name its item can't open it.
@MainActor
final class ItemReminderTargetTests: XCTestCase {

    func testTargetRoundTripsThroughUserInfoValues() {
        let cases: [ItemReminder.Target] = [
            .word("appreciate"),
            .expression("catch up on"),
            .sentence(UUID()),
        ]
        for target in cases {
            let back = ItemReminder.Target(kind: target.kind, value: target.value)
            XCTAssertEqual(back, target, "\(target.kind) lost identity in the payload")
        }
    }

    func testUnknownPayloadIsRejectedRatherThanGuessed() {
        XCTAssertNil(ItemReminder.Target(kind: "sentence", value: "not-a-uuid"))
        XCTAssertNil(ItemReminder.Target(kind: "nonsense", value: "x"))
    }

    /// One pending request per item: re-snoozing the same word replaces its
    /// callback instead of stacking a second one.
    func testRequestIdIsStablePerItem() {
        XCTAssertEqual(ItemReminder.Target.word("Appreciate").requestId,
                       ItemReminder.Target.word("appreciate").requestId)
        XCTAssertNotEqual(ItemReminder.Target.word("appreciate").requestId,
                          ItemReminder.Target.expression("appreciate").requestId)
    }
}

/// A book's material has to reach its category's library, not just sit on the
/// book. Watch books were the disconnected half: their expressions, words and
/// scene lines lived on the `Scenario` and no library, count or browser knew
/// about them.
@MainActor
final class BookMaterialReachesLibraryTests: XCTestCase {

    private func scenario(words: [String] = [],
                          expressions: [String] = [],
                          lines: [String] = []) -> Scenario {
        var s = Scenario(environment: "At the pharmacy", role: "pharmacist",
                         notes: "picking up a prescription")
        var c = ScenarioCurriculum()
        c.words = words.map { .init(text: $0, note: "") }
        c.expressions = expressions.map { .init(text: $0, note: "") }
        c.shadowLines = lines.map { .init(text: $0, note: "") }
        s.curriculum = c
        return s
    }

    /// Unique fixtures: `VocabStore` is a singleton reading the real files, so
    /// the catalog legitimately also contains whatever this simulator has
    /// collected. The claim under test is about THESE phrases.
    private let scenePhrase = "zz-pick-up-a-prescription"
    private let otherScenePhrase = "zz-over-the-counter"

    func testSceneExpressionsAppearInTheExpressionCatalog() {
        let s = scenario(expressions: [scenePhrase, otherScenePhrase])
        let all = ExpressionCatalog.all(scenarios: [s])

        for phrase in [scenePhrase, otherScenePhrase] {
            guard let item = all.first(where: { $0.key == phrase }) else {
                return XCTFail("\(phrase) never reached the catalog")
            }
            XCTAssertTrue(item.isFromScene, "a scene expression must say where it came from")
        }
    }

    /// An archived book stops asking.
    func testArchivedScenariosDropOutOfTheCatalog() {
        var s = scenario(expressions: [scenePhrase])
        s.archivedAt = Date()          // `isArchived` is derived from this
        XCTAssertNil(ExpressionCatalog.all(scenarios: [s]).first { $0.key == scenePhrase },
                     "an archived book must stop asking")
    }
}

/// A book has to fill in as you learn. Talk books were built from
/// `pickupWords`, which excludes anything you already know — so learning a
/// word removed it from the chapter instead of checking it off, and the
/// progress bar sat at 0 no matter what.
@MainActor
final class TalkBookProgressTests: XCTestCase {

    /// Picked from the ACTIVE language's core list at runtime — the store is
    /// language-scoped, so a hardcoded English word isn't in the list when the
    /// simulator is set to another target language.
    private lazy var taughtWord: String = {
        CoreVocabulary.entries
            .first { VocabStore.shared.state(of: $0.word) == nil && $0.word.count > 3 }?
            .word ?? "commute"
    }()

    private func session(saying line: String) -> Session {
        Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                topic: "Free talk", startedAt: Date(), endedAt: Date(),
                turns: [
                    Turn(id: UUID(), role: .fluentSelf, audioURL: nil, transcript: line,
                         durationMs: 0, timestamp: Date(), suggestion: nil)
                ])
    }

    override func tearDown() {
        VocabStore.shared.unmark(taughtWord)
        VocabStore.shared.unmark(VocabStore.lookupKey(for: taughtWord))
        super.tearDown()
    }

    func testLearningAWordChecksItOffInsteadOfRemovingIt() {
        // The book stores LEMMAS (lowercased); German nouns arrive capitalized.
        let taughtWord = self.taughtWord.lowercased()
        let talk = session(saying: taughtWord)

        let before = TalkCurriculum.build(session: talk, proficiency: .a1, shadowAttempts: [], drillCards: [])
        guard before.words.contains(where: { $0.text == taughtWord }) else {
            return XCTFail("""
                the fluent self's word never made it into the book —                 word=\(taughtWord) lemmas=\(VocabStore.lemmas(in: [taughtWord]))                 level=\(String(describing: CoreVocabulary.level(of: taughtWord)))                 got=\(before.words.map(\.text))
                """)
        }
        XCTAssertNil(before.words.first { $0.text == taughtWord }?.masteredAt)

        VocabStore.shared.markKnown(VocabStore.lookupKey(for: taughtWord))

        let after = TalkCurriculum.build(session: talk, proficiency: .a1, shadowAttempts: [], drillCards: [])
        guard let item = after.words.first(where: { $0.text == taughtWord }) else {
            return XCTFail("learning the word REMOVED it from the book — the old bug")
        }
        XCTAssertNotNil(item.masteredAt, "the word should now be checked off")
        XCTAssertEqual(after.words.count, before.words.count,
                       "the chapter's size must not change as you learn")
        XCTAssertGreaterThan(after.masteredCount, before.masteredCount)
    }
}

/// Bookmarking an expression is not the same as knowing it.
@MainActor
final class ExpressionMasteryEvidenceTests: XCTestCase {

    /// Unique per run: the store persists to disk, and a previous run's
    /// "known" record made this test pass alone but fail in the full suite.
    private let phrase = "zz-flag-it-early-\(UUID().uuidString.prefix(6))"

    override func tearDown() {
        VocabStore.shared.setStudyingExpression(phrase, false)
        VocabStore.shared.setKnownExpression(phrase, false)
        super.tearDown()
    }

    func testBookmarkingDoesNotCountAsHavingUsedIt() {
        VocabStore.shared.setStudyingExpression(phrase, true)

        XCTAssertTrue(VocabStore.shared.hasExpression(phrase),
                      "the bookmark still creates a row (it shows in the notebook)")
        XCTAssertFalse(VocabStore.shared.hasUsedExpression(phrase),
                       "…but saving something is not evidence of knowing it")

        VocabStore.shared.setKnownExpression(phrase, true)
        XCTAssertTrue(VocabStore.shared.hasUsedExpression(phrase))
    }
}

/// A day is complete when work is FINISHED, not when items were handled.
/// Postponing ten cards used to tick the day off exactly like mastering them.
@MainActor
final class DailyGoalCountsFinishedWorkTests: XCTestCase {

    private var log: PracticeLog!
    private let filename = "test-practice-log-goals.json"

    override func setUp() {
        super.setUp()
        log = PracticeLog(filename: filename)
    }

    override func tearDown() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        super.tearDown()
    }

    func testHandlingAnItemIsEffortButNotDone() {
        log.record(.word)                     // "Keep" / pushed to later
        let day = log.day(Date())!
        XCTAssertEqual(day.wordReps, 1, "effort is still recorded")
        XCTAssertEqual(day.wordDone, 0, "…but nothing was finished")
    }

    func testFinishedWorkCountsForBoth() {
        log.record(.word, finished: true)     // "I know"
        let day = log.day(Date())!
        XCTAssertEqual(day.wordReps, 1)
        XCTAssertEqual(day.wordDone, 1)
    }

    func testGoalIsNotMetByPostponingAlone() {
        let goals = GoalStore(defaults: UserDefaults(suiteName: "test.goals.\(UUID().uuidString)")!)
        goals.sentencesPerDay = 0
        goals.wordsPerDay = 2
        goals.expressionsPerDay = 0
        goals.shadowsPerDay = 0

        log.record(.word); log.record(.word)                 // two postponements
        XCTAssertFalse(goals.met(on: Date(), log: log),
                       "a day must not complete itself on postponed items")

        log.record(.word, finished: true); log.record(.word, finished: true)
        XCTAssertTrue(goals.met(on: Date(), log: log))
    }
}

/// The daily hand has to honor the SAME schedule the deck writes. It didn't:
/// only the notebook source asked `isDue`, and the three top-up sources —
/// Watch books, a talk's pickup words, the core list — judged by
/// `VocabStore.records`, which `addStudying` never writes. So a word put away
/// for "10 min" was dealt straight back the moment the session was reopened,
/// and the promise the folders make meant nothing.
@MainActor
final class DailyDeckDealTests: XCTestCase {

    private let schedule = StudyScheduleStore.shared
    private var snoozed: [(StudyScheduleStore.Kind, String)] = []

    override func tearDown() {
        for (kind, text) in snoozed { schedule.clear(kind, text) }
        snoozed = []
        super.tearDown()
    }

    private func snooze(_ kind: StudyScheduleStore.Kind, _ text: String, _ delay: TimeInterval) {
        schedule.snooze(kind, text, until: Date().addingTimeInterval(delay))
        snoozed.append((kind, text))
    }

    /// A core-list word the notebook has never seen — so it can only reach the
    /// hand through the top-up source, which is exactly the one that used to
    /// ignore the schedule.
    private func untouchedCoreWord(atOrAbove level: CEFRLevel) -> String? {
        let minRank = CoreVocabulary.levelRank(level)
        return CoreVocabulary.entries.first {
            CoreVocabulary.levelRank($0.level) >= minRank
                && VocabStore.shared.records[$0.word] == nil
                && !VocabStore.shared.studying.contains($0.word)
        }?.word
    }

    func testSnoozedWordIsNotDealtBackByTheCoreListTopUp() {
        let appState = AppState()
        guard let word = untouchedCoreWord(atOrAbove: appState.proficiency) else {
            return XCTFail("no unseen core word at this level to test with")
        }
        let goal = 400   // deep enough that the top-up source is reached

        // Control: with nothing scheduled, the top-up does reach this word.
        XCTAssertTrue(DailyWordsView.pick(goal: goal, appState: appState).contains(word),
                      "the test can't detect the bug — the word never reaches the hand at all")

        snooze(.word, word, DrillBin.soonDelay)
        XCTAssertFalse(DailyWordsView.pick(goal: goal, appState: appState).contains(word),
                       "a word put away for 10 minutes came straight back")
    }

    /// …and it comes back once the promise is actually due.
    func testTheWordReturnsWhenItsTimeArrives() {
        let appState = AppState()
        guard let word = untouchedCoreWord(atOrAbove: appState.proficiency) else {
            return XCTFail("no unseen core word at this level to test with")
        }
        snooze(.word, word, DrillBin.soonDelay)
        let after = Date().addingTimeInterval(DrillBin.soonDelay + 1)
        XCTAssertTrue(DailyWordsView.pick(goal: 400, appState: appState, now: after).contains(word),
                      "the snooze never expires — the word is gone for good")
    }

    /// The expressions deck had the same hole: a bookmarked phrase is also in
    /// the expression catalog, and that source judged by `isKnownExpression`
    /// alone.
    func testSnoozedExpressionIsNotDealtBackByTheCatalog() {
        let appState = AppState()
        let phrase = "zz-deal-\(UUID().uuidString.prefix(6)) the whole way"
        let store = VocabStore.shared
        store.setStudyingExpression(phrase, true)
        defer { store.setStudyingExpression(phrase, false) }

        XCTAssertTrue(DailyExpressionsView.pick(goal: 400, appState: appState)
                        .contains { $0.caseInsensitiveCompare(phrase) == .orderedSame },
                      "the test can't detect the bug — the phrase never reaches the hand")

        snooze(.expression, phrase, 24 * 60 * 60)
        XCTAssertFalse(DailyExpressionsView.pick(goal: 400, appState: appState)
                        .contains { $0.caseInsensitiveCompare(phrase) == .orderedSame },
                       "a phrase put away until tomorrow came straight back")
    }
}

/// The two decks' folders are the same idea and must stay one implementation:
/// a folder is the WINDOW a return time falls in, not the button that wrote it.
final class StudyFolderBucketTests: XCTestCase {

    func testFoldersBucketByWhenTheItemComesBack() {
        XCTAssertEqual(DrillBin.folder(forReturnIn: DrillBin.soonDelay), .tenMinutes)
        XCTAssertEqual(DrillBin.folder(forReturnIn: 11 * 3600), .tenMinutes)
        XCTAssertEqual(DrillBin.folder(forReturnIn: 24 * 3600), .tomorrow)
        XCTAssertEqual(DrillBin.folder(forReturnIn: 47 * 3600), .tomorrow)
        XCTAssertEqual(DrillBin.folder(forReturnIn: 3 * 24 * 3600), .threeDays)
    }

    /// `upcoming` and `dueItems` partition the file between them — an entry
    /// that fell through both would be invisible in the deck AND in its folder.
    func testUpcomingIsTheMirrorImageOfDue() {
        let filename = "test-folders-\(UUID().uuidString).json"
        let store = StudyScheduleStore(filename: filename)
        defer {
            try? FileManager.default.removeItem(
                at: LanguageScope.activeDirectory.appendingPathComponent(filename))
        }
        let now = Date()
        store.snooze(.word, "past", until: now.addingTimeInterval(-60))
        store.snooze(.word, "soon", until: now.addingTimeInterval(600))
        store.snooze(.expression, "later", until: now.addingTimeInterval(3 * 86_400))

        XCTAssertEqual(store.dueItems(now: now).map(\.text), ["past"])
        XCTAssertEqual(store.upcoming(now: now).map(\.text), ["soon", "later"],
                       "soonest first, and the overdue one belongs to the deck")
    }
}

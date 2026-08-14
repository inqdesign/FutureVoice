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

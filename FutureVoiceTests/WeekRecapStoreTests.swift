import XCTest
@testable import FutureVoice

/// A week's deck slides up once — these pin what counts as "the same week"
/// and that the archive lists each week once.
@MainActor
final class WeekRecapStoreTests: XCTestCase {

    private var store: WeekRecapStore!
    private var defaults: UserDefaults!
    private let filename = "week-recaps-test.json"
    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WeekRecapStoreTests")
        defaults.removePersistentDomain(forName: "WeekRecapStoreTests")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        store = WeekRecapStore(filename: filename, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WeekRecapStoreTests")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        super.tearDown()
    }

    private func recap(endingAt end: Date, talkSeconds: Int = 600) -> WeekRecap {
        WeekRecap(start: end.addingTimeInterval(-7 * day), end: end,
                  activeDays: [true, false, false, false, false, false, false], streak: 1,
                  talkSeconds: talkSeconds, previousTalkSeconds: 0, talks: [],
                  usedCount: 0, used: [], cardsCleared: 0, wordsKnown: 0, expressionsKnown: 0,
                  shadowTakes: 0, shadowAverage: nil, previousShadowAverage: nil, scenes: 0,
                  nowYours: [], sentencesGot: [], newExpressionCount: 0, newExpressions: [],
                  newCards: 0, stumbles: [], shakyLines: [], testScore: nil, testTotal: nil,
                  coach: nil)
    }

    func testNothingSeenYet() {
        XCTAssertFalse(store.wasShown(recap(endingAt: base)))
    }

    func testSeenWeekAndOlderWeeksStaySeen() {
        store.markShown(recap(endingAt: base))
        XCTAssertTrue(store.wasShown(recap(endingAt: base)))
        XCTAssertTrue(store.wasShown(recap(endingAt: base.addingTimeInterval(-7 * day))))
    }

    /// Flying Seoul → Berlin moves "Sat 10:00" seven hours later; moving the
    /// test from Saturday to Wednesday moves it days. Neither is a new week.
    func testShiftedEndOfTheSameWeekIsSeen() {
        store.markShown(recap(endingAt: base))
        XCTAssertTrue(store.wasShown(recap(endingAt: base.addingTimeInterval(7 * 3600))))
        XCTAssertTrue(store.wasShown(recap(endingAt: base.addingTimeInterval(4 * day))))
    }

    func testTheNextWeekIsNew() {
        store.markShown(recap(endingAt: base))
        // One hour short of seven days: a DST change still reads as next week.
        XCTAssertFalse(store.wasShown(recap(endingAt: base.addingTimeInterval(7 * day - 3600))))
        XCTAssertFalse(store.wasShown(recap(endingAt: base.addingTimeInterval(7 * day))))
    }

    func testArchiveListsEachWeekOnceNewestFirstAndSkipsEmptyWeeks() {
        store.save(recap(endingAt: base))
        store.save(recap(endingAt: base.addingTimeInterval(7 * 3600)))       // same week, shifted
        store.save(recap(endingAt: base.addingTimeInterval(7 * day)))
        store.save(recap(endingAt: base.addingTimeInterval(14 * day), talkSeconds: 0).withNoDays)
        let ends = store.archive().map(\.end)
        XCTAssertEqual(ends.count, 2)
        XCTAssertEqual(ends.first, base.addingTimeInterval(7 * day))
    }
}

private extension WeekRecap {
    var withNoDays: WeekRecap {
        var copy = self
        copy.activeDays = Array(repeating: false, count: 7)
        return copy
    }
}

import XCTest
@testable import FutureVoice

/// The study timetable. It schedules the daily call, so the first thing it
/// must do is ring exactly when the call rang before it existed.
final class StudyPlanTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.firstWeekday = 2
        return c
    }()

    /// 2026-10-05 is a Monday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func t(_ h: Int, _ m: Int = 0) -> DailyCallStore.CallTime { .init(hour: h, minute: m) }

    // MARK: - The call

    func testSeededPlanRingsLikeTheOldCall() {
        let plan = StudyPlan.seeded(callTimes: [t(8), t(13)], goalMinutes: 10)
        // Before both: both of today's.
        XCTAssertEqual(plan.callDates(after: at(5, 7), calendar: cal), [at(5, 8), at(5, 13)])
        // Between: the rest of today.
        XCTAssertEqual(plan.callDates(after: at(5, 9), calendar: cal), [at(5, 13)])
        // After the last: tomorrow's first only.
        XCTAssertEqual(plan.callDates(after: at(5, 14), calendar: cal), [at(6, 8)])
    }

    func testWeekdaysAndRestDaysAreSkipped() {
        var plan = StudyPlan()
        // Mon (2) and Wed (4) only.
        plan.blocks = [.init(kind: .talk, weekdays: [2, 4], hour: 8, minute: 0, minutes: 10)]
        // Monday evening → Wednesday morning, not Tuesday.
        XCTAssertEqual(plan.callDates(after: at(5, 20), calendar: cal), [at(7, 8)])
        // Wednesday off → the next Monday.
        plan.restDays = [StudyPlan.dayKey(at(7, 0), calendar: cal)]
        XCTAssertEqual(plan.callDates(after: at(5, 20), calendar: cal), [at(12, 8)])
    }

    func testNoTalkBlocksMeansNoRing() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .words, weekdays: Set(1...7), hour: 8, minute: 0, minutes: 10)]
        XCTAssertEqual(plan.callDates(after: at(5, 7), calendar: cal), [])
    }

    // MARK: - Derived blocks

    func testReviewAndSayItAgainOnlyOnPlannedDays() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [2], hour: 8, minute: 0, minutes: 10)]
        plan.autoReview = true
        plan.autoSayItAgain = true
        let monday = plan.occurrences(on: at(5, 0), calendar: cal)
        XCTAssertEqual(monday.map(\.kind), [.talk, .sayItAgain, .review])
        XCTAssertEqual(monday[1].start, at(5, 8, 10))
        // Tuesday has nothing planned, so no review slot either.
        XCTAssertTrue(plan.occurrences(on: at(6, 0), calendar: cal).isEmpty)
    }

    func testWeeklyTestLandsOnItsWeekday() {
        let plan = StudyPlan()
        let sat = plan.occurrences(on: at(10, 0),
                                   test: WeeklyTestSchedule(weekday: 7, hour: 10, minute: 0),
                                   calendar: cal)
        XCTAssertEqual(sat.map(\.kind), [.test])
    }

    func testReviewLoadSplitsBetweenSlots() {
        let slots = [at(5, 21), at(6, 21)]
        let due = [at(4, 9), at(5, 12), at(5, 22), at(6, 20), at(7, 9)]
        let load = StudyPlan.reviewLoad(slots: slots, dueDates: due)
        XCTAssertEqual(load[at(5, 21)], 2)   // overdue + same day
        XCTAssertEqual(load[at(6, 21)], 2)   // came due since
    }

    // MARK: - Moving

    func testJustThisDayLeavesTheWeekAlone() {
        var plan = StudyPlan()
        let id = UUID()
        plan.blocks = [.init(id: id, kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10)]
        let moved = plan.moving(blockId: id, on: at(6, 0), to: at(6, 9), scope: .thisDay, calendar: cal)!
        XCTAssertEqual(moved.occurrences(on: at(6, 0), calendar: cal).first?.start, at(6, 9))
        XCTAssertEqual(moved.occurrences(on: at(7, 0), calendar: cal).first?.start, at(7, 8))
        XCTAssertEqual(moved.occurrences(on: at(13, 0), calendar: cal).first?.start, at(13, 8))
    }

    func testEveryWeekSplitsOneWeekdayOff() {
        var plan = StudyPlan()
        let id = UUID()
        plan.blocks = [.init(id: id, kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10)]
        // Tuesday 8:00 → Tuesday 9:00, every week.
        let moved = plan.moving(blockId: id, on: at(6, 0), to: at(6, 9), scope: .everyWeek, calendar: cal)!
        XCTAssertEqual(moved.occurrences(on: at(13, 0), calendar: cal).first?.start, at(13, 9))
        XCTAssertEqual(moved.occurrences(on: at(14, 0), calendar: cal).first?.start, at(14, 8))
    }

    func testAllDaysMovesTheWholeBlock() {
        var plan = StudyPlan()
        let id = UUID()
        plan.blocks = [.init(id: id, kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10)]
        let moved = plan.moving(blockId: id, on: at(6, 0), to: at(6, 7, 30), scope: .allDays, calendar: cal)!
        XCTAssertEqual(moved.blocks.count, 1)
        XCTAssertEqual(moved.occurrences(on: at(9, 0), calendar: cal).first?.start, at(9, 7, 30))
    }

    func testAFifthCallTimeIsRefused() {
        var plan = StudyPlan.seeded(callTimes: [t(7), t(8), t(12), t(18)], goalMinutes: 10)
        let id = plan.blocks[0].id
        XCTAssertNil(plan.moving(blockId: id, on: at(6, 0), to: at(6, 21), scope: .thisDay, calendar: cal))
        plan.blocks[0].weekdays = [3]
        // Moving the only 7:00 block (Tuesday) keeps four distinct times.
        XCTAssertNotNil(plan.moving(blockId: id, on: at(6, 0), to: at(6, 21), scope: .everyWeek, calendar: cal))
    }

    func testCallTimesEditedElsewhereAreAdopted() {
        var plan = StudyPlan.seeded(callTimes: [t(8)], goalMinutes: 10)
        plan.blocks[0].weekdays = [2, 3]
        plan.adoptCallTimes([t(8), t(19)], defaultMinutes: 15)
        let talk = plan.blocks.filter { $0.kind == .talk }
        XCTAssertEqual(talk.count, 2)
        // The kept time keeps its weekdays; the new one runs every day.
        XCTAssertEqual(talk.first { $0.hour == 8 }?.weekdays, [2, 3])
        XCTAssertEqual(talk.first { $0.hour == 19 }?.weekdays, Set(1...7))
        plan.adoptCallTimes([t(19)], defaultMinutes: 15)
        XCTAssertEqual(plan.blocks.filter { $0.kind == .talk }.map(\.hour), [19])
    }

    // MARK: - What happened

    func testDoneAtAnotherTimeStillCounts() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [3], hour: 8, minute: 0, minutes: 10),
                       .init(kind: .words, weekdays: [3], hour: 20, minute: 0, minutes: 10)]
        let occ = plan.occurrences(on: at(6, 0), calendar: cal)
        let talks = [PlannerDay.Talk(id: UUID(), start: at(6, 12, 20), end: at(6, 12, 32), title: "x")]
        let events = [ActivityEventLog.Event(kind: .shadow, at: at(6, 15))]
        let actuals = PlannerDay.actuals(talks: talks, events: events)
        let done = PlannerDay.done(planned: occ, actuals: actuals, events: events, testFinished: false)
        XCTAssertTrue(done.contains(occ.first { $0.kind == .talk }!.id))
        XCTAssertFalse(done.contains(occ.first { $0.kind == .words }!.id))
        // Shadowing wasn't planned; it is listed as extra.
        XCTAssertEqual(PlannerDay.unplanned(actuals: actuals, planned: occ).map(\.kind), [.shadow])
    }

    func testRepsCloseTogetherAreOneSitting() {
        let events = [at(6, 20, 0), at(6, 20, 4), at(6, 20, 9), at(6, 21, 0)]
            .map { ActivityEventLog.Event(kind: .drill, at: $0) }
        let acts = PlannerDay.actuals(talks: [], events: events)
        XCTAssertEqual(acts.map(\.count), [3, 1])
    }
}

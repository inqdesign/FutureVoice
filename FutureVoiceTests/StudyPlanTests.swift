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

    func testSayItAgainIsAnOrdinaryBlock() {
        // Seeded after the first talk, every day — and movable like any block.
        let plan = StudyPlan.seeded(callTimes: [t(8), t(13)], goalMinutes: 10)
        let again = plan.blocks.first { $0.kind == .sayItAgain }!
        XCTAssertEqual(again.startMinute, 8 * 60 + 10)
        let moved = plan.moving(blockId: again.id, on: at(6, 0), to: at(6, 20), scope: .everyWeek, calendar: cal)!
        XCTAssertEqual(moved.occurrences(on: at(6, 0), calendar: cal).last?.kind, .sayItAgain)
        XCTAssertEqual(moved.occurrences(on: at(6, 0), calendar: cal).last?.start, at(6, 20))
    }

    func testLegacyDerivedSayItAgainBecomesBlocks() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [2, 3], hour: 8, minute: 0, minutes: 10),
                       .init(kind: .talk, weekdays: [3], hour: 7, minute: 0, minutes: 15)]
        plan.autoSayItAgain = true
        let converted = plan.convertingLegacySayItAgain()
        XCTAssertFalse(converted.autoSayItAgain)
        // After each weekday's FIRST talk, where it used to be drawn.
        XCTAssertEqual(converted.occurrences(on: at(5, 0), calendar: cal)
            .first { $0.kind == .sayItAgain }?.start, at(5, 8, 10))
        XCTAssertEqual(converted.occurrences(on: at(6, 0), calendar: cal)
            .first { $0.kind == .sayItAgain }?.start, at(6, 7, 15))
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

    func testCountsFillBlocksInOrder() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [3], hour: 8, minute: 0, minutes: 10),
                       .init(kind: .talk, weekdays: [3], hour: 20, minute: 0, minutes: 10),
                       .init(kind: .words, weekdays: [3], hour: 19, minute: 0, minutes: 10)]
        let occ = plan.occurrences(on: at(6, 0), calendar: cal)
        var totals = PlannerDay.Totals()
        totals.talkMinutes = 15
        totals.words = 4
        let p = PlannerDay.progress(planned: occ, totals: totals)
        let talks = occ.filter { $0.kind == .talk }
        XCTAssertEqual(p[talks[0].id], 1)
        XCTAssertEqual(p[talks[1].id]!, 0.5, accuracy: 0.001)
        XCTAssertEqual(p[occ.first { $0.kind == .words }!.id]!, 0.4, accuracy: 0.001)
        XCTAssertEqual(PlannerDay.done(planned: occ, totals: totals), [talks[0].id])
    }

    func testWordsExpressionsAndShadowFoldIntoReview() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .words, weekdays: [2, 4], hour: 19, minute: 0, minutes: 10),
                       .init(kind: .expressions, weekdays: [2, 4], hour: 19, minute: 0, minutes: 3),
                       .init(kind: .shadow, weekdays: [7], hour: 11, minute: 0, minutes: 2),
                       .init(kind: .talk, weekdays: Set(1...7), hour: 8, minute: 0, minutes: 10)]
        let folded = plan.foldingIntoReview()
        XCTAssertFalse(folded.blocks.contains { $0.kind.isFoldedIntoReview })
        let review = folded.blocks.filter { $0.kind == .review }
        XCTAssertEqual(review.count, 2)
        XCTAssertEqual(review.first { $0.hour == 19 }?.minutes, 13)
        XCTAssertEqual(review.first { $0.hour == 11 }?.minutes, 2)
        XCTAssertEqual(folded.foldingIntoReview(), folded)
    }

    func testReviewCountsEveryKindOfReview() {
        var totals = PlannerDay.Totals()
        totals.words = 4; totals.expressions = 2; totals.cards = 5; totals.shadow = 1
        XCTAssertEqual(totals.amount(for: .review), 12)
    }

    func testASpeechTakeKeepsASpeechBlock() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .speech, weekdays: [3], hour: 20, minute: 0, minutes: 1)]
        let occ = plan.occurrences(on: at(6, 0), calendar: cal)
        var totals = PlannerDay.Totals()
        XCTAssertTrue(PlannerDay.done(planned: occ, totals: totals).isEmpty)
        totals.speech = 1
        XCTAssertEqual(PlannerDay.done(planned: occ, totals: totals), [occ[0].id])
        let acts = PlannerDay.actuals(talks: [], events: [.init(kind: .speech, at: at(6, 20, 5))])
        XCTAssertEqual(acts.map(\.kind), [.speech])
        XCTAssertEqual(PlannerDay.absorbed(planned: occ, actuals: acts).count, 1)
        XCTAssertTrue(StudyPlan.Kind.placeable.contains(.speech))
    }

    func testOldMinutePlansBecomeCounts() {
        var plan = StudyPlan()
        plan.unitsVersion = nil
        plan.blocks = [.init(kind: .talk, weekdays: [2], hour: 8, minute: 0, minutes: 15),
                       .init(kind: .sayItAgain, weekdays: [2], hour: 8, minute: 15, minutes: 5)]
        let c = plan.convertingToCounts()
        XCTAssertEqual(c.blocks.first { $0.kind == .talk }?.minutes, 15)
        XCTAssertEqual(c.blocks.first { $0.kind == .sayItAgain }?.minutes, 1)
        XCTAssertEqual(c.unitsVersion, 1)
    }

    func testRepsCloseTogetherAreOneSitting() {
        let events = [at(6, 20, 0), at(6, 20, 4), at(6, 20, 9), at(6, 21, 0)]
            .map { ActivityEventLog.Event(kind: .drill, at: $0) }
        let acts = PlannerDay.actuals(talks: [], events: events)
        XCTAssertEqual(acts.map(\.count), [3, 1])
    }

    func testASittingOnThePlanIsOneBlock() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [3, 4], hour: 8, minute: 0, minutes: 10)]
        let tue = plan.occurrences(on: at(6, 0), calendar: cal)
        let onTime = PlannerDay.actuals(
            talks: [.init(id: UUID(), start: at(6, 8, 3), end: at(6, 8, 15), title: "x")], events: [])
        XCTAssertEqual(PlannerDay.absorbed(planned: tue, actuals: onTime).count, 1)
        // At noon it is done, but drawn where it happened, not merged.
        let atNoon = PlannerDay.actuals(
            talks: [.init(id: UUID(), start: at(6, 12), end: at(6, 12, 10), title: "x")], events: [])
        XCTAssertTrue(PlannerDay.absorbed(planned: tue, actuals: atNoon).isEmpty)
    }

    func testDraggedDayLandsFirstThenTheRestCanFollow() {
        var plan = StudyPlan()
        let id = UUID()
        plan.blocks = [.init(id: id, kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10)]
        // Release: Tuesday alone is already at 9:00.
        let moved = plan.moving(blockId: id, on: at(6, 0), to: at(6, 9), scope: .everyWeek, calendar: cal)!
        XCTAssertEqual(moved.occurrences(on: at(6, 0), calendar: cal).first?.start, at(6, 9))
        XCTAssertEqual(moved.occurrences(on: at(7, 0), calendar: cal).first?.start, at(7, 8))
        // "Every day it runs": the rest follow, and it is one block again.
        let all = moved.following(blockId: id, toHour: 9, minute: 0)!
        XCTAssertEqual(all.blocks.count, 1)
        XCTAssertEqual(all.blocks[0].weekdays, Set(2...6))
        XCTAssertEqual(all.occurrences(on: at(7, 0), calendar: cal).first?.start, at(7, 9))
    }

    // MARK: - The promise

    private func walk(_ marks: [Int: PracticeStats.DayStanding], today: Int) -> Int {
        PracticeStats.streak(endingAt: at(today, 12), floor: at(1, 0), calendar: cal) { d in
            marks[self.cal.component(.day, from: d)] ?? .missed
        }
    }

    func testRestDaysNeitherCountNorBreak() {
        // Thu kept, Fri rest, Sat kept, Sun kept → 3.
        XCTAssertEqual(walk([1: .kept, 2: .rest, 3: .kept, 4: .kept], today: 4), 3)
    }

    func testTodayIsAliveUntilItIsOver() {
        // Today (5th) not kept yet: the streak is yesterday's.
        XCTAssertEqual(walk([3: .kept, 4: .kept, 5: .missed], today: 5), 2)
        XCTAssertEqual(walk([3: .kept, 4: .kept, 5: .kept], today: 5), 3)
    }

    func testAMissedDayEndsIt() {
        XCTAssertEqual(walk([2: .kept, 3: .missed, 4: .kept], today: 4), 1)
    }


    func testRestWeekdaysPlanNothing() {
        var plan = StudyPlan.seeded(callTimes: [t(8)], goalMinutes: 10)
        plan.offWeekdays = [1, 7]
        XCTAssertTrue(plan.occurrences(on: at(10, 0), calendar: cal).isEmpty)   // Saturday
        XCTAssertFalse(plan.occurrences(on: at(9, 0), calendar: cal).isEmpty)   // Friday
        // Friday evening → the call skips the weekend to Monday.
        XCTAssertEqual(plan.callDates(after: at(9, 20), calendar: cal), [at(12, 8)])
    }

    func testReviewSwitchBecomesABlock() {
        var plan = StudyPlan()
        plan.blocks = [.init(kind: .talk, weekdays: [2, 4], hour: 8, minute: 0, minutes: 10)]
        plan.autoReview = true
        plan.reviewHour = 21
        let c = plan.convertingReviewSwitch()
        XCTAssertFalse(c.autoReview)
        let review = c.blocks.first { $0.kind == .review }
        XCTAssertEqual(review?.weekdays, [2, 4])
        XCTAssertEqual(review?.hour, 21)
        XCTAssertTrue(c.hasReviewBlocks)
    }

    func testAnAnytimeTalkTakesTheCallsTime() {
        // Turning the call on (or picking its time) gives an "any time"
        // routine its call: the routine's timed talks ARE the calls.
        var plan = StudyPlan.seeded(callTimes: [], goalMinutes: 15, callEnabled: false)
        XCTAssertFalse(plan.hasTimedTalk)
        plan.adoptCallTimes([t(8)], defaultMinutes: 10)
        let talks = plan.blocks.filter { $0.kind == .talk }
        XCTAssertEqual(talks.count, 1)
        XCTAssertEqual(talks.first?.hour, 8)
        XCTAssertEqual(talks.first?.minutes, 15, "keeps the routine's own minutes")
        XCTAssertEqual(talks.first?.isAnytime, false)
        XCTAssertEqual(plan.callDates(after: at(5, 7), calendar: cal).first, at(5, 8))
    }

    func testOnboardingRoutineWithoutACallIsAnytime() {
        let plan = StudyPlan.seeded(callTimes: [t(8)], goalMinutes: 15, callEnabled: false, now: at(5, 9))
        XCTAssertEqual(plan.blocks.count, 1)
        XCTAssertTrue(plan.blocks[0].isAnytime)
        XCTAssertEqual(plan.blocks[0].minutes, 15)
        XCTAssertNotNil(plan.streakSince)              // a promise from the start
        XCTAssertFalse(plan.hasTimedTalk)              // the call keeps its own times
        let occ = plan.occurrences(on: at(6, 0), calendar: cal)[0]
        XCTAssertFalse(occ.isOver(now: at(6, 23, 59), calendar: cal))  // anytime lasts the day
        XCTAssertTrue(occ.isOver(now: at(7, 0, 1), calendar: cal))
    }

    func testAnUntouchedOldPlanBecomesTheOnboardingPromise() {
        var old = StudyPlan.seeded(callTimes: [t(8)], goalMinutes: 10)   // timed, from the old seeding
        old.streakSince = nil
        old.unitsVersion = 1
        let up = old.upgradingToOnboardingPromise(callEnabled: false, goalMinutes: 10, now: at(5, 9))
        XCTAssertEqual(up.blocks.filter { $0.kind == .talk }.map(\.isAnytime), [true])
        XCTAssertFalse(up.blocks.contains { $0.kind == .sayItAgain })
        XCTAssertNotNil(up.streakSince)
        // A routine the learner already changed is kept as it is.
        var mine = old
        mine.streakSince = at(1, 0)
        let kept = mine.upgradingToOnboardingPromise(callEnabled: false, goalMinutes: 10)
        XCTAssertEqual(kept.blocks, mine.blocks)
    }
}

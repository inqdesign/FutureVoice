import XCTest
@testable import FutureVoice

/// The usage coaching (`StudyHabits`, `HabitAdvisor`): the same logs always
/// give the same findings, and each finding rests on its numbers.
final class StudyHabitsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    /// Monday 2026-10-19 00:00 Berlin.
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19))! }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(byAdding: .minute, value: day * 1440 + hour * 60 + minute, to: monday)!
    }

    private func habits(_ sittings: [StudyHabits.Sitting], days: Int = 7, corrections: Int = 0,
                        fixes: [WeekRecap.Stumble] = [], plan: [StudyPlan.Block] = []) -> StudyHabits {
        StudyHabits.compute(start: monday, end: at(days, 0), sittings: sittings,
                            correctionsMade: corrections, repeatedFixes: fixes,
                            planBlocks: plan, calendar: cal)
    }

    func testAllInOneDayIsCramming() {
        let h = habits([.init(activity: .talk, at: at(6, 20), minutes: 45),
                        .init(activity: .talk, at: at(6, 21), minutes: 10)])
        XCTAssertEqual(h.activeDays, 1)
        let f = HabitAdvisor.findings(h)
        XCTAssertEqual(f.first?.rule, "cramming")
        XCTAssertEqual(f.first?.tone, .firm)
    }

    func testTalkingWithoutReviewIsFirmAndAddsReviewAfterTheTalk() {
        let sittings = (0..<5).map { StudyHabits.Sitting(activity: .talk, at: at($0, 8), minutes: 10) }
        let fix = WeekRecap.Stumble(was: "since three years", now: "for three years", count: 3)
        let h = habits(sittings, corrections: 14, fixes: [fix])
        let f = HabitAdvisor.findings(h)
        let noReview = f.first { $0.rule == "no-review" }
        XCTAssertEqual(noReview?.tone, .firm)
        XCTAssertTrue(noReview?.facts.contains { $0.contains("14") } == true)
        // Five of seven days is consistent — the good news is said too.
        XCTAssertTrue(f.contains { $0.tone == .good })
        let base = [StudyPlan.Block(kind: .talk, weekdays: Set(1...7), hour: 8, minute: 0, minutes: 10)]
        let routine = HabitAdvisor.routine(base: base, habits: h, findings: f, goalMinutes: 10)
        let review = routine.first { $0.block.kind == .review }
        XCTAssertEqual(review?.rule, "no-review")
        XCTAssertEqual(review.map { $0.block.startMinute }, 8 * 60 + 15)
        // The block is the size the finding names ("a short review (10 cards)").
        XCTAssertEqual(review?.block.minutes, 10)
        XCTAssertTrue(noReview?.change?.contains("(10 cards)") == true)
        XCTAssertTrue(routine.contains { $0.block.kind == .sayItAgain })
    }

    func testHabitHourIsWhenTheyActuallyPractise() {
        let sittings = (0..<4).map { StudyHabits.Sitting(activity: .talk, at: at($0, 22, 10), minutes: 8) }
            + [.init(activity: .talk, at: at(5, 9), minutes: 8)]
        let h = habits(sittings)
        XCTAssertEqual(h.habitHour, 22)
        XCTAssertEqual(h.habitShare, 0.8, accuracy: 0.01)
    }

    func testPlannedReviewNeverDoneMovesToTheHabitHour() {
        let sittings = (0..<5).map { StudyHabits.Sitting(activity: .talk, at: at($0, 8), minutes: 10) }
        let plan = [StudyPlan.Block(kind: .talk, weekdays: Set(1...7), hour: 8, minute: 0, minutes: 10),
                    StudyPlan.Block(kind: .review, weekdays: Set(1...7), hour: 21, minute: 30, minutes: 10)]
        let h = habits(sittings, plan: plan)
        XCTAssertEqual(h.plan.first { $0.kind == .review }?.keptDays, 0)
        let f = HabitAdvisor.findings(h)
        XCTAssertTrue(f.contains { $0.rule == "plan-missed-review" })
        let routine = HabitAdvisor.routine(base: plan, habits: h, findings: f, goalMinutes: 10)
        XCTAssertEqual(routine.first { $0.block.kind == .review }?.block.hour, 8)
    }

    func testAGapInsideTheWindowIsCountedFromTheFirstSitting() {
        let h = habits([.init(activity: .talk, at: at(0, 9), minutes: 10),
                        .init(activity: .talk, at: at(6, 9), minutes: 10)], days: 8)
        XCTAssertEqual(h.longestGapDays, 5)
        XCTAssertTrue(HabitAdvisor.findings(h).contains { $0.rule == "gap" || $0.rule == "cramming" })
    }

    func testNeverMoreThanFourAndNeverOnlyCriticism() {
        let sittings = (0..<6).map { StudyHabits.Sitting(activity: .talk, at: at($0, 8), minutes: 10) }
        let plan = StudyPlan.Kind.allCases.filter { $0 != .talk && $0 != .test }.map {
            StudyPlan.Block(kind: $0, weekdays: Set(1...7), hour: 21, minute: 0, minutes: 2)
        }
        let f = HabitAdvisor.findings(habits(sittings, corrections: 9,
                                             fixes: [.init(was: "a", now: "b", count: 2)], plan: plan))
        XCTAssertLessThanOrEqual(f.count, HabitAdvisor.maxFindings)
        XCTAssertEqual(f.last?.tone, .good)
    }

    func testAShortTrialStillGetsEvidence() {
        // Three days, a talk each day, some review, corrections, no redo.
        let sittings = (0..<3).map { StudyHabits.Sitting(activity: .talk, at: at($0, 18), minutes: 4) }
            + (0..<11).map { StudyHabits.Sitting(activity: .review, at: at(2, 19, $0)) }
        let h = habits(sittings, days: 3, corrections: 7)
        let rules = HabitAdvisor.findings(h).map(\.rule)
        XCTAssertTrue(rules.contains("no-say-again"))
        XCTAssertTrue(rules.contains("came-back") || rules.contains("reviewed"))
        let routine = HabitAdvisor.routine(base: [], habits: h, findings: HabitAdvisor.findings(h), goalMinutes: 10)
        XCTAssertEqual(routine.first { $0.block.kind == .sayItAgain }?.rule, "no-say-again")
    }
}

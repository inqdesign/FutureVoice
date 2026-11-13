import XCTest
@testable import FutureVoice

final class GoalPlanTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!
    private let qs = (1...7).map { "Q\($0)" }

    private func plan(days: Int, open: [String], talkDays: Set<Int> = Set(1...7)) -> GoalPlan {
        let day = cal.date(byAdding: .day, value: days, to: now)!
        let goal = UpcomingGoal(kind: .exam, title: "OPIc", date: day, language: "en")
        return GoalPlan.make(goal: goal, open: open, total: 7, day: day, talkDays: talkDays, now: now, calendar: cal)
    }

    func testEveryOpenQuestionGetsADayThenMockRunsThenTheDay() {
        let p = plan(days: 18, open: qs)
        XCTAssertEqual(p.rows.first?.item, .question("Q1"))
        XCTAssertEqual(p.rows.compactMap { if case .question(let q) = $0.item { return q } else { return nil } }, qs)
        XCTAssertEqual(p.rows.suffix(3).map(\.item), [.rehearse, .rehearse, .theDay])
        XCTAssertTrue(p.rows.contains { $0.item == .catchUp })
    }

    func testShortRunDoublesUpAndSkipsTheMockRun() {
        let p = plan(days: 4, open: qs)
        XCTAssertEqual(p.rows.filter { $0.item.isQuestion }.count, 7)
        XCTAssertFalse(p.rows.contains { $0.item == .rehearse })
        XCTAssertEqual(p.rows.last?.item, .theDay)
    }

    func testOnlyTheRoutinesTalkDaysAreUsed() {
        // Mondays and Thursdays only.
        let p = plan(days: 14, open: ["Q1", "Q2"], talkDays: [2, 5])
        for row in p.rows.dropLast() {
            XCTAssertTrue([2, 5].contains(cal.component(.weekday, from: row.date)))
        }
    }

    func testEverythingReadyIsAllMockRuns() {
        let p = plan(days: 5, open: [])
        XCTAssertEqual(Set(p.rows.dropLast().map(\.item)).count, 1)
        XCTAssertEqual(p.rows.first?.item, .rehearse)
    }
}

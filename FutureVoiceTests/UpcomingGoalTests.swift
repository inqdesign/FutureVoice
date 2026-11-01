import XCTest
@testable import FutureVoice

final class UpcomingGoalTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func goal(inDays n: Int, from now: Date) -> UpcomingGoal {
        UpcomingGoal(kind: .interview, title: "Interview",
                     date: cal.date(byAdding: .day, value: n, to: now), language: "en")
    }

    func testDaysLeftGoesNegativeOnceTheDayHasPassed() {
        let now = Date()
        XCTAssertEqual(goal(inDays: 3, from: now).daysLeft(now: now, calendar: cal), 3)
        XCTAssertEqual(goal(inDays: 0, from: now).daysLeft(now: now, calendar: cal), 0)
        XCTAssertEqual(goal(inDays: -2, from: now).daysLeft(now: now, calendar: cal), -2)
    }

    func testAPastGoalIsPastAndLeavesComingUp() {
        let now = Date()
        XCTAssertTrue(goal(inDays: -1, from: now).isPast(now: now))
        XCTAssertFalse(goal(inDays: 0, from: now).isPast(now: now))
        XCTAssertNil(goal(inDays: -1, from: now).countdown(now: now))
    }
}

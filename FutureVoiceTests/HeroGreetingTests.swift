import XCTest
@testable import FutureVoice

/// Two things decide the Talk hero's line: WHICH kind of line today deserves,
/// and WHICH phrasing of it. The second one is the fragile half — the hero
/// re-renders on every scroll frame, so the rotation must be a function of the
/// day and the finished-call cursor, never of the moment it was asked.
final class HeroGreetingTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func input(_ mutate: (inout HeroGreeting.Input) -> Void = { _ in }) -> HeroGreeting.Input {
        var i = HeroGreeting.Input(now: Date(timeIntervalSince1970: 1_770_000_000),
                                   sessionCount: 5,
                                   lastSessionEndedAt: nil,
                                   calendar: cal)
        mutate(&i)
        return i
    }

    func testOrdinaryDayAsksAQuestion() {
        XCTAssertEqual(HeroGreeting.kind(for: input()), .question)
    }

    func testFirstRunOutranksEverything() {
        let i = input {
            $0.sessionCount = 0
            $0.hasMissedCall = true
        }
        XCTAssertEqual(HeroGreeting.kind(for: i), .firstRun)
    }

    func testMissedCallOutranksTheQuestion() {
        XCTAssertEqual(HeroGreeting.kind(for: input { $0.hasMissedCall = true }), .missedCall)
    }

    func testComebackNeedsARealGapAndNothingSpokenToday() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!

        XCTAssertEqual(HeroGreeting.kind(for: input { $0.lastSessionEndedAt = threeDaysAgo }),
                       .comeback)
        // A weekend off is not an absence.
        XCTAssertNotEqual(HeroGreeting.kind(for: input { $0.lastSessionEndedAt = yesterday }),
                          .comeback)
        // Already talking today — the gap is history.
        let spokeToday = input {
            $0.lastSessionEndedAt = threeDaysAgo
            $0.todaySpokenSeconds = 60
        }
        XCTAssertNotEqual(HeroGreeting.kind(for: spokeToday), .comeback)
    }

    func testGoalMet() {
        let i = input {
            $0.todaySpokenSeconds = 10 * 60
            $0.dailyGoalMinutes = 10
        }
        XCTAssertEqual(HeroGreeting.kind(for: i), .goalMet)
    }

    /// The whole reason the rotation is derived rather than stored: asking
    /// twice inside one day — one scroll frame or eight hours apart — has to
    /// give the same sentence back.
    func testLineIsStableWithinADay() {
        let morning = Date(timeIntervalSince1970: 1_770_000_000)
        XCTAssertEqual(HeroGreeting.text(for: input { $0.now = morning }),
                       HeroGreeting.text(for: input { $0.now = morning }))

        // Same day, same time-of-day bucket, hours apart.
        let laterSameEvening = input { $0.now = evening(morning, hour: 19) }
        let stillThatEvening = input { $0.now = evening(morning, hour: 21) }
        XCTAssertEqual(HeroGreeting.text(for: laterSameEvening),
                       HeroGreeting.text(for: stillThatEvening))
    }

    func testTheDayAndTheCallCursorBothMoveTheLine() {
        let today = input()
        let tomorrow = input { $0.now = cal.date(byAdding: .day, value: 1, to: $0.now)! }
        let afterACall = input { $0.rotationCursor = 1 }

        XCTAssertNotEqual(HeroGreeting.text(for: today), HeroGreeting.text(for: tomorrow))
        XCTAssertNotEqual(HeroGreeting.text(for: today), HeroGreeting.text(for: afterACall))
    }

    /// A cursor that has grown for years must still land inside the pool.
    func testHugeCursorStaysInRange() {
        for cursor in [0, 7, 999, Int.max - 1] {
            let line = HeroGreeting.text(for: input { $0.rotationCursor = cursor })
            XCTAssertFalse(line.isEmpty)
        }
    }

    /// Time of day still colours the question — the pool is per bucket.
    func testMorningAndNightDrawFromDifferentPools() {
        let morning = input { $0.now = evening($0.now, hour: 8) }
        let night = input { $0.now = evening($0.now, hour: 23) }
        XCTAssertNotEqual(HeroGreeting.text(for: morning), HeroGreeting.text(for: night))
    }

    private func evening(_ day: Date, hour: Int) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }
}

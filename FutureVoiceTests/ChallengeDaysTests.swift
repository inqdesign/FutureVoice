import XCTest
@testable import FutureVoice

final class ChallengeDaysTests: XCTestCase {
    private var seoul: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        seoul.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testOnlyDaysWithANumberAreSentOldestFirstByLocalDate() {
        let now = at(2026, 12, 3, 9)
        let talk: [Date: Int] = [seoul.startOfDay(for: at(2026, 12, 1)): 250,
                                 seoul.startOfDay(for: now): 300]
        // 00:30 on Dec 2 in Seoul is still Dec 1 in UTC: it is Dec 2's take.
        let days = ChallengeDayPlan.days(now: now, calendar: seoul, talkSeconds: { talk[$0] ?? 0 },
                                         speechAt: [at(2026, 12, 2, 0, 30), at(2026, 12, 3, 8), at(2026, 12, 3, 8, 30)])
        XCTAssertEqual(days, [
            .init(day: "2026-12-01", talkSeconds: 250, speechTakes: 0),
            .init(day: "2026-12-02", talkSeconds: 0, speechTakes: 1),
            .init(day: "2026-12-03", talkSeconds: 300, speechTakes: 2),
        ])
    }

    func testOnlyTheLastFourteenDaysGo() {
        let now = at(2026, 12, 20)
        let days = ChallengeDayPlan.days(now: now, calendar: seoul, talkSeconds: { _ in 60 },
                                         speechAt: [at(2026, 12, 1)])
        XCTAssertEqual(days.count, ChallengeDayPlan.windowDays)
        XCTAssertEqual(days.first?.day, "2026-12-07")
        XCTAssertEqual(days.last?.day, "2026-12-20")
        XCTAssertTrue(days.allSatisfy { $0.speechTakes == 0 })
    }

    func testTheFingerprintMovesWithANumberOrTheTimeZone() {
        let a = [ChallengeDay(day: "2026-12-01", talkSeconds: 240, speechTakes: 1)]
        let print = ChallengeDayPlan.fingerprint(a, timeZone: "Asia/Seoul")
        XCTAssertEqual(print, ChallengeDayPlan.fingerprint(a, timeZone: "Asia/Seoul"))
        XCTAssertNotEqual(print, ChallengeDayPlan.fingerprint(a, timeZone: "Europe/Berlin"))
        var more = a
        more[0].speechTakes = 2
        XCTAssertNotEqual(print, ChallengeDayPlan.fingerprint(more, timeZone: "Asia/Seoul"))
    }

    func testAParticipantSendsOnlyWhatChanged() {
        let now = at(2026, 12, 3)
        func step(_ participant: Bool?, asked: Date? = nil, failed: Date? = nil, sent: String? = nil) -> ChallengeDayPlan.Step {
            ChallengeDayPlan.step(participant: participant, askedAt: asked, failedAt: failed,
                                  sentFingerprint: sent, fingerprint: "new", now: now)
        }
        XCTAssertEqual(step(true, sent: "new"), .wait)
        XCTAssertEqual(step(true, sent: "old"), .send)
        XCTAssertEqual(step(true, failed: now.addingTimeInterval(-60), sent: "old"), .wait)
        XCTAssertEqual(step(true, failed: now.addingTimeInterval(-3600), sent: "old"), .send)
    }

    func testSomeoneOutsideTheProgramIsAskedOnceADay() {
        let now = at(2026, 12, 3)
        func step(_ participant: Bool?, asked: Date? = nil, failed: Date? = nil) -> ChallengeDayPlan.Step {
            ChallengeDayPlan.step(participant: participant, askedAt: asked, failedAt: failed,
                                  sentFingerprint: nil, fingerprint: "new", now: now)
        }
        XCTAssertEqual(step(nil), .ask)
        XCTAssertEqual(step(false, asked: now.addingTimeInterval(-3600)), .wait)
        XCTAssertEqual(step(false, asked: now.addingTimeInterval(-25 * 3600)), .ask)
        // The RPC is not there yet: no storm.
        XCTAssertEqual(step(nil, failed: now.addingTimeInterval(-3600)), .wait)
        XCTAssertEqual(step(nil, failed: now.addingTimeInterval(-7 * 3600)), .ask)
        // A clock set back does not silence it.
        XCTAssertEqual(step(false, asked: now.addingTimeInterval(3600)), .ask)
    }
}

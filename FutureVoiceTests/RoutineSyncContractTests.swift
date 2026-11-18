import XCTest
@testable import FutureVoice

/// The routine crosses to Android in these exact bytes. Android's
/// `RoutineSyncTest` holds the same literal: a routine either side reads and
/// writes back must come out identical, or the two devices push it to each
/// other on every pass.
final class RoutineSyncContractTests: XCTestCase {

    static let plan = #"{"autoReview":false,"autoSayItAgain":false,"blocks":["# +
        #"{"anytime":true,"hour":8,"id":"6F1C2A9E-1B2C-4D3E-8F90-0A1B2C3D4E5F","kind":"talk","minute":0,"minutes":10,"remind":true,"weekdays":[1,2,3,4,5,6,7]},"# +
        #"{"hour":21,"id":"0B7E5D11-2C3D-4E5F-9A0B-1C2D3E4F5A6B","kind":"review","minute":30,"minutes":20,"remind":false,"weekdays":[2,4,6]}],"# +
        #""editedAt":"2026-11-18T03:04:05Z","exceptions":{"2026-11-20":[{"hour":9,"id":"1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D","kind":"shadow","minute":0,"minutes":2,"remind":true,"weekdays":[6]}]},"# +
        #""offWeekdays":[1,7],"restDays":["2026-11-25"],"reviewHour":21,"reviewMinute":0,"reviewMinutes":20,"# +
        #""shadowIsOwn":true,"streakSince":"2026-11-01T15:00:00Z","unitsVersion":2}"#

    func testARoutineGoesUpInTheBytesAndroidWrites() throws {
        let plan = try SyncCanonical.decode(StudyPlan.self, from: Data(Self.plan.utf8))
        let out = try XCTUnwrap(StudyPlanKind.payload(plan))
        XCTAssertEqual(String(decoding: out, as: UTF8.self), Self.plan)
    }

    func testSetsGoUpSortedWhateverOrderTheyHold() throws {
        var plan = try SyncCanonical.decode(StudyPlan.self, from: Data(Self.plan.utf8))
        // A Set's order is per process; rebuild them so it differs.
        plan.offWeekdays = Set([7, 1])
        plan.blocks = plan.blocks.map { var b = $0; b.weekdays = Set(b.weekdays.reversed()); return b }
        for _ in 0..<5 {
            XCTAssertEqual(String(decoding: try XCTUnwrap(StudyPlanKind.payload(plan)), as: UTF8.self), Self.plan)
        }
    }

    func testAnAndroidPayloadNormalizesToTheSameBytes() {
        XCTAssertEqual(StudyPlanKind().normalize(Data(Self.plan.utf8)), Data(Self.plan.utf8))
    }
}

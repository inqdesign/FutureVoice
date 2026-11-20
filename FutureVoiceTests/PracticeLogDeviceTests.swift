import XCTest
@testable import FutureVoice

/// Two devices practising on one day add up (2026-11-20). The per-day file
/// syncs by the bigger device's count; the per-device file sums.
final class PracticeLogDeviceTests: XCTestCase {
    private let filename = "test-practice-log-devices.json"
    private var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    override func tearDown() {
        for f in [filename, "devices-" + filename] { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        super.tearDown()
    }

    private func day(drill: Int, done: Int = 0, scenes: Int = 0) -> PracticeLog.Day {
        var d = PracticeLog.Day(); d.drillReps = drill; d.drillDone = done; d.sceneReps = scenes; return d
    }

    func testTwoDevicesOnOneDayAddUp() {
        // The Mac 27 cards, the phone 10; the per-day file kept the Mac's 27.
        let devices = ["2026-11-18|mac": day(drill: 27, done: 5), "2026-11-18|phone": day(drill: 10, done: 2),
                       "2026-11-19|mac": day(drill: 1)]
        let d = PracticeLog.combined(day(drill: 27, done: 5), devices: devices, day: "2026-11-18")
        XCTAssertEqual(d?.drillReps, 37)
        XCTAssertEqual(d?.drillDone, 7)
    }

    func testALegacyOnlyDayKeepsItsCount() {
        let d = PracticeLog.combined(day(drill: 12, scenes: 1), devices: [:], day: "2026-11-01")
        XCTAssertEqual(d?.drillReps, 12)
        XCTAssertEqual(d?.sceneReps, 1)
        XCTAssertNil(PracticeLog.combined(nil, devices: [:], day: "2026-11-01"))
    }

    func testARepWritesBothFiles() throws {
        let log = PracticeLog(filename: filename, device: "phone")
        let now = Date()
        log.record(.drill, finished: true, on: now)
        log.record(.scene, on: now)
        XCTAssertEqual(log.day(now)?.drillReps, 1)
        XCTAssertEqual(log.day(now)?.drillDone, 1)
        let data = try Data(contentsOf: dir.appendingPathComponent("devices-" + filename))
        let devices = try JSONDecoder().decode([String: PracticeLog.Day].self, from: data)
        XCTAssertEqual(devices.count, 1)
        XCTAssertTrue(devices.keys.first!.hasSuffix("|phone"))
        XCTAssertEqual(devices.values.first?.sceneReps, 1)
        XCTAssertEqual(log.activeDays().count, 1)
    }
}

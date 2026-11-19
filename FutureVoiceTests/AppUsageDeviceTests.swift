import XCTest
@testable import FutureVoice

/// Two devices used on one day add up (2026-11-19). The per-day map syncs by
/// the bigger device's number; the per-device map sums.
@MainActor
final class AppUsageDeviceTests: XCTestCase {
    private let legacy = "futurevoice.foregroundSecondsByDay"
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for k in [legacy, AppUsageLog.deviceKey] { saved[k] = UserDefaults.standard.object(forKey: k) }
    }

    override func tearDown() {
        for (k, v) in saved { UserDefaults.standard.set(v ?? nil, forKey: k) }
        super.tearDown()
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func testTwoDevicesOnOneDayAddUp() {
        // The Mac 30 min, the phone 20 min; the per-day map kept the Mac's 30.
        UserDefaults.standard.set(["2026-11-18": 1800], forKey: legacy)
        UserDefaults.standard.set(["2026-11-18|mac": 1800, "2026-11-18|phone": 1200, "2026-11-17|phone": 60],
                                  forKey: AppUsageLog.deviceKey)
        XCTAssertEqual(AppUsageLog.seconds(on: date("2026-11-18 12:00"), now: date("2026-11-19 09:00")), 3000)
    }

    func testADayFromBeforeTheDeviceMapKeepsItsNumber() {
        UserDefaults.standard.set(["2026-11-10": 900], forKey: legacy)
        UserDefaults.standard.set([String: Int](), forKey: AppUsageLog.deviceKey)
        XCTAssertEqual(AppUsageLog.seconds(on: date("2026-11-10 12:00"), now: date("2026-11-19 09:00")), 900)
    }

    func testAStintGoesIntoBothMaps() {
        UserDefaults.standard.set([String: Int](), forKey: legacy)
        UserDefaults.standard.set([String: Int](), forKey: AppUsageLog.deviceKey)
        AppUsageLog.becameActive(now: date("2026-11-19 09:00"))
        AppUsageLog.resigned(now: date("2026-11-19 09:10"))
        let devices = UserDefaults.standard.dictionary(forKey: AppUsageLog.deviceKey) as? [String: Int] ?? [:]
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(AppUsageLog.deviceSum(devices, day: "2026-11-19"), 600)
        XCTAssertEqual((UserDefaults.standard.dictionary(forKey: legacy) as? [String: Int])?["2026-11-19"], 600)
    }
}

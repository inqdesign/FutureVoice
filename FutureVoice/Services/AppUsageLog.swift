import Foundation
import UIKit

/// Seconds the app spent in the FOREGROUND, per local day — "how long did I
/// study today", for the day card. Written at the edges of a foreground stint
/// (`FutureVoiceApp` on `scenePhase`), never polled.
///
/// Deliberately naive: a call that keeps running in a pocket is metered by
/// `TalkMeter` but not counted here, so the card takes `max(usage, talk)`. It
/// is a study-time figure, not a billing one — the day's talk seconds stay
/// with `TalkTimeLog`, which reads the meter.
///
/// Two maps, because two devices used on one day must ADD UP (2026-11-19, a
/// learner on a Mac and an Android phone). The per-day map syncs by taking
/// the bigger device's number (`DefaultsCountKind`), so the smaller device's
/// minutes that day dropped out. The per-DEVICE map keys each count by
/// `day|device`: only one device ever writes a key, so the max merge is exact
/// and the day is the sum of its devices. The per-day map is still written
/// for builds that don't know the device map, and a day reads the larger of
/// the two, so a day from before this, or one with an older build in it, is
/// never lower than it was.
@MainActor
enum AppUsageLog {
    private static let key = "futurevoice.foregroundSecondsByDay"
    nonisolated static let deviceKey = "futurevoice.foregroundSecondsByDevice"
    private static let keepDays = 45
    private static var activeSince: Date?

    static func becameActive(now: Date = Date()) {
        activeSince = now
    }

    static func resigned(now: Date = Date()) {
        guard let since = activeSince else { return }
        activeSince = nil
        add(seconds: Int(now.timeIntervalSince(since)), now: now)
    }

    /// Stored seconds for a day — plus the open stint when the day is today,
    /// so a card made mid-session counts the minutes it is being made in.
    static func seconds(on day: Date, now: Date = Date()) -> Int {
        let stored = max(load()[dayKey(day)] ?? 0, deviceSum(load(deviceKey), day: dayKey(day)))
        guard dayKey(day) == dayKey(now) else { return stored }
        let open = activeSince.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        return stored + open
    }

    private static func add(seconds: Int, now: Date) {
        guard seconds > 0 else { return }
        var map = load()
        map[dayKey(now), default: 0] += seconds
        if map.count > keepDays {
            let cutoff = dayKey(now.addingTimeInterval(-Double(keepDays) * 86_400))
            map = map.filter { $0.key >= cutoff }
        }
        UserDefaults.standard.set(map, forKey: key)

        let cutoff = dayKey(now.addingTimeInterval(-Double(keepDays) * 86_400))
        var devices = load(deviceKey).filter { $0.key >= cutoff }
        devices[dayKey(now) + "|" + device, default: 0] += seconds
        UserDefaults.standard.set(devices, forKey: deviceKey)

        SyncEngine.noteChanged(.usageDay)
        SyncEngine.noteChanged(.usageDevice)
    }

    /// Every device's seconds for a day (`yyyy-MM-dd|<device>` keys).
    static func deviceSum(_ map: [String: Int], day: String) -> Int {
        map.reduce(0) { $1.key.hasPrefix(day + "|") ? $0 + $1.value : $0 }
    }

    /// This install's name in the device map. The vendor id: different on
    /// every device, never carried by a backup onto a new one.
    private static var device: String {
        if let id = UIDevice.current.identifierForVendor?.uuidString { return id.lowercased() }
        let k = "futurevoice.usageDeviceId"
        if let id = UserDefaults.standard.string(forKey: k) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: k)
        return id
    }

    private static func load(_ key: String = key) -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    /// LOCAL day, same shape as `TalkTimeLog`'s keys.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

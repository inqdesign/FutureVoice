import Foundation

/// The sync's own settings. Per APP ACCOUNT where it matters: whether sync
/// is on is a decision about one account's data, and a shared iPad can hold
/// two.
enum SyncStore {
    private static var defaults: UserDefaults { .standard }

    static func isEnabled(userId: String) -> Bool {
        defaults.bool(forKey: "futurevoice.sync.enabled.\(userId)")
    }

    static func setEnabled(_ on: Bool, userId: String) {
        defaults.set(on, forKey: "futurevoice.sync.enabled.\(userId)")
    }

    /// Whether the "continue from your other device?" offer has been made
    /// on this install for this account — asked once, whatever the answer.
    static func wasOffered(userId: String) -> Bool {
        defaults.bool(forKey: "futurevoice.sync.offered.\(userId)")
    }

    static func setOffered(userId: String) {
        defaults.set(true, forKey: "futurevoice.sync.offered.\(userId)")
    }

    /// Audio is the gigabyte; items are kilobytes. Off by default so a month
    /// of talks never goes out over cellular unasked.
    static var cellularForAudio: Bool {
        get { defaults.bool(forKey: "futurevoice.sync.cellularAudio") }
        set { defaults.set(newValue, forKey: "futurevoice.sync.cellularAudio") }
    }
}

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Notification permission, as a thing the learner can SEE and fix.
///
/// A schedule the app can't ring is the worst failure mode here: the learner
/// drops a card on "10 min", nothing ever comes back, and the feature reads as
/// broken rather than unpermitted. `DrillReminder` stays silent by design when
/// permission is missing, so something has to say so out loud — that's what
/// this feeds (Practice → daily goals).
@MainActor
enum ReviewNotifications {

    enum Status {
        case notAsked
        case allowed
        case denied

        var canRing: Bool { self == .allowed }
    }

    static func status() async -> Status {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined:                     return .notAsked
        case .denied:                            return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default:                        return .denied
        }
    }

    /// Ask, then immediately arm whatever is already scheduled — granting
    /// permission with a pile of pending snoozes should not need a second
    /// visit to a deck.
    @discardableResult
    static func request() async -> Status {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let now = await status()
        if now.canRing { await DrillReminder.reschedule() }
        return now
    }

    /// Once denied, only Settings can undo it.
    static func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

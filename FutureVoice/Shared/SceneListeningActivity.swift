import ActivityKit
import AppIntents
import Foundation

/// The situation playing right now, as the Dynamic Island and the lock
/// screen show it (2026-10-18, founder: "play it live in the island").
///
/// Compiled into BOTH the app and the widget extension — keep it free of
/// Models.swift and the stores. Everything in `ContentState` is resolved
/// app-side (names in the app language, the line as written), because the
/// extension can only draw.
struct SceneListeningAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Who says the current line.
        var speaker: String
        /// The line, cut to fit a Live Activity's payload.
        var line: String
        /// The fluent self's line (drawn in the accent) or the other person's.
        var isFluentSelf: Bool
        var sceneTitle: String
        /// 1-based place in the list, and its length.
        var position: Int
        var total: Int
        var isPlaying: Bool
    }

    /// The list being played ("My situations").
    var title: String
}

/// The two buttons on the Live Activity. A `LiveActivityIntent` runs in the
/// APP's process, so `perform` only has to tell the player, which is listening
/// for this notification (the extension never runs it).
enum ScenePlaybackCommand: String {
    case toggle, next

    static let notification = Notification.Name("futurevoice.scenePlaybackCommand")
}

struct ToggleScenePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or pause"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: ScenePlaybackCommand.notification,
                                        object: ScenePlaybackCommand.toggle.rawValue)
        return .result()
    }
}

struct NextScenePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next line"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: ScenePlaybackCommand.notification,
                                        object: ScenePlaybackCommand.next.rawValue)
        return .result()
    }
}

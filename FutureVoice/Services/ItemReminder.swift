import Foundation
import UserNotifications

/// One notification per thing the learner explicitly asked to see again.
///
/// The aggregate reminder (`DrillReminder`) answers "something is waiting" —
/// right for the automatic Leitner ladder, wrong for a deliberate drop on
/// "1 min". When you put a specific card in a folder you made a promise about
/// THAT card: the notification has to name it, and tapping it has to open it.
/// Anything less and the folder is just a delay, not a callback.
///
/// Deliberate scope: only MANUAL snoozes get one. Ladder returns stay with the
/// aggregate reminder, or a big backlog would mean dozens of notifications.
@MainActor
enum ItemReminder {

    static let categoryId = "futurevoice.review-item"

    /// What the notification points at. The raw values ride in `userInfo` and
    /// come back on tap, so they must stay stable.
    enum Target: Equatable {
        case word(String)
        case expression(String)
        case sentence(UUID)      // a DrillCard

        var kind: String {
            switch self {
            case .word:       return "word"
            case .expression: return "expression"
            case .sentence:   return "sentence"
            }
        }

        var value: String {
            switch self {
            case .word(let w):       return w
            case .expression(let p): return p
            case .sentence(let id):  return id.uuidString
            }
        }

        /// One pending request per item — re-snoozing replaces rather than
        /// stacks (iOS keys pending requests by identifier).
        var requestId: String {
            "futurevoice.item.\(kind).\(value.lowercased())"
        }

        init?(kind: String, value: String) {
            switch kind {
            case "word":       self = .word(value)
            case "expression": self = .expression(value)
            case "sentence":
                guard let id = UUID(uuidString: value) else { return nil }
                self = .sentence(id)
            default: return nil
            }
        }
    }

    /// Arm the callback. `text` is what the learner will read on the lock
    /// screen — the word, phrase or line itself, because "1 item is waiting"
    /// tells them nothing about whether it's worth opening.
    ///
    /// Silent when permission is missing; `ReviewNotifications` is what makes
    /// that state visible.
    static func schedule(_ target: Target, text: String, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [target.requestId])

        // Clamp into waking hours the same way the aggregate reminder does —
        // a "tomorrow" drop made at 2am shouldn't ring at 2am.
        guard let fireDate = DrillReminder.fireDate(now: Date(), nextDue: date, hasDueNow: false),
              fireDate > Date() else { return }

        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default:
            #if DEBUG
            NSLog("ITEMNOTIF skipped (no permission): %@", text)
            #endif
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ready to review")
        content.body = trimmed(text)
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["kind": target.kind, "value": target.value]
        // Grouped per item so a second one doesn't bury the first.
        content.threadIdentifier = categoryId

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: target.requestId,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
        #if DEBUG
        NSLog("ITEMNOTIF scheduled %@ at %@ — %@",
              target.kind, fireDate.description, content.body)
        #endif
    }

    /// The promise is settled (mastered, known, or reviewed early) — take the
    /// callback back. A notification for a card that no longer needs it is the
    /// fastest way to teach someone to ignore notifications.
    static func cancel(_ target: Target) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [target.requestId])
    }

    /// Lock-screen bodies get truncated by the OS anyway; keep whole words.
    private static func trimmed(_ text: String, max: Int = 90) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > max else { return clean }
        let cut = clean.prefix(max)
        let lastSpace = cut.lastIndex(of: " ") ?? cut.endIndex
        return clean[clean.startIndex..<lastSpace] + "…"
    }
}

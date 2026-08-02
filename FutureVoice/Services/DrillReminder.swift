import Foundation
import UserNotifications

/// One local notification for the drill queue — SRS only works if something
/// pulls the user back when cards come due, and nothing did until now.
///
/// Policy (deliberately quiet):
///   • At most ONE pending reminder at any time, always rescheduled from the
///     current queue state — never a stack of stale notifications.
///   • Fires when the next card becomes due, clamped into 09:00–21:00 local
///     time so a 3-day Leitner interval landing at 2am waits for morning.
///   • If cards are ALREADY due while the user is in the app, remind
///     tomorrow morning instead — nudging about a queue they can see is noise.
///   • Permission is requested only from a foreground moment right after new
///     cards were created (post-session), never from the background path.
@MainActor
enum DrillReminder {

    private static let requestId = "futurevoice.drill-due"
    private static let dayStartHour = 9
    private static let dayEndHour = 21

    /// Recompute and replace the pending reminder from current queue state.
    /// - Parameter allowPermissionPrompt: pass true only from a foreground,
    ///   contextual moment (e.g. right after a session created cards).
    static func reschedule(allowPermissionPrompt: Bool = false, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])

        let cards = DrillStore.shared.load()
        guard !cards.isEmpty else { return }

        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            guard allowPermissionPrompt else { return }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
        case .denied:
            return
        default:
            break
        }

        let hasDueNow = cards.contains { $0.nextReviewAt <= now }
        let nextFutureDue = cards.map(\.nextReviewAt).filter { $0 > now }.min()
        guard let fireDate = fireDate(now: now, nextDue: nextFutureDue, hasDueNow: hasDueNow),
              fireDate > now else { return }

        // How many cards will be waiting at fire time.
        let countAtFire = cards.filter { $0.nextReviewAt <= fireDate }.count
        guard countAtFire > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Drills are due"
        content.body = countAtFire == 1
            ? "1 phrase is ready to review."
            : "\(countAtFire) phrases are ready to review."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Picks when to fire, clamped into the waking-hours window.
    static func fireDate(
        now: Date,
        nextDue: Date?,
        hasDueNow: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        let candidate: Date
        if hasDueNow {
            // User can see today's queue right now — remind tomorrow morning.
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  let morning = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: tomorrow)
            else { return nil }
            candidate = morning
        } else if let nextDue {
            candidate = nextDue
        } else {
            return nil
        }

        // A due time inside the next 12 hours can only have come from the
        // learner picking one in the bin tray — every ladder interval is a
        // day or longer, and box 0 is "due now" (handled above). They asked
        // for it, at an hour they were awake to ask: fire exactly then rather
        // than parking a 10-minute snooze until 9am.
        if candidate.timeIntervalSince(now) < 12 * 60 * 60 { return candidate }

        let hour = calendar.component(.hour, from: candidate)
        if hour < dayStartHour {
            return calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: candidate)
        }
        if hour >= dayEndHour {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            return calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: nextDay)
        }
        return candidate
    }
}

import Foundation
import UserNotifications

/// A local reminder at each hand-placed timetable block (words, expressions,
/// shadowing) for the next week. Talk blocks ring as the daily call and the
/// review slot goes through `DrillReminder`, so neither is scheduled here.
///
/// Rebuilt from the plan every time — on a plan edit and on every foreground —
/// so a moved or deleted block can never leave a stale reminder behind. It
/// never asks for permission itself: the block editor asks, at the moment the
/// learner turns a reminder on.
@MainActor
enum PlanReminder {
    private static let prefix = "futurevoice.plan."
    /// Tapping lands on the talk picker, not just the app.
    static let sayItAgainCategoryId = "futurevoice.plan.say-again"
    static let horizonDays = 7

    static func reschedule(now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }

        let plan = StudyPlanStore.shared.plan
        let today = calendar.startOfDay(for: now)
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for occ in plan.occurrences(on: day, calendar: calendar)
            where occ.remind && occ.start > now && occ.blockId != nil
                && [.sayItAgain, .words, .expressions, .shadow].contains(occ.kind) {
                let content = UNMutableNotificationContent()
                content.title = title(for: occ.kind)
                content.body = occ.kind == .sayItAgain
                    ? explain("Pick a recent talk and say it again.")
                    : explain("\(occ.kind.titled(occ.amount)), as planned.")
                content.sound = .default
                switch occ.kind {
                case .sayItAgain: content.categoryIdentifier = sayItAgainCategoryId
                case .words, .expressions: content.categoryIdentifier = DrillReminder.categoryId
                default: break
                }
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occ.start)
                let id = prefix + occ.id
                try? await center.add(UNNotificationRequest(
                    identifier: id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }

    /// Ask once, from a foreground moment the learner chose (saving a block
    /// with its reminder on).
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private static func title(for kind: StudyPlan.Kind) -> String {
        switch kind {
        case .words: return explain("Time for your words")
        case .expressions: return explain("Time for your expressions")
        case .shadow: return explain("Time for shadowing")
        case .sayItAgain: return explain("Time to say it again")
        default: return explain("Time to practice")
        }
    }
}

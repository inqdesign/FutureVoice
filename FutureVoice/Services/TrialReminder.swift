import Foundation
import UserNotifications

/// The "your trial ends in two days" notice the paywall promises, and the one
/// place that promise is kept or knowingly withdrawn.
///
/// It used to be three lines inside `PaywallView` that called `add(request)`
/// and hoped. Three things were wrong with that, all silent:
///
///   * no authorization was ever asked for, so on a phone that had never
///     turned on the daily call the notice was accepted by iOS and never
///     delivered — a promise made on the purchase screen, broken invisibly;
///   * the title and body were bare Swift strings, which never see the
///     learner's locale, so a Korean subscriber got English;
///   * nothing cancelled it, so someone who cancelled on day two still heard
///     "your trial converts in 2 days" on day five.
enum TrialReminder {
    private static let id = "futurevoice.trial-ending"

    /// Days before the trial ends that the notice fires. Two is enough to
    /// cancel without hurrying and late enough to still be about this week.
    private static let leadDays = 2

    /// Ask for permission, then schedule. Returns whether the notice will
    /// actually arrive, so the caller can stop claiming it if it won't.
    ///
    /// Permission is requested HERE rather than at launch: the moment someone
    /// starts a trial is the one moment "we'll remind you before it converts"
    /// explains itself. Asked cold on day one it is just another prompt.
    @discardableResult
    static func schedule(trialDays: Int) async -> Bool {
        guard trialDays > leadDays else { return false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var granted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = explain("Your free trial ends soon")
        content.body = explain("Your trial becomes a paid subscription in \(leadDays) days. You can cancel any time in the App Store.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval((trialDays - leadDays) * 24 * 60 * 60),
                repeats: false)
        )
        try? await center.add(request)
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Drop the notice once the trial is over — converted, cancelled, or
    /// expired. Runs on foreground off the billing snapshot the app already
    /// keeps, so it costs no extra round trip on the common path.
    ///
    /// Cancelling matters more than scheduling did: a notice that says the
    /// trial converts in two days, sent to someone who cancelled it, is worse
    /// than no notice at all.
    static func reconcile() async {
        guard let account = await BillingGate.shared.snapshot() else { return }
        // Only on a subscription row that EXISTS and says it is not a trial.
        // `!isTrialing` alone would also be true in the gap between paying and
        // `apple-webhook` writing the row — seconds usually, longer if Apple
        // retries — and cancelling there would silently drop the notice for
        // the very purchase that just scheduled it, with nothing to
        // reschedule it later. "inactive" is the value `AccountStatus.empty`
        // carries when no row was found, so it means "don't know yet", never
        // "not a trial".
        guard account.subscriptionStatus != "inactive" else { return }
        if !account.isTrialing { cancel() }
    }
}

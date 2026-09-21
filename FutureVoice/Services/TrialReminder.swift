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
///
/// **Timed from the store's trial end, not only from our paywall**
/// (2026-09-18). Scheduling lived solely on `PaywallView`'s purchase, so a
/// trial started any other way — an offer code redeemed from the launch mail,
/// the App Store's own page, a new phone, a reinstall — never had a notice at
/// all, and the first launch-week trials converted with nobody able to say
/// whether they'd been warned. `reconcile` now (re)schedules on every
/// foreground from `AccountStatus.trialEndsAt`, the date every webhook writes.
/// It never ASKS for permission there: a cold prompt on launch is just another
/// prompt; the purchase is the moment it explains itself.
///
/// **Every outcome is logged** (`trial_reminder`, once per trial per outcome).
/// It is a local notification — nothing server-side can see whether it was
/// scheduled — so without this "did the reminders go out?" has no answer.
enum TrialReminder {
    private static let id = "futurevoice.trial-ending"
    /// "outcome|trialEnd" of the last logged row, so a foreground doesn't
    /// write the same event every time the app opens.
    private static let loggedKey = "futurevoice.trialReminder.logged"

    /// Days before the trial ends that the notice fires. Two is enough to
    /// cancel without hurrying and late enough to still be about this week.
    private static let leadDays = 2

    /// Ask for permission, then schedule. Returns whether the notice will
    /// actually arrive, so the caller can stop claiming it if it won't.
    ///
    /// Permission is requested HERE rather than at launch: the moment someone
    /// starts a trial is the one moment "we'll remind you before it converts"
    /// explains itself. Asked cold on day one it is just another prompt.
    ///
    /// The server's row usually lands seconds after this; `reconcile` then
    /// re-times the same request to the store's exact trial end.
    @discardableResult
    static func schedule(trialDays: Int) async -> Bool {
        guard trialDays > leadDays else { return false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var granted = isAllowed(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        let fireAt = Date().addingTimeInterval(TimeInterval((trialDays - leadDays) * 24 * 60 * 60))
        guard granted else {
            log("denied", path: "purchase", fireAt: fireAt, trialEnd: nil)
            return false
        }
        await add(fireAt: fireAt)
        log("scheduled", path: "purchase", fireAt: fireAt, trialEnd: nil)
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Bring the notice in line with the subscription as the server knows it,
    /// on every foreground: schedule it for a trial that has none (or re-time
    /// it to the store's date), and drop it once the trial is over or will not
    /// convert.
    ///
    /// Cancelling matters as much as scheduling: a notice that says the trial
    /// converts in two days, sent to someone who cancelled it, is worse than
    /// no notice at all.
    static func reconcile() async {
        guard let account = await BillingGate.shared.snapshot() else { return }
        // Only on a subscription row that EXISTS. "inactive" is the value
        // `AccountStatus.empty` carries when no row was found — in the gap
        // between paying and `apple-webhook` writing the row, seconds usually,
        // longer if Apple retries — so it means "don't know yet", never "not
        // a trial". Cancelling there would drop the notice for the very
        // purchase that just scheduled it.
        guard account.subscriptionStatus != "inactive" else { return }

        let center = UNUserNotificationCenter.current()
        // Converted, expired, or auto-renew turned off: nothing will be
        // charged, so "becomes a paid subscription" would be untrue.
        guard account.isTrialing, !account.cancelAtPeriodEnd else {
            let pending = await center.pendingNotificationRequests()
            if pending.contains(where: { $0.identifier == id }) {
                cancel()
                log(account.isTrialing ? "cancelled_auto_renew_off" : "cancelled_trial_over",
                    path: "reconcile", fireAt: nil, trialEnd: account.trialEndsAt)
            }
            return
        }
        guard let trialEnd = account.trialEndsAt else {
            // A trial row without a date (an older webhook write). Whatever
            // the purchase scheduled stays as it is.
            log("no_trial_end", path: "reconcile", fireAt: nil, trialEnd: nil)
            return
        }
        let fireAt = fireDate(before: trialEnd)
        guard fireAt > Date().addingTimeInterval(60) else {
            // Already inside the last two days — too late for this notice to
            // say what it says. The Usage page names the date.
            log("too_late", path: "reconcile", fireAt: fireAt, trialEnd: trialEnd)
            return
        }
        let settings = await center.notificationSettings()
        guard isAllowed(settings.authorizationStatus) else {
            log(settings.authorizationStatus == .notDetermined ? "not_asked" : "denied",
                path: "reconcile", fireAt: fireAt, trialEnd: trialEnd)
            return
        }
        // Same identifier, so this REPLACES whatever the purchase scheduled —
        // re-adding on every foreground is idempotent.
        await add(fireAt: fireAt)
        log("scheduled", path: "reconcile", fireAt: fireAt, trialEnd: trialEnd)
    }

    /// `leadDays` before the trial ends — moved EARLIER, never later, when
    /// that lands at night: a trial that started at 2am would otherwise be
    /// announced at 2am. Earlier only ever gives more time to decide.
    static func fireDate(before trialEnd: Date, calendar: Calendar = .current) -> Date {
        let raw = trialEnd.addingTimeInterval(-TimeInterval(leadDays * 24 * 60 * 60))
        let hour = calendar.component(.hour, from: raw)
        if (9..<21).contains(hour) { return raw }
        // 21:00–23:59 → 20:00 the same evening; 00:00–08:59 → 20:00 the
        // evening before.
        let day = hour >= 21 ? raw : calendar.date(byAdding: .day, value: -1, to: raw) ?? raw
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? raw
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private static func add(fireAt: Date) async {
        let content = UNMutableNotificationContent()
        content.title = explain("Your free trial ends soon")
        content.body = explain("Your trial becomes a paid subscription in \(leadDays) days. You can cancel any time in the App Store.")
        content.sound = .default

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireAt)
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func log(_ outcome: String, path: String, fireAt: Date?, trialEnd: Date?) {
        let iso = ISO8601DateFormatter()
        let endKey = trialEnd.map(iso.string(from:)) ?? "-"
        let key = "\(outcome)|\(endKey)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: loggedKey) != key else { return }
        defaults.set(key, forKey: loggedKey)
        var props = ["outcome": outcome, "path": path]
        if let fireAt { props["fire_at"] = iso.string(from: fireAt) }
        if let trialEnd { props["trial_ends_at"] = iso.string(from: trialEnd) }
        Telemetry.log("trial_reminder", props)
    }
}

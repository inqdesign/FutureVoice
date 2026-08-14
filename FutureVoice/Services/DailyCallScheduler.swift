import Foundation
import UserNotifications

/// Schedules the daily call and handles what the learner does with it.
///
/// Both surfaces (`DailyCallAlarm` first, notification as fallback) offer the
/// same two choices, and the second one is the reason this works at all:
///
///   • **Answer** — opens the app and starts the talk.
///   • **Can't talk now** — declines. NOT a failure. 전화영어's forfeited
///     lesson is what makes people cancel; here the caller simply rings back
///     in an hour, the way a person would, up to `maxCallbacks`. Then they
///     leave it for the day — never a scold, never a broken counter.
///
/// Every call settles into a `DailyCallOutcome` and goes into the store's
/// history, which is what the NEXT script is written from. That loop is where
/// the "someone is calling me" feeling actually lives: an alarm knows nothing
/// about you, a caller remembers that you couldn't talk yesterday.
///
/// Generation happens at the END of a session (foreground, freshest context),
/// never here. By the time this schedules anything, the script and its audio
/// are already on disk, so the call fires offline and can't fail at 8am.
@MainActor
enum DailyCallScheduler {

    static let categoryId = "FUTUREVOICE_DAILY_CALL"
    static let answerActionId = "FUTUREVOICE_CALL_ANSWER"
    /// Suffixed with the delay in minutes — see `callbackOptions`.
    static let declineActionPrefix = "FUTUREVOICE_CALL_DECLINE_"

    private static let requestId = "futurevoice.daily-call"

    /// "Call me back in…", in minutes.
    ///
    /// The NOTIFICATION can offer all of these, because a
    /// `UNNotificationCategory` takes an array of actions. The ALARM cannot:
    /// `AlarmPresentation.Alert` has room for exactly one button we control
    /// (the other is system-drawn), so on that surface the single Decline
    /// button uses `defaultCallbackMinutes` — which is why that setting exists
    /// in Me rather than being a constant.
    static let callbackOptions = [30, 60, 180]

    /// What the learner chose in Me, or an hour if they never looked.
    static var defaultCallbackMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "futurevoice.dailyCall.callbackMinutes")
            return stored > 0 ? stored : 60
        }
        set { UserDefaults.standard.set(newValue, forKey: "futurevoice.dailyCall.callbackMinutes") }
    }
    /// After three tries the caller gives up for the day. A fourth ring is
    /// nagging, and nagging is what people turn notifications off over.
    static let maxCallbacks = 3
    /// How long after a pickup the passive re-arm keeps its hands off, so the
    /// session that pickup started gets to be the context for tomorrow's call
    /// instead of being written around. See `refresh`.
    static let answerSettleWindow: TimeInterval = 3 * 60 * 60
    /// Grace before an untouched call counts as missed — long enough that a
    /// phone still ringing on the table isn't written off while the learner
    /// walks over to it.
    static let rangOutGrace: TimeInterval = 5 * 60

    // MARK: - Category

    /// Install the two actions. Must run on EVERY launch and before any of
    /// these notifications is delivered — a category iOS doesn't know about
    /// renders as a plain notification with no buttons.
    static func registerCategory() {
        let answer = UNNotificationAction(
            identifier: answerActionId,
            title: explain("Answer"),
            options: [.foreground])
        // One action per callback delay. The notification is the one surface
        // that can show a choice — take it.
        let declines = callbackOptions.map { minutes in
            UNNotificationAction(
                identifier: "\(declineActionPrefix)\(minutes)",
                title: callbackLabel(minutes),
                options: [])
        }
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [answer] + declines,
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// "Call back in 30 min" / "in 1 hour" / "in 3 hours". Phrased as the
    /// CALLER's next move, not as a snooze the learner is setting — the whole
    /// framing is that somebody tries again, not that a timer slips.
    static func callbackLabel(_ minutes: Int) -> String {
        if minutes < 60 { return explain("Call back in \(minutes) min") }
        let hours = minutes / 60
        return hours == 1 ? explain("Call back in 1 hour")
                          : explain("Call back in \(hours) hours")
    }

    // MARK: - Permission

    /// Ask for whatever this system can ring with. Called ONLY from the Me tab
    /// toggle — a call the learner just switched on is the one moment the
    /// prompts explain themselves.
    ///
    /// Alarms first, because that's the surface we actually want. Notifications
    /// are still requested afterwards: they're the fallback if alarms are
    /// refused, and one of the two granted is enough to turn the feature on.
    static func requestPermission() async -> Bool {
        let alarmGranted = await DailyCallAlarm.requestAuthorizationIfSupported()

        let center = UNUserNotificationCenter.current()
        let notificationsGranted: Bool
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            notificationsGranted =
                (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            notificationsGranted = false
        default:
            notificationsGranted = true
        }

        return alarmGranted || notificationsGranted
    }

    // MARK: - Scheduling

    /// Bring the pending call in line with current state.
    ///
    /// Regenerates the script only when there isn't a usable one — a plan that
    /// still matches the learner's language and clone, hasn't been answered,
    /// and hasn't fired yet is reused as-is. Each regeneration costs a Gemini
    /// call and an ElevenLabs synthesis, so "already have one" must be the
    /// common path.
    ///
    /// - Parameter force: rewrite even when a usable plan exists — the session
    ///   that just ended is newer context than whatever the plan was built on.
    static func refresh(context: VoicemailEngine.Context,
                        voiceId: String?,
                        callerName: String,
                        force: Bool = false) async {
        let store = DailyCallStore.shared
        guard store.isEnabled else {
            await cancel()
            return
        }
        // No clone yet (onboarding not finished) — a call in a stranger's
        // voice is worse than no call.
        guard let voiceId else {
            await cancel()
            return
        }
        guard await isAuthorized() else { return }

        let now = Date()
        // A call whose time came and went with nobody touching it. Nothing was
        // running to notice at the time, so it's settled here, on the next
        // launch — and it settles as MISSED rather than vanishing, which is
        // the difference between a person having tried to reach you and an
        // alarm you slept through.
        settleIfRangOut(now: now)

        let existing = store.load()
        let reusable = !force
            && existing?.isSettled == false
            && existing?.matches(language: context.targetLanguage, voiceId: voiceId) == true
            && (existing?.scheduledFor ?? .distantPast) > now

        if let plan = existing, reusable {
            await schedule(plan, callerName: callerName)
            return
        }

        // Just picked up, and this is only the passive re-arm (a foreground,
        // not a finished session). Leave it alone: the talk they're in RIGHT
        // NOW is the context tomorrow's call should be written from, and it
        // hasn't ended yet. Rewriting here would pay for a script off stale
        // context and then pay again when the session ends.
        if !force, existing?.outcome == .answered,
           let endedAt = existing?.endedAt,
           now.timeIntervalSince(endedAt) < answerSettleWindow {
            return
        }

        guard let fireDate = nextFireDate(after: now) else { return }

        // Hand the caller their memory of this learner before they write.
        var context = context
        context.lastOutcome = store.history().first?.outcome
        context.lastCallbacks = store.history().first?.callbacks ?? 0
        context.consecutiveUnanswered = store.consecutiveUnanswered()

        guard let script = try? await VoicemailEngine.writeScript(context),
              !script.isEmpty else { return }

        // The voicemail is synthesized NOW, not on answer: it lands in the
        // phrase cache so picking up starts the talk on audio that's already
        // on disk. It is NOT what rings — see `DailyCallStore.ringtoneFilename`.
        if let wav = await VoicemailEngine.synthesizeVoicemail(script: script, voiceId: voiceId) {
            PhraseAudioStore.shared.save(wav, text: script, voiceId: voiceId)
        }

        let plan = DailyCallPlan(
            id: UUID(),
            script: script,
            language: context.targetLanguage,
            voiceId: voiceId,
            scheduledFor: fireDate,
            callbackCount: 0,
            createdAt: now,
            outcome: nil,
            endedAt: nil,
            heardAt: nil
        )
        store.save(plan)
        await schedule(plan, callerName: callerName)
        Analytics.capture("daily_call_scheduled", [
            "hour": DailyCallStore.shared.hour,
            "consecutive_unanswered": context.consecutiveUnanswered
        ])
    }

    /// They sent it away. The caller tries again later, the way a person would
    /// — same script, same audio, no new spend — until the cap.
    ///
    /// This is not a snooze button on an alarm. Declining is a decision, and
    /// the point is that it costs nothing: no streak breaks, no scold, and the
    /// only consequence is that somebody rings back.
    ///
    /// - Parameter minutes: which "call me back in…" they picked. nil means
    ///   the surface couldn't offer a choice (the alarm's single button), so
    ///   their setting decides.
    static func decline(after minutes: Int? = nil) async {
        let store = DailyCallStore.shared
        guard var plan = store.load(), !plan.isSettled else { return }
        let delay = minutes ?? defaultCallbackMinutes
        Analytics.capture("daily_call_declined", [
            "callback": plan.callbackCount + 1,
            "minutes": delay,
            "chosen": minutes != nil
        ])
        plan.callbackCount += 1

        guard plan.callbackCount <= maxCallbacks else {
            // Out of callbacks. The caller gives up for today — quietly, and
            // the unheard message stays behind for whenever they look.
            settle(plan, as: .declined)
            await cancelPendingRequest()
            return
        }
        plan.scheduledFor = Date().addingTimeInterval(TimeInterval(delay) * 60)
        store.save(plan)
        await schedule(plan, callerName: nil)
    }

    /// They picked up. Spend the plan so it can't ring twice, and mark the
    /// message heard — they're about to hear it as the talk's opening line.
    static func markAnswered() {
        guard let plan = DailyCallStore.shared.load(), !plan.isSettled else { return }
        Analytics.capture("daily_call_answered", ["callbacks": plan.callbackCount])
        settle(plan, as: .answered, heard: true)
        // Picking up clears any older message still waiting: they're talking
        // to the same person right now, so "you missed me" is no longer true.
        DailyCallStore.shared.clearUnheard()
        Task { await cancelPendingRequest() }
    }

    /// "Not today." The caller stops trying and leaves the message behind —
    /// the same end state as running out of callbacks, reached deliberately.
    static func declineForToday() async {
        guard let plan = DailyCallStore.shared.load(), !plan.isSettled else { return }
        Analytics.capture("daily_call_declined_for_today", ["callbacks": plan.callbackCount])
        settle(plan, as: .declined)
        await cancelPendingRequest()
    }

    /// The learner played the message back from the missed-call row. It stops
    /// being "waiting for you" from here.
    /// Clears the trace and NOTHING else. It must not touch the plan on disk:
    /// by the time the learner taps that row, `refresh` has already replaced
    /// the missed call with the NEXT one, so stamping `heardAt` there would
    /// mark a call that hasn't even rung as already listened to — and then
    /// `settle` would refuse to keep its message when it goes unanswered.
    static func markVoicemailHeard() {
        DailyCallStore.shared.clearUnheard()
    }

    /// Close a call out and hand its result to the caller's memory.
    private static func settle(_ plan: DailyCallPlan,
                               as outcome: DailyCallOutcome,
                               heard: Bool = false) {
        var plan = plan
        plan.outcome = outcome
        plan.endedAt = Date()
        if heard { plan.heardAt = Date() }
        DailyCallStore.shared.save(plan)
        DailyCallStore.shared.record(DailyCallRecord(
            date: Date(), outcome: outcome, callbacks: plan.callbackCount))
        // The trace outlives the plan. `refresh` writes the NEXT call into the
        // same single plan file moments after settling this one, so a message
        // kept only on the plan would be erased before the learner ever saw
        // it — usually inside the very same `refresh`.
        if plan.hasUnheardVoicemail {
            DailyCallStore.shared.keepUnheard(plan)
        }
    }

    /// Settle a call that rang out unattended. Given a grace period so a plan
    /// that fired seconds ago — and is still on screen — isn't written off as
    /// missed while the learner is reaching for the phone.
    private static func settleIfRangOut(now: Date) {
        guard let plan = DailyCallStore.shared.load(), !plan.isSettled,
              now.timeIntervalSince(plan.scheduledFor) > rangOutGrace,
              // A plan owns EVERY remaining slot, not just `scheduledFor` (see
              // `fireDates`) — so one slot passing is not the day ending. At
              // 08:05 with calls at 13:00 and 20:00, those alarms are still
              // armed and carrying THIS plan; settling it here would make
              // Answer and Decline no-ops when they ring, because both intents
              // guard on `!plan.isSettled`.
              !hasSlotRemainingToday(after: now) else { return }
        Analytics.capture("daily_call_missed", ["callbacks": plan.callbackCount])
        settle(plan, as: .missed)
    }

    /// Whether any call is still due to ring TODAY.
    ///
    /// `fireDates` rolls to tomorrow's first call once today's are spent, so
    /// "the next one is not today" is exactly "nothing left is armed today".
    static func hasSlotRemainingToday(after now: Date,
                                      calendar: Calendar = .current) -> Bool {
        guard let next = fireDates(after: now, calendar: calendar).first else { return false }
        return calendar.isDate(next, inSameDayAs: now)
    }

    /// Turned off, or no longer possible. Drops the pending ring and the plan.
    static func cancel() async {
        await cancelPendingRequest()
        DailyCallStore.shared.clearUnheard()
        DailyCallStore.shared.clear()
    }

    // MARK: - Internals

    /// Either surface being granted is enough — `schedule` picks whichever can
    /// actually fire. Gating on notifications alone would silently kill the
    /// feature for a learner who allowed alarms and refused banners, which is a
    /// perfectly reasonable pair of answers to give.
    private static func isAuthorized() async -> Bool {
        if await DailyCallAlarm.requestAuthorizationIfSupported() { return true }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Clears BOTH surfaces. A plan can have been scheduled as an alarm on one
    /// launch and as a notification on the next (permissions change, OS
    /// upgrade) — dropping only the one we're about to use would leave the
    /// other still armed and the learner called twice.
    private static func cancelPendingRequest() async {
        // One id per slot (see `schedule`), plus the legacy single id so an
        // install updating mid-day can't leave an orphaned ring behind.
        let ids = [requestId] + (0..<DailyCallStore.maxTimes).map { "\(requestId).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        DailyCallAlarm.cancelIfSupported()
    }

    /// The learner's chosen time of day, today if it hasn't passed yet,
    /// otherwise tomorrow.
    static func nextFireDate(after now: Date,
                             calendar: Calendar = .current,
                             hour: Int? = nil,
                             minute: Int? = nil) -> Date? {
        if let hour {
            return fireDate(hour: hour, minute: minute ?? 0, after: now, calendar: calendar)
        }
        return fireDates(after: now, calendar: calendar).first
    }

    /// Every upcoming call, soonest first: the rest of today's times, then
    /// tomorrow's first — so there is always at least one.
    ///
    /// This is what makes more than one call a day actually work. A plan is
    /// written while the app is in the FOREGROUND (session end), but a call
    /// the learner sleeps through happens with the app closed and nothing
    /// running to write the next one. So every remaining slot is armed up
    /// front, all carrying the same still-unheard message — which is also how
    /// a person behaves: they try again later with the same thing to say.
    /// Answering cancels the rest, and the session that follows writes the
    /// next call fresh.
    static func fireDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        let times = DailyCallStore.shared.times
        let todays = times.compactMap {
            fireDateToday(hour: $0.hour, minute: $0.minute, on: now, calendar: calendar)
        }
        let remaining = todays.filter { $0 > now }.sorted()
        if !remaining.isEmpty { return remaining }
        // Past the last one: tomorrow's first.
        guard let first = times.first,
              let today = fireDateToday(hour: first.hour, minute: first.minute,
                                        on: now, calendar: calendar),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        else { return [] }
        return [tomorrow]
    }

    private static func fireDateToday(hour: Int, minute: Int,
                                      on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func fireDate(hour: Int, minute: Int,
                                 after now: Date, calendar: Calendar) -> Date? {
        guard let today = fireDateToday(hour: hour, minute: minute, on: now, calendar: calendar)
        else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// One pending call at a time, always replaced rather than stacked — the
    /// same policy `DrillReminder` follows, for the same reason.
    ///
    /// Tries the ALARM first (`DailyCallAlarm`): full-screen, rings through
    /// silent mode, buttons visible without a long press — the only thing on
    /// iOS that reads as an incoming call. The notification is the fallback for
    /// older systems and for a learner who granted notifications but not
    /// alarms; it rings in their own cloned voice but is, unavoidably, a
    /// banner.
    private static func schedule(_ plan: DailyCallPlan, callerName: String?) async {
        await cancelPendingRequest()

        // Every remaining slot today, not just the plan's own time — see
        // `fireDates`. They all carry this same still-unheard message;
        // whichever rings first and gets answered cancels the rest.
        let now = Date()
        var dates = fireDates(after: now)
        if plan.scheduledFor > now, !dates.contains(plan.scheduledFor) {
            // A callback ("call me back in 30 min") lands between slots — it
            // still has to ring at the time the learner picked.
            dates.append(plan.scheduledFor)
        }
        dates = Array(Set(dates)).sorted().prefix(DailyCallStore.maxTimes).map { $0 }
        guard !dates.isEmpty else { return }

        let caller = callerName ?? cachedCallerName ?? explain("Your future self")
        if await DailyCallAlarm.scheduleIfSupported(plan, at: dates, callerName: caller) {
            if let callerName { cachedCallerName = callerName }
            return
        }

        let content = UNMutableNotificationContent()
        // Caller ID. The whole illusion rests on this line reading like a
        // person, not a product.
        content.title = callerName ?? cachedCallerName ?? explain("Your future self")
        content.subtitle = explain("Incoming call")
        // The script itself — target-language material. Even a learner who
        // swipes it away has read one real sentence, which a "time to
        // practice!" body would never have given them.
        content.body = plan.script
        content.categoryIdentifier = categoryId
        content.userInfo = ["planId": plan.id.uuidString]
        // Breaks through Focus once the Time Sensitive capability is on the
        // App ID. Without the entitlement iOS silently treats it as .active,
        // so setting it now costs nothing and needs no signing change today.
        content.interruptionLevel = .timeSensitive
        // A phone ringing, from the app bundle. See
        // `DailyCallStore.ringtoneFilename` for why it can't be their voice.
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(DailyCallStore.ringtoneFilename))

        if let callerName { cachedCallerName = callerName }

        // One request per slot — a notification trigger fires once, so more
        // than one call a day means more than one pending request.
        for (index, date) in dates.enumerated() {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(requestId).\(index)",
                                      content: content, trigger: trigger))
        }
    }

    /// Remembered so a snooze — which happens with the app closed and no
    /// `AppState` in reach — can re-post the notification under the same
    /// caller name instead of falling back to a generic one.
    private static var cachedCallerName: String? {
        get { UserDefaults.standard.string(forKey: "futurevoice.dailyCall.callerName") }
        set { UserDefaults.standard.set(newValue, forKey: "futurevoice.dailyCall.callerName") }
    }
}

/// Where an answered call waits for the UI.
///
/// The tap is handled by the notification delegate, which has no `AppState` and
/// may run before any view is mounted (cold launch from the lock screen). So it
/// posts here and `RootTabView` picks it up on appear — the same staged
/// hand-off `AppState.pendingFreeTalk` uses, and for the same race.
@MainActor
final class DailyCallInbox: ObservableObject {
    static let shared = DailyCallInbox()
    /// Set when the learner answers; cleared by the view that starts the call.
    @Published var pendingAnswer: DailyCallPlan?
    /// Set when they decline FROM THE ALARM, which has no room to ask when to
    /// try again — the app opens on `DailyCallCallbackSheet` instead. The
    /// notification fallback asks inline (its category takes an array of
    /// actions) and never sets this.
    @Published var pendingCallbackChoice: DailyCallPlan?
    /// Set when a review reminder is tapped — `RootTabView` opens the due
    /// deck from here. Same handoff shape as the call: the notification
    /// delegate has no AppState to write to, and on a cold launch the tab
    /// isn't mounted yet when the tap arrives.
    @Published var pendingReview = false
    /// Set when a per-item callback is tapped — the app opens that exact
    /// word / phrase / line.
    @Published var pendingReviewItem: ItemReminder.Target?
}

/// Routes notification taps. Installed as the app's `UNUserNotificationCenter`
/// delegate at launch — without it, tapping an action does nothing at all and
/// tapping the banner just opens the app on whatever tab it was left on.
/// These are the COMPLETION-HANDLER signatures on purpose, not the prettier
/// `async` ones.
///
/// `UNUserNotificationCenterDelegate` is an `@objc` protocol whose methods are
/// all optional, and an `async` implementation of an optional ObjC requirement
/// does not reliably emit the selector UIKit actually looks up
/// (`userNotificationCenter:didReceive:withCompletionHandler:`). When it
/// doesn't, nothing errors and nothing warns — iOS simply finds no
/// implementation and falls back to plain "launch the app", so tapping the
/// call opens whatever tab was last on screen. `@objc` + the completion
/// handler is the spelling that cannot silently go missing.
final class DailyCallNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// The call is worth interrupting the app for: seeing your own voicemail
    /// arrive mid-session is the feature demonstrating itself.
    @objc func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    @objc func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier

        // Review reminders land on the due items themselves, not just "the
        // app": a reminder that opens wherever you left off is the reason a
        // schedule stops feeling real. Dismissals stay silent.
        if category == DrillReminder.categoryId {
            Task { @MainActor in
                defer { completionHandler() }
                guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
                DailyCallInbox.shared.pendingReview = true
            }
            return
        }

        // A per-item callback: it named a specific word / phrase / line, so
        // the tap opens THAT card, not a queue it might be buried in.
        if category == ItemReminder.categoryId {
            let info = response.notification.request.content.userInfo
            Task { @MainActor in
                defer { completionHandler() }
                guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
                guard let kind = info["kind"] as? String,
                      let value = info["value"] as? String,
                      let target = ItemReminder.Target(kind: kind, value: value) else {
                    // Unreadable payload — still better to open the queue than
                    // to swallow the tap.
                    DailyCallInbox.shared.pendingReview = true
                    return
                }
                DailyCallInbox.shared.pendingReviewItem = target
            }
            return
        }

        guard category == DailyCallScheduler.categoryId else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier

        Task { @MainActor in
            defer { completionHandler() }

            switch action {
            case let id where id.hasPrefix(DailyCallScheduler.declineActionPrefix):
                // The chosen delay rides in the action id's suffix — one
                // action per option, so the notification can show the choice
                // the alarm has no room for.
                let minutes = Int(id.dropFirst(DailyCallScheduler.declineActionPrefix.count))
                await DailyCallScheduler.decline(after: minutes)

            case UNNotificationDismissActionIdentifier:
                // Swiped away. Deliberately nothing: no reschedule, no record,
                // no consequence tomorrow.
                break

            default:
                // Explicit Answer, or a tap on the banner itself — both mean
                // "pick up".
                guard let plan = DailyCallStore.shared.load(), !plan.isSettled else { return }
                DailyCallScheduler.markAnswered()
                DailyCallInbox.shared.pendingAnswer = plan
            }
        }
    }
}

import Foundation
import UserNotifications

/// Schedules the daily call and handles what the learner does with it.
///
/// Both surfaces (`DailyCallAlarm` first, notification as fallback) offer the
/// same two choices, and the second one is the reason this works at all:
///
///   • **Answer** — opens the app and starts the talk.
///   • **Can't talk now** — declines. NOT a failure. 전화영어's forfeited
///     lesson is what makes people cancel; here a declined call is simply a
///     call that wasn't taken — no callback, no follow-up question, no app
///     opening, never a scold, never a broken counter. The learner's own
///     later times today still ring, because those are their schedule.
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
    /// Matched by PREFIX: builds before 2026-09-21 suffixed it with a
    /// callback delay (`…_DECLINE_60`), and a notification already delivered
    /// by one of them still has to decline when tapped after the update.
    static let declineActionId = "FUTUREVOICE_CALL_DECLINE"

    private static let requestId = "futurevoice.daily-call"

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
        // Background action: declining never opens the app.
        let decline = UNNotificationAction(
            identifier: declineActionId,
            title: explain("Can't talk now"),
            options: [])
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [answer, decline],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
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
        // A parked voice (see `VoiceParking`) can't write tomorrow's voicemail,
        // and answering would open a call straight into the paywall. Stand
        // down; the next refresh after the voice comes back arms it again.
        // The learner's setting is untouched.
        guard !VoiceParking.isParked(voiceId) else {
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
        // Written now, heard then: the script is dated to the rings
        // `schedule` is about to arm, not to this moment.
        context.ringDates = Array(Set(fireDates(after: now) + [fireDate])).sorted()

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

    /// They sent it away. That's the whole of it: nobody rings back, nothing
    /// asks when to try again, the app doesn't open (2026-09-21, user
    /// decision — a callback prompt after "can't talk" was the app nagging).
    ///
    /// The learner's OWN later times today are left armed; they chose those.
    /// So the plan settles as `.declined` only once no slot is left today —
    /// until then `callbackCount` counts the declines, and a plan that rings
    /// out after one still settles as declined (see `settleIfRangOut`).
    static func decline() async {
        let store = DailyCallStore.shared
        guard var plan = store.load(), !plan.isSettled else { return }
        Analytics.capture("daily_call_declined", ["declines": plan.callbackCount + 1])
        plan.callbackCount += 1
        if hasSlotRemainingToday(after: Date()) {
            store.save(plan)
        } else {
            settle(plan, as: .declined)
            await cancelPendingRequest()
        }
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
        // Declined earlier today and never answered later: the last thing
        // the learner actually did was say no, not ignore it.
        let outcome: DailyCallOutcome = plan.callbackCount > 0 ? .declined : .missed
        if outcome == .missed {
            Analytics.capture("daily_call_missed", [:])
        }
        settle(plan, as: outcome)
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

    // MARK: - A call already in progress

    /// Set while a conversation is live (`ConversationView`, bracketed with
    /// `CallNowPlaying`). In memory on purpose: a killed app drops it, and the
    /// next launch's re-arm puts the rings back.
    private static var liveCallSince: Date?

    /// A conversation is on screen right now — anything that would interrupt
    /// it (an alert, `SyncQuotaNotice`) waits.
    static var isLiveCall: Bool { liveCallSince != nil }

    /// A scheduled ring must not land on a call the learner is already in.
    /// An AlarmKit alert takes the audio session — the live call's engine
    /// stops under it and the call dies with an error — and there is nothing
    /// to "answer": they are on the phone with that same person right now.
    /// So every pending ring is taken down for the length of the call, and
    /// `schedule` refuses to arm one until `releaseAfterLiveCall`.
    static func holdForLiveCall() {
        guard liveCallSince == nil else { return }
        liveCallSince = Date()
        Task { await cancelPendingRequest() }
    }

    /// The call is over: put the rings back. A slot that came due DURING the
    /// call is settled as answered — they were talking to their future self
    /// at that very moment, and a voicemail next morning asking "couldn't
    /// talk yesterday?" would be false. Answering cancels the rest of the
    /// day's slots, exactly as a real pickup does; the session's own end
    /// (`refreshDailyCall(force: true)`) writes the next call.
    static func releaseAfterLiveCall() {
        guard let since = liveCallSince else { return }
        liveCallSince = nil
        Task {
            let store = DailyCallStore.shared
            guard store.isEnabled, let plan = store.load(), !plan.isSettled else { return }
            let now = Date()
            let cameDue = (fireDates(after: since) + [plan.scheduledFor])
                .contains { $0 > since && $0 <= now }
            if cameDue {
                Analytics.capture("daily_call_during_talk", [:])
                settle(plan, as: .answered, heard: true)
                store.clearUnheard()
                await cancelPendingRequest()
                return
            }
            await schedule(plan, callerName: nil)
        }
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
    ///
    /// The times come from the study timetable (`StudyPlan`): a talk block IS
    /// a call. A timetable seeded from the call times, with every block on
    /// every day, gives exactly the old answer; weekdays, rest days and
    /// one-off moves are what it adds.
    static func fireDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        // The routine is the ONE place a call lives (founder, 2026-10-03:
        // "the daily call and the routine's call are the same thing"). A
        // routine with no talk at a set time rings nothing — there used to be
        // a fallback to the call's own times, which was a second schedule
        // nobody could see from the routine.
        StudyPlanStore.shared.plan.callDates(after: now, calendar: calendar)
    }

    /// The timetable changed: put the rings where it now says. The stored
    /// voicemail is kept (it is still the same unheard message) but moved to
    /// the next slot if its own time is no longer one; nothing planned in the
    /// next two weeks takes every ring down.
    static func rearmFromStoredPlan() {
        guard liveCallSince == nil else { return }
        Task {
            let store = DailyCallStore.shared
            guard store.isEnabled, var plan = store.load(), !plan.isSettled else { return }
            let dates = fireDates(after: Date())
            guard let first = dates.first else {
                await cancelPendingRequest()
                return
            }
            if !dates.contains(plan.scheduledFor) {
                plan.scheduledFor = first
                store.save(plan)
            }
            await schedule(plan, callerName: nil)
        }
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
        // Never arm into a live call (see `holdForLiveCall`); the release
        // re-arms from the stored plan.
        guard liveCallSince == nil else { return }

        // Every remaining slot today, not just the plan's own time — see
        // `fireDates`. They all carry this same still-unheard message;
        // whichever rings first and gets answered cancels the rest.
        let now = Date()
        var dates = fireDates(after: now)
        if plan.scheduledFor > now, !dates.contains(plan.scheduledFor) {
            // A plan written for a time the learner has since removed, or an
            // older build's callback: it still rings when it said it would.
            dates.append(plan.scheduledFor)
        }
        dates = Array(Set(dates)).sorted().prefix(DailyCallStore.maxTimes).map { $0 }
        guard !dates.isEmpty else { return }

        let caller = callerName ?? cachedCallerName ?? explain("Your future self")
        if await DailyCallAlarm.scheduleIfSupported(plan, at: dates, callerName: caller) {
            if let callerName { cachedCallerName = callerName }
            // A call started while the alarm was being armed.
            if liveCallSince != nil { await cancelPendingRequest() }
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
        if liveCallSince != nil { await cancelPendingRequest() }
    }

    /// Remembered so a re-arm — which can happen with the app closed and no
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
    /// Set when a review reminder is tapped — `RootTabView` opens the due
    /// deck from here. Same handoff shape as the call: the notification
    /// delegate has no AppState to write to, and on a cold launch the tab
    /// isn't mounted yet when the tap arrives.
    @Published var pendingReview = false
    /// Set when a per-item callback is tapped — the app opens that exact
    /// word / phrase / line.
    @Published var pendingReviewItem: ItemReminder.Target?
    /// Set when the weekly test's reminder is tapped — the app opens the test.
    @Published var pendingWeeklyTest = false
    /// A timetable say-it-again reminder was tapped: pick a talk to redo.
    @Published var pendingSayItAgain = false
    /// Set when the week-turn notification carried the week's numbers — the
    /// app opens "Your week", whose last card is the test.
    @Published var pendingWeekRecap = false
    /// Developer: a recap built on demand (any window), raised as is.
    @Published var debugWeekRecap: WeekRecap?
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

        // A say-it-again block came due: ask which talk.
        if category == PlanReminder.sayItAgainCategoryId {
            Task { @MainActor in
                defer { completionHandler() }
                guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
                DailyCallInbox.shared.pendingSayItAgain = true
            }
            return
        }

        // The week turned: land on the week's cards when the notice spoke
        // about the week, otherwise straight on the test.
        if category == WeeklyTestReminder.categoryId {
            let recap = response.notification.request.content.userInfo[WeeklyTestReminder.recapKey] as? Bool ?? false
            Task { @MainActor in
                defer { completionHandler() }
                guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
                if recap {
                    DailyCallInbox.shared.pendingWeekRecap = true
                } else {
                    DailyCallInbox.shared.pendingWeeklyTest = true
                }
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
            case let id where id.hasPrefix(DailyCallScheduler.declineActionId):
                await DailyCallScheduler.decline()

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

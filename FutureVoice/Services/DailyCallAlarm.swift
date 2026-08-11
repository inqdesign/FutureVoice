import AppIntents
import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

/// The daily call as a real ALARM, not a banner.
///
/// A `UNNotification` can never look like an incoming call — it's a banner, its
/// buttons only appear on a long press, and on a silenced phone it makes no
/// sound at all, which is exactly how the first build got missed. AlarmKit is
/// the only API that gives an app a full-screen, lock-screen alert that rings
/// **through silent mode and Focus**, with its buttons visible immediately.
///
/// ## What this file can and cannot make it feel like
///
/// It cannot make it LOOK like a call. iOS hands the incoming-call screen to
/// CallKit alone, and CallKit demands a server-sent VoIP push for a real
/// person-to-person call — Apple rejects it for anything else. An AlarmKit
/// alert is an alarm screen and no amount of configuration changes that.
///
/// What it CAN do is make something ring through a silenced phone, with a
/// labelled Answer button, sounding like a telephone. The rest of the
/// "somebody is calling me" feeling is not built here at all — it comes from
/// the caller having a MEMORY (`VoicemailEngine.Context`'s call history) and
/// from an unanswered call leaving a trace instead of evaporating
/// (`DailyCallOutcome`). A person who remembers you were busy yesterday reads
/// as a person; a full-screen skin over a timer does not.
///
/// Below iOS 26.1 the notification path stays in place — same ringtone, same
/// buttons, just a banner.
enum DailyCallAlarm {

    /// AlarmKit ships in the iOS 26.0 SDK, but the non-deprecated
    /// `AlarmPresentation.Alert` initializer landed in 26.1 — and its
    /// predecessor demands a `stopButton` the system no longer draws. Gating on
    /// 26.1 keeps one code path instead of two that render differently.
    static var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) { return true }
        #endif
        return false
    }

    #if canImport(AlarmKit)

    /// Ferried alongside the alarm so the alert can name who's calling.
    /// Deliberately tiny — metadata is serialized into the Live Activity, so
    /// the script itself stays on disk and is looked up by the answer path.
    @available(iOS 26.1, *)
    struct CallMetadata: AlarmMetadata {
        var callerName: String
    }

    /// Replace any standing alarm with one for `plan`.
    ///
    /// Returns false when AlarmKit can't take it (not authorized, past the
    /// alarm limit, scheduling threw) so the caller can fall back to the
    /// notification rather than leaving the learner with no call at all.
    @available(iOS 26.1, *)
    @discardableResult
    static func schedule(_ plan: DailyCallPlan, at dates: [Date],
                         callerName: String) async -> Bool {
        let upcoming = dates.filter { $0 > Date() }.sorted()
        guard !upcoming.isEmpty else { return false }
        guard await isAuthorized() else { return false }

        cancelAll()

        // BUTTON MAPPING — deliberately inverted from what reads naturally.
        //
        // `AlarmPresentation.Alert.stopButton` was deprecated in iOS 26.1: the
        // system draws that button and we cannot label it. The SECONDARY button
        // is the only one whose text and icon are ours. So Answer goes there,
        // where it can actually say "Answer" and carry a phone glyph, and the
        // system's own button becomes Decline — which is the right shape
        // anyway, since dismissing a call IS declining it.
        let alert = AlarmPresentation.Alert(
            // Caller ID. The whole thing rests on this reading like a person
            // rather than a product.
            title: LocalizedStringResource(stringLiteral: callerName),
            secondaryButton: AlarmButton(
                text: LocalizedStringResource(stringLiteral: explain("Answer")),
                textColor: .green,
                systemImageName: "phone.fill"),
            // `.custom`, NOT `.countdown`: countdown would oblige the app to
            // ship a Live Activity widget for that state, and the callback is
            // already handled by re-scheduling the same plan.
            secondaryButtonBehavior: .custom)

        let attributes = AlarmAttributes<CallMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: CallMetadata(callerName: callerName),
            tintColor: .accentColor)

        func configuration(for date: Date) -> AlarmManager.AlarmConfiguration<CallMetadata> {
            AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            // Mirrors the button mapping above: system button = decline,
            // our labelled one = answer. The decline delay is whatever they
            // set in Me — this surface has no room to ask.
            stopIntent: DeclineDailyCallIntent(),
            secondaryIntent: AnswerDailyCallIntent(),
            // A phone ringing, from the app bundle — see the note at the top
            // of this file for why it can't be the learner's own voice.
            sound: .named(DailyCallStore.ringtoneFilename))
        }

        // One alarm per remaining slot today, all holding the same unheard
        // message. A `.fixed` schedule fires once, so more than one call a day
        // means more than one alarm — and they must be armed now, because the
        // app won't be running between them to arm the next.
        //
        // Each needs its own id, derived from the plan's so `cancelAll` and a
        // re-schedule stay idempotent. Partial success still counts: if the
        // second alarm trips AlarmKit's ceiling, the first one ringing is far
        // better than falling back to a banner for the whole day.
        var scheduledAny = false
        for (index, date) in upcoming.enumerated() {
            let id = alarmId(for: plan, slot: index)
            do {
                _ = try await AlarmManager.shared.schedule(id: id,
                                                           configuration: configuration(for: date))
                scheduledAny = true
            } catch {
                break
            }
        }
        return scheduledAny
    }

    /// Deterministic per-slot id: the plan's UUID with its last byte replaced
    /// by the slot index, so the same plan always maps to the same ids.
    @available(iOS 26.1, *)
    private static func alarmId(for plan: DailyCallPlan, slot: Int) -> UUID {
        guard slot > 0 else { return plan.id }
        var bytes = withUnsafeBytes(of: plan.id.uuid) { Array($0) }
        bytes[15] = bytes[15] ^ UInt8(slot & 0xFF)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Drop every alarm this app owns. `AlarmManager.alarms` only ever returns
    /// our own, so there is nothing else here to hit.
    @available(iOS 26.1, *)
    static func cancelAll() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms { try? AlarmManager.shared.cancel(id: alarm.id) }
    }

    @available(iOS 26.1, *)
    static func isAuthorized() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:    return true
        case .denied:        return false
        case .notDetermined: return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        @unknown default:    return false
        }
    }

    #endif

    /// Version-erased entry points, so `DailyCallScheduler` never carries an
    /// `#available` ladder of its own.
    @discardableResult
    static func scheduleIfSupported(_ plan: DailyCallPlan, at dates: [Date],
                                    callerName: String) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            return await schedule(plan, at: dates, callerName: callerName)
        }
        #endif
        return false
    }

    static func cancelIfSupported() {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) { cancelAll() }
        #endif
    }

    static func requestAuthorizationIfSupported() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) { return await isAuthorized() }
        #endif
        return false
    }
}

// MARK: - Buttons

/// The primary button: pick up.
///
/// `openAppWhenRun` is what turns an alarm into a call — without it the button
/// dismisses the alert and the learner is left holding a phone that stopped
/// ringing. With it, the app comes up and `RootTabView` presents the talk from
/// the inbox, exactly like the notification path.
struct AnswerDailyCallIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Answer"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let plan = DailyCallStore.shared.load(), !plan.isSettled {
            DailyCallScheduler.markAnswered()
            DailyCallInbox.shared.pendingAnswer = plan
        }
        return .result()
    }
}

/// Sending the call away. Runs on the SYSTEM button — see the mapping note in
/// `schedule`.
///
/// This one DOES open the app, and only because the alarm gives us nowhere
/// else to ask. `AlarmPresentation.Alert` has exactly one button we control
/// and it's spent on Answer, so "in 30 min / in 3 hours" has no home on that
/// screen; the app comes up on `DailyCallCallbackSheet` instead. The trade is
/// real and deliberate — declining is supposed to cost nothing, and this costs
/// a context switch. The notification fallback, whose category takes an array
/// of actions, still asks inline and never opens anything.
///
/// The call is NOT settled here. Until they pick, it stays live: closing the
/// sheet without choosing falls back to their Me setting rather than silently
/// cancelling the day.
struct DeclineDailyCallIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Can't talk now"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let plan = DailyCallStore.shared.load(), !plan.isSettled {
            DailyCallInbox.shared.pendingCallbackChoice = plan
        }
        return .result()
    }
}

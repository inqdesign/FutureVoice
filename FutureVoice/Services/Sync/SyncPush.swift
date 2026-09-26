import CloudKit
import os
import UIKit

/// The other device's talk arrives without waiting for this one to be opened.
///
/// Sync has always had two clocks, and both are the learner's: a foreground
/// pass when the app is opened, and `SyncBackground`'s tasks, which iOS runs
/// when it feels like it. Neither can make the tablet's shelf carry the talk
/// that finished on the phone a minute ago — the tablet has to be picked up
/// first, which is the one moment the delay is visible. This is the third
/// clock, and it is the server's: a CloudKit zone subscription wakes the app
/// the moment anything in the zone changes, and the wake runs the same pass
/// every other trigger runs.
///
/// Three things it is deliberately not:
///
/// - **Not a notification.** `shouldSendContentAvailable` only — no alert, no
///   badge, no sound, nothing for the learner to read or dismiss. A silent
///   push needs no permission, so opting into sync can never be the reason a
///   permission sheet appears.
/// - **Not a guarantee.** iOS budgets silent pushes and drops them freely on
///   a low battery or a dozing phone. The foreground pass stays the one that
///   always runs; this only ever makes it earlier.
/// - **Not a second sync path.** It calls `requestSync` like everything else,
///   so a push landing beside a running pass is collapsed by the engine's
///   one-pass-at-a-time door rather than racing it.
///
/// A push also comes back to the device that CAUSED the change — CloudKit
/// doesn't exempt the sender — and that is left alone on purpose: the pull
/// finds its own records, the merge produces nothing new, and the pass costs
/// one empty `changes` call. Suppressing it would mean guessing which of our
/// own writes a push belongs to, and guessing wrong drops a real change.
@MainActor
enum SyncPush {

    /// The only thing a silent push can be watched with.
    ///
    /// Everything else here reports through `Analytics`, which goes to
    /// PostHog and can be read hours later from a console — and a wake that
    /// decides the push is not ours leaves no other trace at all, by design,
    /// because it draws nothing. So every outcome says so here, and
    /// `scripts/sync-push-probe.sh` reads it to tell "the push never arrived"
    /// apart from "it arrived and was dropped" — two failures that look
    /// identical from outside.
    ///
    /// `.notice`, not `.debug`, for two reasons: debug messages live in a
    /// memory buffer a stream often misses, and the run that matters most is
    /// on a REAL DEVICE, where Console.app shows notice and drops debug. One
    /// line per wake, and a wake is rare.
    private static let log = Logger(subsystem: "com.roro.futurevoice", category: "sync-push")

    /// One subscription per ZONE, shared by every device of the account.
    /// A private-database subscription already pushes to all of them, so a
    /// per-device id would buy nothing and cost N pushes per change; the
    /// zone is in the id because a shared iPad can hold two app accounts,
    /// each with its own zone, and one fixed id would have them overwriting
    /// each other's subscription.
    static func subscriptionID(for zone: String) -> String { "changes-\(zone)" }

    // MARK: - On / off

    /// Registers this device with APNs and makes sure the account's zone
    /// subscription exists. Both are idempotent, and neither is allowed to
    /// matter: sync works exactly as before if either fails.
    static func activate(zone: String, userId: String, transport: SyncTransport) {
        // Registering is what lets CloudKit's pushes reach this install at
        // all. `PushTokens.register()` asks for the same thing on every
        // launch and the call is idempotent, so this is belt and braces for
        // the moment sync is switched on.
        PushTokens.register()
        guard !SyncStore.wasSubscribedToPush(userId: userId) else { return }
        Task {
            do {
                try await transport.subscribeToZoneChanges(
                    zone, subscriptionID: subscriptionID(for: zone))
                SyncStore.setSubscribedToPush(true, userId: userId)
            } catch {
                // Left unset, so the next launch asks again. Nothing is shown:
                // what the learner would lose is promptness, not data.
                let reason = (error as? SyncTransportError).map(SyncEngine.describe)
                    ?? error.localizedDescription
                Analytics.capture("sync_push_subscribe_failed", ["reason": reason])
            }
        }
    }

    /// This device stops acting on sync wakes. Two things it must NOT do:
    ///
    /// - **Delete the subscription.** It belongs to every device of the
    ///   account, and the learner turning sync off on a phone has said
    ///   nothing about their tablet; only "Delete from iCloud" speaks for
    ///   all of them.
    /// - **Unregister from APNs**, which it did until `PushTokens` existed
    ///   (2026-09-26). That call is not sync's to make: the same
    ///   registration carries the Core's arrivals, billing notices and the
    ///   founder's announcements, so turning off a setting about iCloud was
    ///   silently switching off every notification the app can send. The
    ///   wakes stop because `handle` drops them when sync is off, which was
    ///   always the real gate.
    static func deactivate(userId: String) {
        SyncStore.setSubscribedToPush(false, userId: userId)
    }

    // MARK: - Arrival

    /// A remote notification landed. Returns what to tell iOS, which uses it
    /// to decide how generous to be with the next one.
    static func handle(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let engine = SyncEngine.shared
        // A push can arrive with no scene ever having been built, so auth has
        // not run and the engine has no account yet — the same cold start
        // `SyncBackground` handles.
        engine.restoreLastUserIfNeeded()
        guard let zone = engine.zoneName, isOurs(userInfo, zone: zone) else {
            log.notice("woken by a push that isn't this account's — dropped")
            return .noData
        }
        guard engine.isEnabled else {
            log.notice("woken for \(zone, privacy: .public), but sync is off here — dropped")
            return .noData
        }
        log.notice("woken for \(zone, privacy: .public) — running an items pass")
        // Items only. iOS grants a silent push seconds, not minutes, and what
        // the wake is for is that the TALK is here; audio has always gone
        // through the background tasks, and still does.
        await engine.syncAndWait(kinds: nil, scope: .items)
        // Whatever wouldn't fit — audio, a batch left over — is iOS's to
        // finish later, on the same terms as a trip to the background.
        SyncBackground.schedule()
        // NOT "sync_push" — that name belongs to the engine pushing records UP,
        // and this is the opposite direction: the server woke us.
        log.notice("pass done, audio left: \(engine.hasBackgroundWork, privacy: .public)")
        Analytics.capture("sync_woken", ["left": engine.hasBackgroundWork])
        return .newData
    }

    /// Whether this notification is our zone subscription's. Anything else —
    /// another app account's zone on a shared iPad, a push this build knows
    /// nothing about — is left for whoever it belongs to.
    ///
    /// Not private so `SyncPushTests` can run a REAL CloudKit payload through
    /// it. Delivery is Apple's and can only be watched on a device, but the
    /// parse is ours and would otherwise be the one link in the chain nothing
    /// tests — a push that arrives and is silently read as somebody else's
    /// looks exactly like a push that never came.
    static func isOurs(_ userInfo: [AnyHashable: Any], zone: String) -> Bool {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }
        return note.subscriptionID == subscriptionID(for: zone)
    }
}

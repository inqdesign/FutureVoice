import Foundation
import Supabase

/// Talk metering — the in-call timer IS the price, but only while the call
/// is actually a call.
///
/// While a call is active this ticks the `talk-tick` Edge Function every
/// 30 s of LIVE time; the server pools the seconds per day and consumes them
/// from the plan's daily allowance (subscribers) or the one-time seconds
/// balance (free users) — 1 s of talking = 1 s, no other unit. A 1-second
/// preflight tick fires at call start so an empty allowance surfaces BEFORE
/// the greeting speaks (otherwise every fresh session would carry a free
/// first minute).
///
/// **Idle time is not charged** (2026-08-18). It used to be: the ticker was a
/// plain wall clock, so a screen left open while the learner did something
/// else spent the day's minutes on silence — 8 minutes billed for a call
/// where nobody said a word. A learner cannot be asked to pay for a room they
/// walked out of. So the meter polls `isBillable` once a second and only
/// accumulates the seconds it answers yes to; the predicate lives in the
/// caller because only the call screen knows what "something is happening"
/// means (see `ConversationView.isBillableMoment`). Unset → everything counts,
/// which is the old behaviour and the safe default for a surface that hasn't
/// been taught the difference.
///
/// Failure policy is asymmetric on purpose:
/// - 402 → `onWallHit` — the call ends gracefully. `wallReason` says which
///   wall: a free user's spent pool (paywall) or a subscriber's finished
///   day ("see you tomorrow" — never a paywall, they already paid).
/// - Network blips → skip the tick and keep talking. A call must never drop
///   over billing plumbing; the server's chars-per-minute floor on turn TTS
///   bounds what unbilled seconds can cost us.
@MainActor
final class TalkMeter: ObservableObject {
    /// Whole minutes of talk this account can still speak (floor) — today's
    /// allowance remainder for subscribers, the balance for free users. Nil
    /// until the first tick lands.
    @Published private(set) var minutesRemaining: Int?

    enum WallReason { case outOfMinutes, dailyCapReached }
    /// Which wall ended the call — set just before `onWallHit` fires.
    @Published private(set) var wallReason: WallReason?

    /// Fired once when the server says today's talking is over (402).
    var onWallHit: (() -> Void)?

    /// Polled once a second: is this second part of the conversation? Seconds
    /// it answers `false` to are neither billed nor counted toward the day.
    /// Set it before `start`; nil means "count everything".
    var isBillable: (() -> Bool)?

    static let tickSeconds = 30

    /// How long after the learner's last voiced frame still counts as them
    /// talking. Must cover the longest end-of-turn wait (`vadLongSeconds` 5s
    /// + the STT settle) or the meter would stop mid-turn while the app is
    /// still deciding the learner finished.
    static let voiceGraceSeconds: Double = 6

    /// Poll cadence, and the ceiling on what one poll may contribute. The
    /// clamp matters because a suspended app resumes with a huge gap on the
    /// clock — without it, a phone that was in a pocket for ten minutes would
    /// bill all ten on its first poll back.
    private static let pollSeconds: Double = 1
    private static let maxSecondsPerPoll: Double = 2

    /// The target language, read straight from defaults rather than passed in
    /// — the meter is started from several surfaces and threading it through
    /// each one is how a caller eventually forgets and silently drops a call
    /// out of its club.
    private static func spokenLanguage() -> String {
        (UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en")
            .lowercased()
    }

    private var task: Task<Void, Never>?
    private var sessionKey = ""

    func start(sessionId: UUID) {
        stop()
        sessionKey = sessionId.uuidString
        task = Task { [weak self] in
            // Preflight before the first sleep — see type comment.
            await self?.tick(seconds: 1, label: "pre")
            var live = 0.0            // billable seconds not yet sent
            var i = 0
            var lastPoll = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
                guard !Task.isCancelled, let self else { break }
                let now = Date()
                let elapsed = min(now.timeIntervalSince(lastPoll), Self.maxSecondsPerPoll)
                lastPoll = now
                guard self.isBillable?() ?? true else { continue }
                live += elapsed
                guard live >= Double(Self.tickSeconds) else { continue }
                live -= Double(Self.tickSeconds)
                await self.tick(seconds: Self.tickSeconds, label: String(i))
                i += 1
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private struct TickBody: Encodable {
        let seconds: Int
        let session_id: String
        /// Which language was being SPOKEN. Billing ignores it — the daily
        /// allowance is per account — but the Core is one club per language
        /// (`20260816120000_core_by_language`) and this is the only place the
        /// server ever learns which one a call belongs to. Without it the
        /// seconds still bill and simply count toward no club.
        let language: String
    }
    private struct TickResponse: Decodable {
        let balance: Int
        let charged: Int
        let seconds_today: Int
        let daily_cap: Int?
    }

    private func tick(seconds: Int, label: String) async {
        do {
            let res: TickResponse = try await SupabaseProvider.shared.functions.invoke(
                "talk-tick",
                options: FunctionInvokeOptions(
                    // One key per tick: a retried request can't double-bill.
                    headers: ["X-Idempotency-Key": "tick:\(sessionKey):\(label)"],
                    body: TickBody(seconds: seconds, session_id: sessionKey,
                                   language: Self.spokenLanguage())
                )
            )
            // Accepted → these seconds were metered, so they're what the
            // home ring counts too (TalkTimeLog). Deriving the ring from
            // session spans instead made it disagree with the receipt.
            TalkTimeLog.add(seconds: seconds, language: Self.spokenLanguage())
            // Subscriber: what's left of the allowance. Free user: the
            // seconds balance. Both already in seconds.
            //
            // A plan with NO ceiling (Plus) comes back with no cap AND
            // nothing charged — the seconds were covered by the plan, not
            // taken from the balance. There is nothing to count down, so
            // the figure stays nil; falling through to `balance` here showed
            // the leftover free pool as "0 min left" mid-call on Plus.
            if res.daily_cap == nil, res.charged == 0 {
                minutesRemaining = nil
            } else {
                let secondsLeft = res.daily_cap.map { max(0, $0 - res.seconds_today) }
                    ?? max(0, res.balance)
                minutesRemaining = secondsLeft / 60
            }
        } catch let FunctionsError.httpError(code, data) where code == 402 {
            stop()
            minutesRemaining = 0
            let body = String(data: data, encoding: .utf8) ?? ""
            wallReason = body.contains("daily_cap_reached") ? .dailyCapReached : .outOfMinutes
            onWallHit?()
        } catch {
            // Transient failure: skip this tick. The idempotency key was
            // unique to it, so nothing double-bills when the next one lands.
        }
    }
}

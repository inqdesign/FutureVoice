import Foundation
import Supabase

/// Wall-clock talk metering — the in-call timer IS the price.
///
/// While a call is active this ticks the `talk-tick` Edge Function every
/// 30 s; the server pools the seconds per day and consumes them from the
/// plan's daily allowance (subscribers) or the one-time seconds balance
/// (free users) — 1 s of call = 1 s, no other unit. A 1-second preflight
/// tick fires at call start so an empty allowance surfaces BEFORE the
/// greeting speaks (otherwise every fresh session would carry a free first
/// minute).
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

    static let tickSeconds = 30

    private var task: Task<Void, Never>?
    private var sessionKey = ""

    func start(sessionId: UUID) {
        stop()
        sessionKey = sessionId.uuidString
        task = Task { [weak self] in
            // Preflight before the first sleep — see type comment.
            await self?.tick(seconds: 1, label: "pre")
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
                guard !Task.isCancelled else { break }
                await self?.tick(seconds: Self.tickSeconds, label: String(i))
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
                    body: TickBody(seconds: seconds, session_id: sessionKey)
                )
            )
            // Subscriber: what's left of today's allowance. Free user: the
            // seconds balance. Both already in seconds.
            let secondsLeft = res.daily_cap.map { max(0, $0 - res.seconds_today) }
                ?? max(0, res.balance)
            minutesRemaining = secondsLeft / 60
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

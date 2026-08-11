import Foundation
import Supabase

/// Wall-clock talk metering — the in-call timer IS the price.
///
/// While a call is active this ticks the `talk-tick` Edge Function every
/// 30 s; the server pools the seconds per day and debits the credit balance
/// at 4.5 credits/minute on boundary crossings, so the long-run price is
/// exact regardless of cadence. A 1-second preflight tick fires at call
/// start so an empty balance surfaces BEFORE the greeting speaks (otherwise
/// every fresh session would carry a free first minute).
///
/// Failure policy is asymmetric on purpose:
/// - 402 (balance spent) → `onWallHit` — the call ends gracefully.
/// - Network blips → skip the tick and keep talking. A call must never drop
///   over billing plumbing; the server's chars-per-minute floor on turn TTS
///   bounds what unbilled seconds can cost us.
@MainActor
final class TalkMeter: ObservableObject {
    /// Whole minutes of talk the balance still buys (floor). Nil until the
    /// first tick lands.
    @Published private(set) var minutesRemaining: Int?

    /// Fired once when the server says the balance is spent (402).
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
            minutesRemaining = max(0, Int(Double(res.balance) / AccountStatus.creditsPerMinute))
        } catch let FunctionsError.httpError(code, _) where code == 402 {
            stop()
            minutesRemaining = 0
            onWallHit?()
        } catch {
            // Transient failure: skip this tick. The idempotency key was
            // unique to it, so nothing double-bills when the next one lands.
        }
    }
}

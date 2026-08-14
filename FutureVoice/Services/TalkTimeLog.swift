import Foundation
import Supabase

/// The day's talk seconds as they were actually METERED — appended by
/// `TalkMeter` every time the server accepts a tick.
///
/// The home ring used to derive this from session records (`endedAt -
/// startedAt`), which is not the same thing at all: continuing an old talk
/// keeps the original `startedAt`, and backgrounding the app freezes the
/// ticks while the span keeps running. A learner saw "25 min" on the ring
/// and "13 min used today" on the receipt for the same afternoon.
///
/// So the ring reads what the meter counted, not what the clock could have
/// counted. Two consequences worth keeping: seconds that failed to meter
/// (offline) don't show up — but they weren't billed either, so the two
/// numbers still agree; and the count is keyed to the LOCAL day, because a
/// habit belongs to the day the learner is living in (the server pools per
/// UTC day for billing, and around midnight the two may briefly differ).
enum TalkTimeLog {
    private static let key = "futurevoice.talkSecondsByDay"
    /// Days kept before pruning — the ring needs today, the widget's history
    /// needs a couple of weeks of headroom, and this is a few hundred bytes.
    private static let keepDays = 30

    /// Record seconds the server accepted. Never call this for a tick that
    /// 402'd: those seconds were refused, and counting them would put the
    /// ring back ahead of the receipt.
    static func add(seconds: Int, now: Date = Date()) {
        guard seconds > 0 else { return }
        var map = load()
        map[dayKey(now), default: 0] += seconds
        save(prune(map, now: now))
    }

    static func secondsToday(now: Date = Date()) -> Int {
        load()[dayKey(now)] ?? 0
    }

    static func seconds(on day: Date) -> Int {
        load()[dayKey(day)] ?? 0
    }

    // MARK: - Server backfill

    /// Rebuild the log from the server's `usage_ledger`, which is where the
    /// meter's accepted ticks actually landed.
    ///
    /// The local file only starts filling the moment a build carrying
    /// `TalkMeter`'s write runs on this device, so without this the ring reads
    /// zero for a day that the receipt already counts — after an update, a
    /// reinstall, or a second device. Every accepted tick wrote a `talk_time`
    /// row carrying `metadata.seconds` and a timestamp, so the day's total is
    /// a read, not an estimate.
    ///
    /// Bucketed by the LOCAL day (the ledger's timestamps allow it, unlike
    /// the server's UTC-pooled `tts_char_pool`) and applied as a FLOOR: a tick
    /// accepted seconds ago may not be visible in this query yet, and a
    /// ledger read must never walk the ring backwards mid-call.
    @MainActor
    static func syncFromServer(now: Date = Date(), calendar: Calendar = .current) async {
        guard let session = try? await SupabaseProvider.shared.auth.session,
              let start = calendar.date(byAdding: .day, value: -(backfillDays - 1),
                                        to: calendar.startOfDay(for: now))
        else { return }

        struct LedgerRow: Decodable {
            let created_at: String
            let metadata: Metadata?
            struct Metadata: Decodable { let seconds: Int? }
        }
        guard let rows: [LedgerRow] = try? await SupabaseProvider.shared
            .from("usage_ledger")
            .select("created_at,metadata")
            .eq("user_id", value: session.user.id.uuidString)
            .eq("action", value: "talk_time")
            .gte("created_at", value: ISO8601DateFormatter().string(from: start))
            // One row per 30 s tick: a fortnight of heavy use is ~2k rows.
            .limit(4000)
            .execute()
            .value
        else { return }

        var serverByDay: [String: Int] = [:]
        for row in rows {
            guard let seconds = row.metadata?.seconds, seconds > 0,
                  let at = parseTimestamp(row.created_at) else { continue }
            serverByDay[dayKey(at), default: 0] += seconds
        }
        guard !serverByDay.isEmpty else { return }

        var map = load()
        for (day, seconds) in serverByDay where seconds > (map[day] ?? 0) {
            map[day] = seconds
        }
        save(prune(map, now: now))
    }

    /// How far back the backfill reaches — today for the ring, plus enough
    /// history for the widget's recent days.
    private static let backfillDays = 14

    /// Postgres timestamps come back with fractional seconds, but not always
    /// — one formatter can't parse both, and a nil date would silently drop
    /// the day.
    private static func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    // MARK: - Disk

    private static func load() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func save(_ map: [String: Int]) {
        UserDefaults.standard.set(map, forKey: key)
    }

    private static func prune(_ map: [String: Int], now: Date) -> [String: Int] {
        guard map.count > keepDays else { return map }
        let cutoff = dayKey(now.addingTimeInterval(-Double(keepDays) * 86_400))
        return map.filter { $0.key >= cutoff }
    }

    /// LOCAL day — see the type comment for why this differs from the
    /// server's UTC pooling.
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

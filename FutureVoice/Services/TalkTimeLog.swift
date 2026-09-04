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
    /// Days kept before pruning. The ring needs today and the widget a
    /// fortnight, but the STREAK needs the whole entry run plus room to see
    /// where it started — pruning at 30 would cap a 30-day streak at exactly
    /// the length it is trying to prove.
    private static let keepDays = 45

    /// Record seconds the server accepted. Never call this for a tick that
    /// 402'd: those seconds were refused, and counting them would put the
    /// ring back ahead of the receipt.
    ///
    /// `language` is what was being SPOKEN. The ring doesn't care — a minute
    /// is a minute against the day's allowance — but the streak does, because
    /// the Core counts one language at a time and the app must not show a
    /// second, looser streak beside it.
    static func add(seconds: Int, language: String?, now: Date = Date()) {
        guard seconds > 0 else { return }
        var map = load()
        map[key(day: now, language: language), default: 0] += seconds
        save(prune(map, now: now))
    }

    /// Every language's seconds for the day — what the ring and the receipt
    /// read, since the daily allowance is per account.
    static func secondsToday(now: Date = Date()) -> Int {
        seconds(on: now)
    }

    static func seconds(on day: Date) -> Int {
        let prefix = dayKey(day)
        return load().reduce(0) { total, entry in
            entry.key == prefix || entry.key.hasPrefix(prefix + separator)
                ? total + entry.value : total
        }
    }

    /// One language's seconds for the day — the streak's input.
    ///
    /// Entries written before this log knew about languages have no language
    /// in their key and are deliberately NOT counted here: they can't be
    /// attributed, and guessing would put days into a streak that may have
    /// been spoken in another language. They still count in the totals above.
    static func seconds(on day: Date, language: String) -> Int {
        load()[key(day: day, language: language)] ?? 0
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
    /// the server's UTC-pooled `tts_char_pool`). A floor for TODAY — a tick
    /// accepted seconds ago may not be visible in this query yet, and a
    /// ledger read must never walk the ring backwards mid-call — and the
    /// plain truth for the few days behind it (see the loop).
    @MainActor
    static func syncFromServer(now: Date = Date(), calendar: Calendar = .current) async {
        guard let session = try? await SupabaseProvider.shared.auth.session,
              let start = calendar.date(byAdding: .day, value: -(backfillDays - 1),
                                        to: calendar.startOfDay(for: now))
        else { return }

        struct LedgerRow: Decodable {
            let created_at: String
            let metadata: Metadata?
            struct Metadata: Decodable { let seconds: Int?; let language: String? }
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
            // Ticks from a build that predates language reporting land under
            // the bare day key, exactly where this log used to put them.
            serverByDay[key(day: at, language: row.metadata?.language), default: 0] += seconds
        }
        guard !serverByDay.isEmpty else { return }

        var map = load()
        let today = dayKey(now)
        let correctableFrom = dayKey(now.addingTimeInterval(-Double(correctDownDays) * 86_400))
        for (day, seconds) in serverByDay {
            let date = String(day.prefix(10))
            // The last few days are also corrected DOWNWARD, because the
            // floor's one failure mode is unbounded: a gateway session that
            // outlived its call billed 45 minutes of silence (2026-09-05,
            // fixed server-side), and a floor can only ever agree with it.
            // The ledger is the receipt, so where it has the day's rows it
            // is the day. Not TODAY — a tick accepted seconds ago may not be
            // visible yet, and the ring must never walk backwards mid-call —
            // and not further back than a few days, where `usage_ledger`'s
            // oldest-first truncation could leave a day only partly present
            // and quietly shorten a streak.
            if date != today, date >= correctableFrom {
                map[day] = seconds
            } else if seconds > (map[day] ?? 0) {
                map[day] = seconds
            }
        }
        save(prune(map, now: now))
    }

    /// How far back a day may be corrected downward. Deliberately short —
    /// see the loop above.
    private static let correctDownDays = 3

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
        // Compare the DATE part: "2026-08-01|en" must not be judged against a
        // bare cutoff by plain string order, or a language suffix would keep
        // stale days alive.
        return map.filter { String($0.key.prefix(10)) >= cutoff }
    }

    /// `yyyy-MM-dd|lang`, or a bare `yyyy-MM-dd` when the language is
    /// unknown — which is what every entry written before 2026-08 looks like.
    /// Prefix-compatible on purpose: the totals scan by date prefix, so old
    /// rows keep counting without a migration pass.
    private static let separator = "|"

    private static func key(day: Date, language: String?) -> String {
        let lang = language?.trimmingCharacters(in: .whitespaces).lowercased()
        guard let lang, !lang.isEmpty else { return dayKey(day) }
        return dayKey(day) + separator + lang
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

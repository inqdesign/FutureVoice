import Foundation
import Supabase

/// Where your talk time actually went — read straight from the server's
/// `usage_ledger` (owner-readable via RLS).
///
/// This exists because "49 of 60 min" answers *how much* and nothing else.
/// The beta's loudest complaint was never the price, it was not knowing what
/// a tap costs; a number with no breakdown behind it recreates exactly that
/// doubt. Every metered row carries `metadata.seconds`, so the split is a
/// read, not an estimate — and the free rows (delta 0) are shown too,
/// because "reviewing cost you nothing" is only believable when the learner
/// can see it counted.
struct UsageBreakdown {
    /// One metered category — the two things that spend minutes.
    struct Meter: Identifiable {
        var id: String { key }
        let key: String
        let title: String
        let icon: String
        var seconds: Int
        var count: Int

        var minutes: Int { seconds / 60 }
        /// "12 min" / "40 sec" — under a minute must not read as "0 min".
        var durationLabel: String {
            seconds >= 60 ? explain("\(seconds / 60) min")
                          : explain("\(seconds) sec")
        }
    }

    /// One free category: counted, never charged.
    struct FreeItem: Identifiable {
        var id: String { key }
        let key: String
        let title: String
        let icon: String
        var count: Int
    }

    /// A day's metered total, for the recent-days list. Talk and scene
    /// seconds are kept apart because since 2026-08-14 they come out of
    /// different allowances — a chart that adds them would re-tell the very
    /// confusion that split fixed.
    struct Day: Identifiable {
        var id: String { date }
        let date: String        // "yyyy-MM-dd" (UTC, matching the server pool)
        var talkSeconds: Int = 0
        var sceneSeconds: Int = 0

        var seconds: Int { talkSeconds + sceneSeconds }
        var minutes: Int { seconds / 60 }
    }

    var today: [Meter] = []
    var week: [Meter] = []
    var freeToday: [FreeItem] = []
    var days: [Day] = []
    /// True once a fetch has landed — separates "nothing yet" from "empty".
    var loaded = false

    var todaySeconds: Int { today.reduce(0) { $0 + $1.seconds } }
    var weekSeconds: Int { week.reduce(0) { $0 + $1.seconds } }

    // MARK: - Fetch

    private struct LedgerRow: Decodable {
        let action: String
        let delta: Int
        let created_at: String
        let metadata: Metadata?

        struct Metadata: Decodable {
            let seconds: Int?
            let purpose: String?
        }
    }

    /// Last 7 days of ledger rows for the signed-in user, aggregated.
    /// Best-effort: any failure returns an unloaded breakdown rather than
    /// throwing — a usage page is never worth blocking settings for.
    static func fetch() async -> UsageBreakdown {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            return UsageBreakdown()
        }
        let since = ISO8601DateFormatter().string(
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())

        guard let rows: [LedgerRow] = try? await SupabaseProvider.shared
            .from("usage_ledger")
            .select("action,delta,created_at,metadata")
            .eq("user_id", value: session.user.id.uuidString)
            .gte("created_at", value: since)
            .order("created_at", ascending: false)
            // A heavy week is a few thousand rows (every turn writes one);
            // the cap keeps a pathological account from paging forever.
            .limit(4000)
            .execute()
            .value
        else { return UsageBreakdown() }

        return aggregate(rows)
    }

    // MARK: - Aggregation

    /// The two metered buckets. `talk_time` is wall-clock call time;
    /// `tts_scene` is Watch scene playback — the only two things that spend.
    private static func meterTitle(_ action: String) -> (String, String)? {
        switch action {
        case "talk_time": return (explain("Talking"), "phone.fill")
        case "tts_scene": return (explain("Watch scenes"), "play.circle.fill")
        default: return nil
        }
    }

    /// Free work, grouped by what the learner would recognize doing — not by
    /// the engine that ran. `purpose` carries that intent on every row.
    private static func freeTitle(action: String, purpose: String?) -> (String, String, String)? {
        switch purpose {
        case "drill", "enrichment":
            return ("drills", explain("Review drills"), "rectangle.stack.fill")
        case "shadow":
            return ("shadow", explain("Shadowing"), "waveform")
        case "library":
            return ("library", explain("Word & phrase playback"), "text.book.closed.fill")
        case "summary", "weekly":
            return ("reports", explain("Summaries & reports"), "doc.text.fill")
        case "topics", "scenario-curriculum", "scene", "parse", "freetalk-openers":
            return ("ideas", explain("Building situations & topics"), "square.grid.2x2")
        case "transcribe", "turn", "opener":
            // Part of a call — already counted under Talking; listing it
            // again as "free" would double-tell the same story.
            return nil
        default:
            // Anything unmapped still deserves a line, but a generic one.
            return action.hasPrefix("gemini") || action.hasPrefix("tts")
                ? ("other", explain("Other free activity"), "sparkles")
                : nil
        }
    }

    private static func aggregate(_ rows: [LedgerRow]) -> UsageBreakdown {
        var out = UsageBreakdown()
        out.loaded = true

        let todayKey = dayKey(Date())
        var todayMeters: [String: Meter] = [:]
        var weekMeters: [String: Meter] = [:]
        var free: [String: FreeItem] = [:]
        var dayTotals: [String: Day] = [:]

        for row in rows {
            let day = String(row.created_at.prefix(10))
            let seconds = row.metadata?.seconds ?? 0

            if let (title, icon) = meterTitle(row.action), seconds > 0 {
                var week = weekMeters[row.action]
                    ?? Meter(key: row.action, title: title, icon: icon, seconds: 0, count: 0)
                week.seconds += seconds
                week.count += 1
                weekMeters[row.action] = week

                var totals = dayTotals[day] ?? Day(date: day)
                if row.action == "tts_scene" { totals.sceneSeconds += seconds }
                else { totals.talkSeconds += seconds }
                dayTotals[day] = totals

                if day == todayKey {
                    var t = todayMeters[row.action]
                        ?? Meter(key: row.action, title: title, icon: icon, seconds: 0, count: 0)
                    t.seconds += seconds
                    t.count += 1
                    todayMeters[row.action] = t
                }
                continue
            }

            // Free rows: delta 0 AND not a metered action at all. (Checking
            // `meterTitle` again — not just the `seconds > 0` branch above —
            // keeps a zero-second scene row out of the free buckets, where
            // its "scene" purpose would file it under building situations.)
            guard row.delta == 0, day == todayKey, meterTitle(row.action) == nil,
                  let (key, title, icon) = freeTitle(action: row.action,
                                                     purpose: row.metadata?.purpose)
            else { continue }
            var item = free[key] ?? FreeItem(key: key, title: title, icon: icon, count: 0)
            item.count += 1
            free[key] = item
        }

        // Talking first, then scenes — the order they cost, most first.
        let order = ["talk_time", "tts_scene"]
        out.today = order.compactMap { todayMeters[$0] }
        out.week = order.compactMap { weekMeters[$0] }
        out.freeToday = free.values.sorted { $0.count > $1.count }
        out.days = dayTotals.values.sorted { $0.date > $1.date }
        return out
    }

    #if DEBUG
    /// A representative day + week for the screenshot harness.
    static var sample: UsageBreakdown {
        var out = UsageBreakdown()
        out.loaded = true
        out.today = [
            Meter(key: "talk_time", title: explain("Talking"),
                  icon: "phone.fill", seconds: 512, count: 18),
            Meter(key: "tts_scene", title: explain("Watch scenes"),
                  icon: "play.circle.fill", seconds: 143, count: 22),
        ]
        out.freeToday = [
            FreeItem(key: "drills", title: explain("Review drills"),
                     icon: "rectangle.stack.fill", count: 34),
            FreeItem(key: "shadow", title: explain("Shadowing"),
                     icon: "waveform", count: 12),
            FreeItem(key: "ideas", title: explain("Building situations & topics"),
                     icon: "square.grid.2x2", count: 7),
            FreeItem(key: "reports", title: explain("Summaries & reports"),
                     icon: "doc.text.fill", count: 3),
        ]
        let today = dayKey(Date())
        out.days = [655, 1240, 0, 430, 980, 610, 320].enumerated().map { i, secs in
            Day(date: dayKey(Date().addingTimeInterval(Double(-i) * 86_400)),
                talkSeconds: secs)
        }.filter { $0.seconds > 0 || $0.date == today }
        return out
    }
    #endif

    /// The server pools per `current_date` in UTC — mirror it exactly or
    /// "today" drifts around midnight.
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// "Mon 11 Aug" for a "yyyy-MM-dd" key; today and yesterday get names.
    static func dayLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.timeZone = TimeZone(identifier: "UTC")!
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        if key == dayKey(Date()) { return explain("Today") }
        if key == dayKey(Date().addingTimeInterval(-86_400)) { return explain("Yesterday") }
        let out = DateFormatter()
        out.timeZone = TimeZone(identifier: "UTC")!
        out.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return out.string(from: date)
    }
}

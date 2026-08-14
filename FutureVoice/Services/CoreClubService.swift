import Foundation
import UserNotifications

/// The Core — 100 seats held by learners who actually speak most days.
///
/// Two facts, deliberately separate (see `20260813120000_core_club.sql`):
///
///   * **Qualification** — 28 of the last 30 days over the daily bar. Earned
///     once, granted the moment it's done, and NEVER revoked. `joinNumber`
///     and `qualifiedAt` are the permanent record; a low number is the whole
///     founding story, which is why there's no separate "founding" flag.
///   * **A seat** — kept with 5 of the last 7 days. Loose on purpose: a
///     missed day costs nothing. A seat is only ever vacated by its holder,
///     never taken by a newcomer, so an arrival is pure good news to the
///     people already inside.
///
/// One glyph shows both (`CoreSeal`): filled = seated now, outlined =
/// qualified but currently seatless. Losing a seat is dormancy, not a scar.
///
/// The client only READS. Every transition is decided by the server's
/// midnight-UTC settlement — the same clock the daily allowance resets on.
enum CoreClubService {

    // MARK: - Rows

    /// The signed-in learner's own membership. Includes the private columns
    /// their `core_membership` self-read policy allows.
    struct Membership: Decodable {
        let join_number: Int
        let qualified_at: String
        let seated: Bool
        let seated_since: String?
        let days_total: Int

        var joinNumber: Int { join_number }
        /// Cumulative days seated across every stint. Stock — it survives
        /// losing the seat, which is what makes leaving a rest rather than a
        /// bankruptcy.
        var daysTotal: Int { days_total }
    }

    /// What a stranger is allowed to see next to someone's name: the seal and
    /// the number. Never lapses, never how much anyone talks.
    struct Badge: Decodable {
        let user_id: String
        let join_number: Int
        let seated: Bool
    }

    struct Config: Decodable {
        let seats: Int
        let daily_bar_seconds: Int
        let entry_window_days: Int
        let entry_required_days: Int
        let keep_window_days: Int
        let keep_required_days: Int
        let bonus_seconds: Int
    }

    /// An arrival. Departures are not readable by clients at all — the RLS
    /// policy filters `kind = 'left'` out — so nobody can work out whose seat
    /// they took.
    struct Event: Decodable {
        let id: Int
        let kind: String
        let user_id: String?
        let join_number: Int?
        let club_size: Int
        let first_time: Bool
    }

    /// Everything the club screen needs, in one round trip, for the caller
    /// only. `core_daily_activity` is revoked from clients — this RPC is the
    /// only door, and it reads nobody else's days.
    struct Progress: Decodable {
        struct Day: Decodable {
            let day: String
            let seconds: Int
            let met: Bool
        }
        struct Member: Decodable {
            let join_number: Int
            let seated: Bool
            let days_total: Int
        }

        let bar_seconds: Int
        let bonus_seconds: Int
        let seats: Int
        let club_size: Int
        let member: Member?
        let days: [Day]
        let met_entry: Int
        let entry_required: Int
        let met_keep: Int
        let keep_required: Int
        /// Best-case days until the entry bar, assuming every remaining day
        /// is met. Nil once qualified.
        let days_to_entry: Int?
        /// Best-case days until a seatless member is eligible again.
        let days_to_return: Int?
        /// A long absence means the month has to be earned again.
        let requalifying: Bool
        /// Bar cleared, badge held, club full — nothing to do but wait.
        let waiting_for_seat: Bool

        /// Absences inside the entry window, and how many are still spare.
        var missedInEntryWindow: Int { days.count - met_entry }
        var spareAbsences: Int {
            max(days.count - entry_required - missedInEntryWindow, 0)
        }
    }

    static func fetchProgress() async -> Progress? {
        try? await SupabaseProvider.shared
            .rpc("core_my_progress")
            .execute()
            .value
    }

    // MARK: - Reads

    private static func myUserId() async -> String? {
        guard let id = try? await SupabaseProvider.shared.auth.session.user.id else { return nil }
        return id.uuidString.lowercased()
    }

    static func fetchMine() async -> Membership? {
        guard let uid = await myUserId() else { return nil }
        let rows: [Membership]? = try? await SupabaseProvider.shared
            .from("core_membership")
            .select("join_number,qualified_at,seated,seated_since,days_total")
            .eq("user_id", value: uid)
            .execute()
            .value
        return rows?.first
    }

    static func fetchConfig() async -> Config? {
        let rows: [Config]? = try? await SupabaseProvider.shared
            .from("core_club_config")
            .select("seats,daily_bar_seconds,entry_window_days,entry_required_days,keep_window_days,keep_required_days,bonus_seconds")
            .execute()
            .value
        return rows?.first
    }

    /// Badges for a batch of persona owners, keyed by LOWERCASE user id.
    ///
    /// Goes through `core_badges_for`, not a table read: the badge is public
    /// but the membership LIST is not, so the server only answers about ids
    /// the caller already names (20260814150000). The club size the counter
    /// draws comes from `fetchProgress().club_size`, never from counting rows
    /// here.
    ///
    /// `uuid` columns come back lowercase while `UUID.uuidString` is
    /// uppercase — the same mismatch that once made `PublicPersonaService`
    /// insert a duplicate of the user on every launch. Both sides are folded
    /// here so a caller can't get it wrong.
    static func fetchBadges(ownerIds: [String]) async -> [String: Badge] {
        let ids = Set(ownerIds.map { $0.lowercased() })
        guard !ids.isEmpty else { return [:] }
        let rows: [Badge]? = try? await SupabaseProvider.shared
            .rpc("core_badges_for", params: ["p_user_ids": Array(ids)])
            .execute()
            .value
        return Dictionary(
            (rows ?? []).map { ($0.user_id.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Arrivals

    private static let lastSeenKey = "futurevoice.core.lastSeenEventId"

    /// Poll for arrivals and announce them locally.
    ///
    /// There is no push infrastructure (no APNs registration, no device-token
    /// table), so this is the honest version: the app notices on foreground
    /// and posts a LOCAL notification. It arrives late by design — when the
    /// learner next opens the app — which is fine while the 28/30 entry bar
    /// keeps arrivals to a handful a week. Wire APNs before that stops being
    /// true.
    ///
    /// First run records the high-water mark WITHOUT announcing: a fresh
    /// install must not dump the club's entire history onto the lock screen.
    static func announceArrivals() async {
        let defaults = UserDefaults.standard
        let lastSeen = defaults.object(forKey: lastSeenKey) as? Int

        let rows: [Event]? = try? await SupabaseProvider.shared
            .from("core_events")
            .select("id,kind,user_id,join_number,club_size,first_time")
            .in("kind", values: ["seated", "club_full"])
            .gt("id", value: lastSeen ?? 0)
            .order("id", ascending: true)
            .limit(200)
            .execute()
            .value
        guard let rows, let newest = rows.map(\.id).max() else { return }
        defaults.set(newest, forKey: lastSeenKey)
        guard lastSeen != nil else { return }   // first run: catch up silently

        let me = await myUserId()
        // A returning member slipping back into a seat is not an arrival, and
        // nobody gets told about their own.
        let arrivals = rows.filter {
            $0.kind == "seated" && $0.first_time && $0.user_id?.lowercased() != me
        }
        let full = rows.last { $0.kind == "club_full" }

        if let full {
            await post(
                title: chrome("The Core"),
                body: explain("The Core is full — all \(full.club_size) seats taken."),
                id: "core.full")
        }
        guard !arrivals.isEmpty else { return }

        // Coalesced: several arrivals in one poll are one line, not a pile.
        if arrivals.count > 1, let last = arrivals.last {
            await post(
                title: chrome("The Core"),
                body: explain("\(arrivals.count) new members joined — \(last.club_size) seats taken."),
                id: "core.arrivals.\(last.id)")
            return
        }

        guard let one = arrivals.first else { return }
        let name = await displayName(forOwner: one.user_id)
        let number = one.join_number ?? 0
        let body = name.map {
            explain("\($0) joined as member \(number) — \(one.club_size) seats taken.")
        } ?? explain("Member \(number) joined — \(one.club_size) seats taken.")
        await post(title: chrome("The Core"), body: body, id: "core.arrival.\(one.id)")
    }

    /// A member's published persona name, when they have one. Members who
    /// never published stay a number — the number is the payload anyway.
    private static func displayName(forOwner ownerId: String?) async -> String? {
        guard let ownerId else { return nil }
        struct Row: Decodable { let display_name: String }
        let rows: [Row]? = try? await SupabaseProvider.shared
            .from("public_personas")
            .select("display_name")
            .eq("owner_user_id", value: ownerId.lowercased())
            .limit(1)
            .execute()
            .value
        return rows?.first?.display_name
    }

    /// Quiet by construction: no sound, no time-sensitive level. The daily
    /// call is the habit anchor and must not be competed with.
    private static func post(title: String, body: String, id: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.threadIdentifier = "core.club"
        content.userInfo = ["kind": "core"]

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try? await center.add(request)
    }
}

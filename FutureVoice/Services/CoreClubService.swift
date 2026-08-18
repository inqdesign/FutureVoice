import Foundation
import UserNotifications

/// The Core — 100 seats held by learners who actually speak every day.
///
/// Two facts, deliberately separate (see `20260817140000_core_streak_entry.sql`):
///
///   * **Qualification** — 30 days IN A ROW over the daily bar. Break the
///     streak and it restarts at zero; there is no forgiveness on the way in,
///     which is the whole value of the badge. Earned once, granted the moment
///     it's done, and NEVER revoked. `qualifiedAt` is the permanent record.
///
///     Qualifying does NOT seat you. It puts you in the queue, in
///     qualification order, and you are seated when someone vacates — which
///     is what `queue_ahead` exists to say out loud.
///
///     There is no member NUMBER anywhere in this file any more. It existed,
///     and it was wrong: an ordinal that is never reused climbs past the seat
///     count forever, so a hundred-seat club ends up with a member #137 —
///     and once the club screen draws the hundred seats, that number is a
///     contradiction the learner has to be argued out of. It also quietly
///     reintroduced the rank the club was designed not to have. The server
///     still keeps `join_number` as its internal ordering key (seat order,
///     promotion tie-break); nothing reads it back to a person.
///   * **A seat** — kept by not missing more than one day per rolling 30. A
///     cold or a flight is free; two inside a month vacates the seat. A seat
///     is only ever vacated by its holder, never taken by a newcomer, so an
///     arrival is pure good news to the people already inside.
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
        let qualified_at: String
        let seated: Bool
        let seated_since: String?
        let days_total: Int

        /// Cumulative days seated across every stint. Stock — it survives
        /// losing the seat, which is what makes leaving a rest rather than a
        /// bankruptcy.
        var daysTotal: Int { days_total }
    }

    /// What a stranger is allowed to see next to someone's name: the seal,
    /// filled or not. Nothing else — never a number, never how much anyone
    /// talks. Rank decides who gets in; inside the club everyone is equal, and
    /// a number beside a name in a browsable list is a rank.
    struct Badge: Decodable {
        let user_id: String
        let seated: Bool
    }

    struct Config: Decodable {
        let seats: Int
        let daily_bar_seconds: Int
        let entry_window_days: Int
        let entry_required_days: Int
        let keep_window_days: Int
        let keep_required_days: Int
    }

    /// An arrival. Departures are not readable by clients at all — the RLS
    /// policy filters `kind = 'left'` out — so nobody can work out whose seat
    /// they took.
    struct Event: Decodable {
        let id: Int
        let kind: String
        let user_id: String?
        let club_size: Int
        let first_time: Bool
    }

    /// Everything the club screen needs, in one round trip, for the caller
    /// only. `core_daily_activity` is revoked from clients — this RPC is the
    /// only door, and it reads nobody else's days.
    struct Progress: Decodable {
        /// `core_my_progress` still puts a `join_number` in this object — it
        /// is the caller's own row and goes nowhere else, and rewriting a
        /// 180-line settlement-adjacent function to delete one key is risk
        /// bought for nothing. Simply never decoded; drop it there the next
        /// time that function is touched for another reason.
        struct Member: Decodable {
            let seated: Bool
            let days_total: Int
        }

        let bar_seconds: Int
        let seats: Int
        let club_size: Int
        let member: Member?

        /// Consecutive days over the daily bar, alive until today is over —
        /// today only breaks it at midnight, so this doesn't read 0 every
        /// morning. `entry_streak` is what it has to reach.
        let streak: Int
        let entry_streak: Int
        /// Missed days inside the keep window, and how many of them are
        /// forgiven. Only meaningful once seated; a challenger's streak
        /// already says everything.
        let missed_recent: Int
        let keep_grace: Int
        let keep_window: Int
        /// Qualified people ahead of you in this language's line. Nil unless
        /// you're qualified and seatless — the one state where it answers
        /// anything.
        let queue_ahead: Int?
        /// `entry_streak - streak`, from the server so the screen and the
        /// settlement can't disagree by a day. Nil once qualified.
        let days_to_entry: Int?
        /// Days until a seatless member is back over the keep bar.
        let days_to_return: Int?
        /// A long absence means the streak has to be run again.
        let requalifying: Bool
        /// Over the bar, badge held, waiting for someone to vacate.
        let waiting_for_seat: Bool

        /// Every field is optional AT THE WIRE, with a fallback.
        ///
        /// Synthesised `Decodable` treats a missing key as fatal for the whole
        /// object, so the club screen is only ever one server-side field
        /// removal away from showing "The Core is unavailable right now" to
        /// every already-installed build — which is exactly what happened when
        /// `bonus_seconds` left the payload. An app that can't render one row
        /// must not lose the other twenty.
        ///
        /// The fallbacks are the config's shipped defaults, so a degraded
        /// screen shows the rule this build was written against rather than a
        /// zero. Counts fall back to 0 because a count nobody sent is not a
        /// count we can guess.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func int(_ k: CodingKeys, _ fallback: Int) -> Int {
                (try? c.decodeIfPresent(Int.self, forKey: k)) .flatMap { $0 } ?? fallback
            }
            func opt(_ k: CodingKeys) -> Int? {
                (try? c.decodeIfPresent(Int.self, forKey: k)).flatMap { $0 }
            }
            func bool(_ k: CodingKeys) -> Bool {
                (try? c.decodeIfPresent(Bool.self, forKey: k)).flatMap { $0 } ?? false
            }
            bar_seconds     = int(.bar_seconds, 240)
            seats           = int(.seats, 100)
            club_size       = int(.club_size, 0)
            member          = try? c.decodeIfPresent(Member.self, forKey: .member)
            streak          = int(.streak, 0)
            entry_streak    = int(.entry_streak, 30)
            missed_recent   = int(.missed_recent, 0)
            keep_grace      = int(.keep_grace, 1)
            keep_window     = int(.keep_window, 30)
            queue_ahead     = opt(.queue_ahead)
            days_to_entry   = opt(.days_to_entry)
            days_to_return  = opt(.days_to_return)
            requalifying    = bool(.requalifying)
            waiting_for_seat = bool(.waiting_for_seat)
        }

        private enum CodingKeys: String, CodingKey {
            case bar_seconds, seats, club_size, member
            case streak, entry_streak, missed_recent, keep_grace, keep_window
            case queue_ahead, days_to_entry, days_to_return
            case requalifying, waiting_for_seat
        }
    }

    /// The hundred seats as colours: `themes[i]` is the palette worn by the
    /// member sitting in seat `i`, oldest first, and everything past `taken`
    /// is an empty seat. Deliberately carries no id, name or number — the room
    /// is drawable, its roster is not (`20260815120000_core_seat_map`).
    struct SeatMap: Decodable {
        let seats: Int
        let taken: Int
        let themes: [Int]
        /// Index of the caller's own seat, if they hold one.
        let mine: Int?

        /// Same rule as `Progress`: a missing key degrades the grid, it never
        /// deletes it. Falling back to 100 empty seats draws the room the app
        /// was built to draw.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seats  = (try? c.decodeIfPresent(Int.self, forKey: .seats)).flatMap { $0 } ?? 100
            taken  = (try? c.decodeIfPresent(Int.self, forKey: .taken)).flatMap { $0 } ?? 0
            themes = (try? c.decodeIfPresent([Int].self, forKey: .themes)).flatMap { $0 } ?? []
            mine   = (try? c.decodeIfPresent(Int.self, forKey: .mine)).flatMap { $0 }
        }

        private enum CodingKeys: String, CodingKey { case seats, taken, themes, mine }
    }

    /// Every read names its club. There is one Core PER TARGET LANGUAGE
    /// (`20260816120000_core_by_language`), so a call without a language is
    /// a call about nobody's club — the server rejects it rather than pick.
    static func fetchProgress(language: String) async -> Progress? {
        try? await SupabaseProvider.shared
            .rpc("core_my_progress", params: ["p_language": language])
            .execute()
            .value
    }

    static func fetchSeatMap(language: String) async -> SeatMap? {
        try? await SupabaseProvider.shared
            .rpc("core_seat_map", params: ["p_language": language])
            .execute()
            .value
    }

    /// Publish the palette this device wears, so the member's seat is drawn in
    /// their own colour on everyone else's grid.
    ///
    /// Fired on launch without checking membership first: a non-member's call
    /// updates nothing and fails at nothing, and the alternative is a
    /// round-trip to ask a question whose answer only ever suppresses a write
    /// that was already free.
    static func publishTheme(_ rawValue: Int) async {
        _ = try? await SupabaseProvider.shared
            .rpc("core_set_theme", params: ["p_theme": rawValue])
            .execute()
    }

    // MARK: - The rule, on-device

    /// The language whose club is being practised — the same value every Core
    /// read is scoped by. Read from defaults rather than passed in, for the
    /// reason `TalkMeter` does: this is consulted from several surfaces and a
    /// parameter is a thing one of them eventually forgets.
    static func activeLanguage() -> String {
        (UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en")
            .lowercased()
    }

    private static let barKey = "futurevoice.core.dailyBarSeconds"

    /// Seconds of talk that make a day count, mirrored from
    /// `core_club_config.daily_bar_seconds`.
    ///
    /// Cached because the streak is drawn on Home, in Activity, in Progress
    /// and in the widget — all of which must render offline and none of which
    /// can wait on a round trip. The default matches the shipped config, so a
    /// device that has never synced still applies the real rule.
    static func dailyBarSeconds() -> Int {
        let cached = UserDefaults.standard.integer(forKey: barKey)
        return cached > 0 ? cached : 240
    }

    /// Refresh the cached bar. Cheap, and safe to call on launch: a failure
    /// leaves the last known value in place rather than falling back to a
    /// guess mid-session.
    static func refreshDailyBar() async {
        guard let config = await fetchConfig() else { return }
        UserDefaults.standard.set(config.daily_bar_seconds, forKey: barKey)
    }

    // MARK: - Reads

    private static func myUserId() async -> String? {
        guard let id = try? await SupabaseProvider.shared.auth.session.user.id else { return nil }
        return id.uuidString.lowercased()
    }

    static func fetchMine(language: String) async -> Membership? {
        guard let uid = await myUserId() else { return nil }
        let rows: [Membership]? = try? await SupabaseProvider.shared
            .from("core_membership")
            .select("qualified_at,seated,seated_since,days_total")
            .eq("user_id", value: uid)
            .eq("language", value: language.lowercased())
            .execute()
            .value
        return rows?.first
    }

    static func fetchConfig() async -> Config? {
        let rows: [Config]? = try? await SupabaseProvider.shared
            .from("core_club_config")
            .select("seats,daily_bar_seconds,entry_window_days,entry_required_days,keep_window_days,keep_required_days")
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
    /// `language` is the pool being BROWSED, not the learner's own — Find
    /// people shows one language at a time, and a seal earned in another one
    /// says nothing about the person in front of you.
    private struct BadgeQuery: Encodable {
        let p_user_ids: [String]
        let p_language: String
    }

    static func fetchBadges(ownerIds: [String], language: String) async -> [String: Badge] {
        let ids = Set(ownerIds.map { $0.lowercased() })
        guard !ids.isEmpty else { return [:] }
        let rows: [Badge]? = try? await SupabaseProvider.shared
            .rpc("core_badges_for",
                 params: BadgeQuery(p_user_ids: Array(ids),
                                    p_language: language.lowercased()))
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
    /// learner next opens the app — which is fine while the entry bar
    /// keeps arrivals to a handful a week. Wire APNs before that stops being
    /// true.
    ///
    /// First run records the high-water mark WITHOUT announcing: a fresh
    /// install must not dump the club's entire history onto the lock screen.
    ///
    /// (The bar referred to above is now 30 consecutive days — arrivals are,
    /// if anything, rarer than they were under 28/30.)
    static func announceArrivals() async {
        let defaults = UserDefaults.standard
        let lastSeen = defaults.object(forKey: lastSeenKey) as? Int

        let rows: [Event]? = try? await SupabaseProvider.shared
            .from("core_events")
            .select("id,kind,user_id,club_size,first_time")
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
        let body = name.map {
            explain("\($0) joined the Core — \(one.club_size) seats taken.")
        } ?? explain("Someone joined the Core — \(one.club_size) seats taken.")
        await post(title: chrome("The Core"), body: body, id: "core.arrival.\(one.id)")
    }

    /// A member's published persona name, when they have one. Members who
    /// never published arrive unnamed — the seat count is the news either way.
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

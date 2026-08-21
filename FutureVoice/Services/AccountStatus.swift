import Foundation
import Supabase

/// Server-side account/billing snapshot for the Me tab. The edge functions
/// meter against `user_credits` / `user_subscriptions`; the client only
/// READS them for display — entitlement is never computed on-device.
extension Error {
    /// True when this failure is the server's 402 out-of-minutes gate (from
    /// either provider client). Screens use it to show the paywall instead
    /// of a retry that can never succeed. A subscriber's daily-cap 402 is
    /// deliberately NOT this — that user already paid.
    var isOutOfCredits: Bool {
        if let g = self as? GeminiError, case .insufficientCredits = g { return true }
        if let e = self as? ElevenLabsError, case .insufficientCredits = e { return true }
        return false
    }

    /// True when a SUBSCRIBER used up today's talk allowance. Screens raise
    /// `DailyAllowanceSheet` on this instead of the error alert: the day
    /// ending on schedule is the plan working, not a failure, and the word
    /// "credits" is wrong for an account that has already paid.
    var isDailyCapReached: Bool {
        if let e = self as? ElevenLabsError, case .dailyCapReached = e { return true }
        return false
    }

    /// Either spent-allowance wall — today's scenes or today's minutes. Both
    /// land on `DailyAllowanceSheet`, and neither is ever a paywall.
    var isDayCapped: Bool {
        if let e = self as? ElevenLabsError, case .sceneCapReached = e { return true }
        return isDailyCapReached
    }
}

struct AccountStatus {
    var email: String?
    /// SECONDS of talk left in the one-time free pool (the server's
    /// `user_credits.balance`, seconds-native since 2026-08). Not what
    /// entitles a subscriber — their plan buys a per-day allowance instead.
    var secondsBalance: Int
    var planId: String?
    var subscriptionStatus: String    // 'trialing' | 'active' | 'grace' | 'expired' | 'inactive'
    /// Admin/test accounts are charged for REAL but auto-reset when they'd
    /// overdraw (server-side), so their traffic measures true spend. The UI
    /// shows the live balance like anyone else's — watching it tick down IS
    /// the point — and only the wall-related nudges are dropped.
    var unlimited: Bool = false
    /// Seconds of metered audio spent SO FAR THIS BILLING PERIOD — the pool
    /// is monthly since 2026-08-20, so "today" is no longer a unit anything
    /// is measured in. From `talk_allowance()`.
    var secondsUsedPeriod: Int = 0
    /// The period's whole talk pool in seconds (`monthly_seconds`: 9000 on
    /// Light, 108000 on Plus, pro-rated during a trial). Nil for free users.
    var monthlyCapSeconds: Int?
    /// Watch scenes started this period, and the pool's size
    /// (`monthly_scenes`: 60 on Light, 600 on Plus). Nil cap = no
    /// entitlement, so scenes are still priced in seconds out of the balance
    /// and no count applies.
    var scenesUsedPeriod: Int = 0
    var monthlyScenesCap: Int?
    /// When this pool refills — the end of the billing period. Nil for free
    /// accounts, whose balance never refills at all.
    var periodEnd: Date?
    /// When the current billing period began. The usage receipt reads its
    /// ledger window from this: the pool is monthly, so a fixed 7-day window
    /// could never account for the month the header counts down from.
    var periodStart: Date?

    /// True while the subscription actually entitles (paid or in trial).
    var isEntitled: Bool {
        ["trialing", "active", "grace"].contains(subscriptionStatus)
    }

    /// In the 7-day trial. Metered at the LIGHT tier's pool PRO-RATED to the
    /// sample's length (7/30 ≈ 35 min) whatever plan is being trialed, so a
    /// week's trial can never spend a month's allowance.
    var isTrialing: Bool { subscriptionStatus == "trialing" }

    /// Signed up, no subscription, and nothing left in the pool — since the
    /// hard paywall there is no free tier, so this account simply cannot
    /// talk yet. (Cloning the voice and hearing it say hello stay free;
    /// they're the entry ticket, not usage.)
    var needsSubscription: Bool { !isEntitled && secondsBalance <= 0 && !unlimited }

    /// Seconds in the pool with no plan behind them: a one-time balance that
    /// spends like talk time but never refills.
    ///
    /// It stopped meaning "a beta tester's leftovers" on 2026-08-18, when
    /// referrals went live: `redeem_referral` credits the same
    /// `user_credits.balance`, so an invited user on day one lands here too.
    /// Nothing user-facing may say "beta" off the back of this flag — it
    /// would tell a brand-new account it had been testing.
    var hasLegacyPool: Bool { !isEntitled && secondsBalance > 0 }

    /// Entitled to the Light tier (plan ids `light_*`) — the one tier with
    /// something left to sell it, so every "offer the upgrade?" branch asks
    /// this. Deliberately does NOT include the admin `unlimited` flag: that
    /// account exists to watch real burn, so it sees what a free user sees.
    var isLightPlan: Bool {
        isEntitled && (planId?.hasPrefix("light") ?? false)
    }

    /// Entitled to the Plus tier (plan ids `plus_*`). Used to suppress the
    /// avatar's talk-time ring on Home: an hour a day is a pool this account
    /// will almost never approach, so the arc would sit near empty all month,
    /// and a gauge that never moves is decoration on the one tier that paid
    /// its way out of counting.
    ///
    /// Deliberately does NOT include the admin `unlimited` flag — that account
    /// exists to watch real burn, so it keeps the ring like everyone else.
    var isPlusPlan: Bool {
        isEntitled && (planId?.hasPrefix("plus") ?? false)
    }

    /// Scenes left in this period's pool.
    var scenesRemaining: Int {
        guard let cap = monthlyScenesCap else { return 0 }
        return max(0, cap - scenesUsedPeriod)
    }

    /// Seconds this account can still speak — what's left of this period's
    /// pool for subscribers, the one-time balance for everyone else.
    var secondsRemaining: Int {
        if isEntitled, let cap = monthlyCapSeconds {
            return max(0, cap - secondsUsedPeriod)
        }
        return max(0, secondsBalance)
    }

    /// Whole talk minutes remaining (floor of `secondsRemaining`).
    var minutesRemaining: Int {
        secondsRemaining / 60
    }

    /// The free tier's full tank — the signup grant (3960 s = 66 min).
    static let freeGrantSeconds = 3960
    /// The admin account's tank: the server auto-resets it to 6600 s
    /// (110 min) when it would overdraw, so that's what "full" means there.
    static let adminResetSeconds = 6600

    /// What a FULL ring means for this account, in seconds — set per account
    /// by `fetch()` (the period's pool for subscribers, the auto-reset value
    /// for admin, the signup grant otherwise). A hardcoded constant made the
    /// ring lie for any account with a bigger tank.
    var fullTankSeconds: Int = freeGrantSeconds

    /// 0…1 fraction of the tank remaining (clamped — referral bonuses can
    /// push a free balance past the reference; a full tank is the right
    /// story there). For subscribers the "tank" is this period's pool.
    var talkTimeFraction: Double {
        min(1, max(0, Double(secondsRemaining) / Double(max(1, fullTankSeconds))))
    }

    /// 0…1 fraction of the tank USED — what the avatar ring draws: a fresh
    /// tank is an empty ring, and the arc grows clockwise from 12 o'clock as
    /// minutes are spent, like an activity gauge filling up.
    var talkTimeUsedFraction: Double {
        1 - talkTimeFraction
    }

    /// The tank in whole minutes — the denominator the learner needs to read
    /// the ring: "58 min left" is meaningless without "of 66".
    var tankMinutes: Int {
        max(1, fullTankSeconds / 60)
    }

    /// The tier's own name, localized. Tier names say SIZE, not rank — the
    /// plans differ only in how much they buy — and they must not grade the
    /// buyer, which is why they aren't Light/Heavy (see PaywallView).
    /// Keyed, not literal: "Light" is also the appearance mode, and a catalog
    /// keyed by English text would give both one translation (see
    /// `explain(key:default:)`).
    static func tierName(_ planId: String?) -> String {
        (planId?.hasPrefix("plus") ?? false)
            ? explain(key: "plan.tier.plus", default: "Plus")
            : explain(key: "plan.tier.light", default: "Light")
    }

    /// "Free", or "Light · Monthly" while the subscription actually entitles.
    var planLabel: String {
        if unlimited { return "Admin" }
        guard isEntitled, let planId else {
            // No free tier since the hard paywall: an account without a
            // subscription is either spending a one-time pool (beta
            // leftovers, or an invite bonus) or hasn't started. Both are
            // "no plan yet" — the pool is a balance, not a tier.
            return hasLegacyPool ? explain("Free minutes") : explain("No plan")
        }
        let name = Self.tierName(planId)
        // The trial is metered as Light whatever plan is being trialed, so
        // naming the trialed plan's tier here would promise the wrong size.
        if isTrialing { return explain("\(name) trial") }
        switch planId.split(separator: "_").dropFirst().first {
        case "annual":  return "\(name) · " + explain("Annual")
        case "monthly": return "\(name) · " + explain("Monthly")
        default:        return name
        }
    }

    /// Balance for display, in talk minutes. Admin included: the number
    /// cycles down and back up, and seeing it move is how the owner gauges
    /// real burn.
    var balanceLabel: String {
        "\(minutesRemaining)"
    }

    /// Minutes of metered audio spent this period.
    var minutesUsedPeriod: Int { secondsUsedPeriod / 60 }

    /// When the pool refills, as a short date ("9월 14일"). Empty when there
    /// is nothing to refill.
    ///
    /// Formatted in the LEARNER's language, not the device's — `.formatted()`
    /// reads `Locale.current` and would print "Sep 14" inside an otherwise
    /// Korean sentence.
    var renewalLabel: String {
        guard let periodEnd else { return "" }
        return periodEnd.formatted(.dateTime.month(.abbreviated).day()
            .locale(Locale(identifier: LanguageCatalog.currentNative)))
    }

    /// The one-line read of talk time for the settings row and the usage
    /// page header.
    ///
    /// Every case must READ differently, not just count differently — whether
    /// the number refills is the thing a learner most needs to know, and one
    /// shared "N of M" shape hid exactly that. Both plans now show the
    /// denominator: Plus is no longer sold as unlimited, so hiding its size
    /// would be the same concealment the rename was made to end.
    var talkTimeLabel: String {
        if unlimited { return explain("\(minutesRemaining) min left") }
        if isEntitled {
            return explain("\(minutesRemaining) of \(tankMinutes) min left this month")
        }
        if hasLegacyPool {
            // A one-time pool with nothing to refill toward, so no
            // denominator. Says nothing about where it came from — beta
            // leftovers and an invite bonus are the same balance.
            return explain("\(minutesRemaining) min of talk left")
        }
        // Hard paywall — there is no free tier to count down from.
        return explain("No talk time yet")
    }

    /// Below this, the plan card turns orange and nudges toward an upgrade.
    /// Free users only — a subscriber's pool refills with the billing period,
    /// so nudging a paying user toward money is wrong.
    var isLowBalance: Bool { !unlimited && !isEntitled && secondsBalance <= 300 }

    static let empty = AccountStatus(email: nil, secondsBalance: 0,
                                     planId: nil, subscriptionStatus: "inactive")

    /// Best-effort fetch — billing display should never block or break the
    /// Me tab, so every failure degrades to the empty snapshot.
    static func fetch() async -> AccountStatus {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            return .empty
        }
        var out = AccountStatus.empty
        out.email = session.user.email
        let userId = session.user.id.uuidString

        struct CreditRow: Decodable { let balance: Int; let unlimited: Bool? }
        if let rows: [CreditRow] = try? await SupabaseProvider.shared
            .from("user_credits")
            .select("balance,unlimited")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value {
            out.secondsBalance = rows.first?.balance ?? 0
            out.unlimited = rows.first?.unlimited ?? false
        }

        struct SubRow: Decodable {
            let plan_id: String?
            let status: String
        }
        if let rows: [SubRow] = try? await SupabaseProvider.shared
            .from("user_subscriptions")
            .select("plan_id,status")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value,
           let row = rows.first {
            out.planId = row.plan_id
            out.subscriptionStatus = row.status
        }

        if out.unlimited { out.fullTankSeconds = adminResetSeconds }

        // This period's pools, from the ONE functions the meters themselves
        // use. They used to be computed here — plan row + a raw
        // `tts_char_pool` read — which was fine while a cap was a single
        // column and stopped being fine the moment it was derived: two
        // implementations of the number the learner is shown can only drift.
        struct AllowanceRow: Decodable {
            let used: Int
            let cap: Int?
            let period_start: String?
            let period_end: String?
        }
        if let talk: AllowanceRow = try? await SupabaseProvider.shared
            .rpc("talk_allowance")
            .execute()
            .value {
            out.secondsUsedPeriod = talk.used
            out.monthlyCapSeconds = talk.cap
            out.periodStart = talk.period_start.flatMap(Self.day(from:))
            out.periodEnd = talk.period_end.flatMap(Self.day(from:))
            if !out.unlimited, let cap = talk.cap { out.fullTankSeconds = cap }
        }

        // This period's Watch allowance, so the count can be shown before a
        // scene starts rather than as a surprise mid-playback.
        if let scenes: AllowanceRow = try? await SupabaseProvider.shared
            .rpc("scene_allowance")
            .execute()
            .value {
            out.scenesUsedPeriod = scenes.used
            out.monthlyScenesCap = scenes.cap
        }
        return out
    }

    /// `period_end` arrives as a bare `yyyy-MM-dd` from Postgres.
    private static func day(from raw: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }
}

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
    /// Seconds of metered audio (talk + Watch scenes) consumed TODAY —
    /// what's been used of a subscriber's daily allowance. From the
    /// server's per-day pool; 0 when nothing ran today.
    var secondsUsedToday: Int = 0
    /// The plan's per-day allowance in seconds (300 for Daily, 3600 for
    /// Unlimited), from `subscription_plans.daily_seconds`. Nil for free
    /// users.
    var dailyCapSeconds: Int?

    /// True while the subscription actually entitles (paid or in trial).
    var isEntitled: Bool {
        ["trialing", "active", "grace"].contains(subscriptionStatus)
    }

    /// The Daily plan's allowance, minutes per day. Keep in sync with the
    /// plan catalog copy (PaywallView "about five minutes of talk a day")
    /// and the pro tier's `subscription_plans.daily_seconds`.
    static let dailyPlanMinutes = 5

    /// Entitled to the Daily tier (plan ids `daily_*`) — the plan whose daily
    /// allowance doubles as the day's talk goal: the home ring's target
    /// becomes the 5 minutes the plan buys, so "goal met" and "today's
    /// minutes used" are the same event instead of two competing numbers.
    var isDailyPlan: Bool {
        isEntitled && (planId?.hasPrefix("daily") ?? false)
    }

    /// Entitled to the Unlimited tier (plan ids `unlimited_*`). These accounts
    /// never see a minutes target: a goal number next to "Unlimited" reads
    /// as a cap, so the home ring's text counts UP instead ("12 min today",
    /// no "of N"). Deliberately does NOT include the admin `unlimited` flag —
    /// that account exists to watch real burn, so it sees what a free user
    /// sees (avatar ring included).
    var isUnlimitedPlan: Bool {
        isEntitled && (planId?.hasPrefix("unlimited") ?? false)
    }

    /// Seconds this account can still speak — today's allowance remainder
    /// for subscribers, the one-time pool for everyone else.
    var secondsRemaining: Int {
        if isEntitled, let cap = dailyCapSeconds {
            return max(0, cap - secondsUsedToday)
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
    /// by `fetch()` (daily allowance for subscribers, the auto-reset value
    /// for admin, the signup grant otherwise). A hardcoded constant made the
    /// ring lie for any account with a bigger tank.
    var fullTankSeconds: Int = freeGrantSeconds

    /// 0…1 fraction of the tank remaining (clamped — referral bonuses can
    /// push a free balance past the reference; a full tank is the right
    /// story there). For subscribers the "tank" is today's allowance.
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

    /// "Free", or "Daily Monthly" / "Unlimited Annual" while the
    /// subscription actually entitles. Tier names are usage amounts, not
    /// feature ranks — the plans differ only in how much talk time they buy.
    var planLabel: String {
        if unlimited { return "Admin" }
        guard isEntitled, let planId else { return "Free" }
        let parts = planId.split(separator: "_")
        let tier = parts.first.map(String.init) ?? planId
        let name = tier.capitalized    // 'daily' → "Daily", 'unlimited' → "Unlimited"
        let period = parts.dropFirst().first?.capitalized ?? ""
        return period.isEmpty ? name : "\(name) \(period)"
    }

    /// Balance for display, in talk minutes. Admin included: the number
    /// cycles down and back up, and seeing it move is how the owner gauges
    /// real burn.
    var balanceLabel: String {
        "\(minutesRemaining)"
    }

    /// Below this, the plan card turns orange and nudges toward an upgrade.
    /// Free users only — a subscriber's allowance refills at midnight, so
    /// nudging a paying user toward money is wrong.
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

        // Tank size for the avatar ring: what "full" means for THIS account.
        struct PlanRow: Decodable { let daily_seconds: Int? }
        if out.unlimited {
            out.fullTankSeconds = adminResetSeconds
        } else if out.isEntitled, let planId = out.planId,
                  let plans: [PlanRow] = try? await SupabaseProvider.shared
                      .from("subscription_plans")
                      .select("daily_seconds")
                      .eq("id", value: planId)
                      .limit(1)
                      .execute()
                      .value,
                  let cap = plans.first?.daily_seconds {
            out.dailyCapSeconds = cap
            out.fullTankSeconds = cap
        }

        // Today's metered seconds (talk + Watch scenes) — the per-day pool
        // the server accumulates into, owner-readable via RLS.
        struct PoolRow: Decodable { let chars: Int }
        if let rows: [PoolRow] = try? await SupabaseProvider.shared
            .from("tts_char_pool")
            .select("chars")
            .eq("user_id", value: userId)
            .eq("day", value: Self.utcDayString())
            .in("action", values: ["talk_seconds", "scene_seconds"])
            .execute()
            .value {
            out.secondsUsedToday = rows.reduce(0) { $0 + $1.chars }
        }
        return out
    }

    /// The server pools per `current_date` in UTC — mirror that exactly or
    /// the "today" query misses around midnight.
    private static func utcDayString() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

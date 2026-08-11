import Foundation
import Supabase

/// Server-side account/billing snapshot for the Me tab. The edge functions
/// charge against `user_credits` / `user_subscriptions`; the client only
/// READS them for display — entitlement is never computed on-device.
extension Error {
    /// True when this failure is the server's 402 credit gate (from either
    /// provider client). Screens use it to show the paywall instead of a
    /// retry that can never succeed.
    var isOutOfCredits: Bool {
        if let g = self as? GeminiError, case .insufficientCredits = g { return true }
        if let e = self as? ElevenLabsError, case .insufficientCredits = e { return true }
        return false
    }
}

struct AccountStatus {
    var email: String?
    var creditBalance: Int
    var planId: String?
    var subscriptionStatus: String    // 'trialing' | 'active' | 'grace' | 'expired' | 'inactive'
    /// Admin/test accounts are charged for REAL but auto-reset to 500 when
    /// they'd overdraw (server-side), so their traffic measures true spend.
    /// The UI shows the live balance like anyone else's — watching it tick
    /// down IS the point — and only the wall-related nudges are dropped.
    var unlimited: Bool = false

    /// True while the subscription actually entitles (paid or in trial).
    var isEntitled: Bool {
        ["trialing", "active", "grace"].contains(subscriptionStatus)
    }

    /// The Daily plan's allowance, minutes per day. Keep in sync with the
    /// plan catalog copy (PaywallView "about five minutes of talk a day").
    static let dailyPlanMinutes = 5

    /// Entitled to the Daily tier (plan ids `pro_*`) — the plan whose daily
    /// allowance doubles as the day's talk goal: the home ring's target
    /// becomes the 5 minutes the plan buys, so "goal met" and "today's
    /// minutes used" are the same event instead of two competing numbers.
    var isDailyPlan: Bool {
        isEntitled && (planId?.hasPrefix("pro") ?? false)
    }

    /// Entitled to the Unlimited tier (plan ids `premium_*`). These accounts
    /// never see a minutes target: a goal number next to "Unlimited" reads
    /// as a cap, so the home ring's text counts UP instead ("12 min today",
    /// no "of N"). Deliberately does NOT include the admin `unlimited` flag —
    /// that account exists to watch real burn, so it sees what a free user
    /// sees (avatar ring included).
    var isUnlimitedPlan: Bool {
        isEntitled && (planId?.hasPrefix("premium") ?? false)
    }

    /// Server credit units per displayed talk minute — must mirror
    /// `charge_talk_seconds` (4.5 credits / 60 s). Everything user-facing
    /// speaks in minutes; credits stay a server-internal unit.
    static let creditsPerMinute = 4.5

    /// Whole talk minutes the balance still buys (floor).
    var minutesRemaining: Int {
        max(0, Int(Double(creditBalance) / Self.creditsPerMinute))
    }

    /// The free tier's full tank — the beta signup grant (300 credits ≈ 66
    /// min).
    static let freeGrantCredits = 300
    /// The admin account's tank: the server auto-resets it to 500 when it
    /// would overdraw, so 500 is what "full" means there.
    static let adminResetCredits = 500

    /// What a FULL ring means for this account, in credits — set per account
    /// by `fetch()` (plan cycle grant for subscribers, 500 for admin, the
    /// signup grant otherwise). A hardcoded 300 made the ring lie for any
    /// account with a bigger tank.
    var fullTankCredits: Int = freeGrantCredits

    /// 0…1 fraction of the tank remaining (clamped — referral bonuses can
    /// push the balance past the reference; a full tank is the right story
    /// there).
    var talkTimeFraction: Double {
        min(1, max(0, Double(creditBalance) / Double(max(1, fullTankCredits))))
    }

    /// 0…1 fraction of the tank USED — what the avatar ring draws: a fresh
    /// tank is an empty ring, and the arc grows clockwise from 12 o'clock as
    /// minutes are spent, like an activity gauge filling up.
    var talkTimeUsedFraction: Double {
        1 - talkTimeFraction
    }

    /// "Free", or "Daily Monthly" / "Unlimited Annual" while the
    /// subscription actually entitles. Tier names are usage amounts, not
    /// feature ranks — the plans differ only in how much talk time they buy.
    var planLabel: String {
        if unlimited { return "Admin" }
        guard isEntitled, let planId else { return "Free" }
        let parts = planId.split(separator: "_")
        let tier = parts.first.map(String.init) ?? planId
        let name = tier == "premium" ? "Unlimited"
                 : tier == "pro" ? "Daily"
                 : tier.capitalized
        let period = parts.dropFirst().first?.capitalized ?? ""
        return period.isEmpty ? name : "\(name) \(period)"
    }

    /// Balance for display, in talk minutes. Admin included: the number
    /// cycles down and back up, and seeing it move is how the owner gauges
    /// real burn.
    var balanceLabel: String {
        "\(minutesRemaining)"
    }

    /// Below this, the plan card turns orange and nudges toward a top-up.
    var isLowBalance: Bool { !unlimited && creditBalance <= 20 }

    static let empty = AccountStatus(email: nil, creditBalance: 0,
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
            out.creditBalance = rows.first?.balance ?? 0
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
        struct PlanRow: Decodable { let credits_per_cycle: Int }
        if out.unlimited {
            out.fullTankCredits = adminResetCredits
        } else if out.isEntitled, let planId = out.planId,
                  let plans: [PlanRow] = try? await SupabaseProvider.shared
                      .from("subscription_plans")
                      .select("credits_per_cycle")
                      .eq("id", value: planId)
                      .limit(1)
                      .execute()
                      .value,
                  let plan = plans.first {
            out.fullTankCredits = plan.credits_per_cycle
        }
        return out
    }
}

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
    /// Admin/test accounts never spend — the balance is cosmetic. UI shows
    /// "Unlimited" and drops the low-balance nudge.
    var unlimited: Bool = false

    /// True while the subscription actually entitles (paid or in trial).
    var isEntitled: Bool {
        ["trialing", "active", "grace"].contains(subscriptionStatus)
    }

    /// "Free", or "Pro Monthly" while the subscription actually entitles.
    var planLabel: String {
        if unlimited { return "Admin" }
        guard isEntitled, let planId else { return "Free" }
        return planId.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    /// Balance for display — "Unlimited" for admin, else the number.
    var balanceLabel: String {
        unlimited ? "Unlimited" : "\(creditBalance)"
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
        return out
    }
}

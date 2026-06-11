import Foundation
import Supabase

/// Server-side account/billing snapshot for the Me tab. The edge functions
/// charge against `user_credits` / `user_subscriptions`; the client only
/// READS them for display — entitlement is never computed on-device.
struct AccountStatus {
    var email: String?
    var creditBalance: Int
    var planId: String?
    var subscriptionStatus: String    // 'trialing' | 'active' | 'grace' | 'expired' | 'inactive'

    /// "Free", or "Pro Monthly" while the subscription actually entitles.
    var planLabel: String {
        let entitled = ["trialing", "active", "grace"].contains(subscriptionStatus)
        guard entitled, let planId else { return "Free" }
        return planId.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

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

        struct CreditRow: Decodable { let balance: Int }
        if let rows: [CreditRow] = try? await SupabaseProvider.shared
            .from("user_credits")
            .select("balance")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value {
            out.creditBalance = rows.first?.balance ?? 0
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

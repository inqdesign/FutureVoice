import Foundation
import Supabase

/// Beta invite system. Each user has a shareable code; redeeming someone's
/// code grants +500 credits to BOTH sides (inviter rewarded for up to 10
/// invites). All credit math happens server-side in `redeem_referral`.
struct ReferralStatus {
    var code: String?
    var invitesUsed: Int          // how many people joined with my code
    static let empty = ReferralStatus(code: nil, invitesUsed: 0)
}

@MainActor
enum ReferralService {
    /// My own code + how many friends have redeemed it. Best-effort.
    static func fetchMine() async -> ReferralStatus {
        guard let session = try? await SupabaseProvider.shared.auth.session else { return .empty }
        let uid = session.user.id.uuidString
        var out = ReferralStatus.empty

        struct CodeRow: Decodable { let code: String }
        if let rows: [CodeRow] = try? await SupabaseProvider.shared
            .from("referral_codes")
            .select("code")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value {
            out.code = rows.first?.code
        }

        if let resp = try? await SupabaseProvider.shared
            .from("referral_redemptions")
            .select("invitee_id", head: true, count: .exact)
            .eq("inviter_id", value: uid)
            .execute() {
            out.invitesUsed = resp.count ?? 0
        }
        return out
    }

    enum RedeemError: LocalizedError {
        case invalid, alreadyRedeemed, selfReferral, unknown
        var errorDescription: String? {
            switch self {
            case .invalid:         return "That invite code isn't valid."
            case .alreadyRedeemed: return "You've already redeemed a code."
            case .selfReferral:    return "You can't redeem your own code."
            case .unknown:         return "Couldn't redeem that code. Try again."
            }
        }
    }

    private struct RedeemResult: Decodable {
        let balance: Int
        let invitee_bonus: Int
        let inviter_rewarded: Bool
    }

    /// Redeem a friend's code. Returns the new credit balance. Throws a
    /// `RedeemError` mapped from the server-side guard that fired.
    @discardableResult
    static func redeem(code: String) async throws -> Int {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let result: RedeemResult = try await SupabaseProvider.shared
                .rpc("redeem_referral", params: ["p_code": clean])
                .execute()
                .value
            return result.balance
        } catch let error as RedeemError {
            throw error
        } catch {
            let msg = String(describing: error)
            if msg.contains("ALREADY_REDEEMED") { throw RedeemError.alreadyRedeemed }
            if msg.contains("SELF_REFERRAL")    { throw RedeemError.selfReferral }
            if msg.contains("INVALID_CODE")     { throw RedeemError.invalid }
            throw RedeemError.unknown
        }
    }
}

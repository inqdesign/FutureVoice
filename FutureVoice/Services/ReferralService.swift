import Foundation
import Supabase

/// Invite system. Each user has a shareable code; redeeming someone's code
/// grants talk time to BOTH sides (inviter rewarded for up to 10 invites).
/// All grant math happens server-side in `redeem_referral`.
struct ReferralStatus {
    var code: String?
    var invitesUsed: Int          // how many people joined with my code
    /// The code THIS account joined with, nil if it never used one. A code
    /// is one-time per account (`referral_redemptions.invitee_id` is the
    /// primary key), so this is what decides whether asking for one is a
    /// real offer or a dead box.
    var redeemedCode: String?
    var hasRedeemed: Bool { redeemedCode != nil }
    static let empty = ReferralStatus(code: nil, invitesUsed: 0, redeemedCode: nil)
}

@MainActor
enum ReferralService {
    /// Seconds granted to BOTH sides by `redeem_referral` — mirrors the
    /// server (1800 s = 30 min since `20260818100000_referral_thirty_minutes`).
    /// Change one without the other and every number on the invite page lies.
    static let bonusSeconds = 1800
    static var bonusMinutes: Int { bonusSeconds / 60 }
    /// The inviter is rewarded for their first 10 redemptions; after that a
    /// friend still gets theirs.
    static let rewardedInviteCap = 10

    /// My own code, how many friends have redeemed it, and the code I joined
    /// with. Best-effort.
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

        struct RedemptionRow: Decodable { let code: String }
        if let rows: [RedemptionRow] = try? await SupabaseProvider.shared
            .from("referral_redemptions")
            .select("code")
            .eq("invitee_id", value: uid)
            .limit(1)
            .execute()
            .value {
            out.redeemedCode = rows.first?.code
        }
        return out
    }

    enum RedeemError: LocalizedError {
        case invalid, alreadyRedeemed, selfReferral, unknown
        var errorDescription: String? {
            switch self {
            case .invalid:         return explain("That invite code isn't valid.")
            case .alreadyRedeemed: return explain("You've already used a code.")
            case .selfReferral:    return explain("You can't use your own code.")
            case .unknown:         return explain("Couldn't redeem that code. Try again.")
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

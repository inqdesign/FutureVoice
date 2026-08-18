import Foundation
import Supabase
import UserNotifications

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

    // MARK: - Friends joining (the inviter's side)

    private static let lastSeenJoinKey = "futurevoice.referral.lastSeenJoinAt"

    /// Poll for friends who joined with my code, and announce them.
    ///
    /// Same shape as `CoreClubService.announceArrivals`, for the same reason:
    /// there is no push infrastructure, so the app notices on foreground and
    /// posts a LOCAL notification plus an in-app sheet. The learner gave
    /// someone a code and then heard nothing back — the grant landed silently
    /// in a balance they had no reason to look at.
    ///
    /// First run records the high-water mark WITHOUT announcing: a fresh
    /// install must not replay every friend who ever joined.
    static func announceJoins() async {
        guard let session = try? await SupabaseProvider.shared.auth.session else { return }
        let uid = session.user.id.uuidString
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: lastSeenJoinKey)

        struct JoinRow: Decodable {
            let invitee_id: String
            let created_at: String
        }
        // The whole list, oldest first: a row's RANK is what decides whether
        // it paid (the server rewards the first `rewardedInviteCap`), and
        // that can't be read off the new rows alone.
        guard let rows: [JoinRow] = try? await SupabaseProvider.shared
            .from("referral_redemptions")
            .select("invitee_id,created_at")
            .eq("inviter_id", value: uid)
            .order("created_at", ascending: true)
            .limit(200)
            .execute()
            .value,
              let newest = rows.last?.created_at
        else { return }

        defaults.set(newest, forKey: lastSeenJoinKey)
        guard let lastSeen else { return }        // first run: catch up silently

        // Postgres timestamps come back in one format from one source, so a
        // string compare is a date compare here.
        let fresh = rows.enumerated().filter { $0.element.created_at > lastSeen }
        guard !fresh.isEmpty else { return }

        let paid = fresh.filter { $0.offset < rewardedInviteCap }.count
        let minutes = paid * bonusMinutes
        let name = fresh.count == 1 ? await displayName(forOwner: fresh[0].element.invitee_id) : nil

        let join = ReferralJoin(id: fresh.last!.element.invitee_id,
                                friendName: name,
                                friendsJoined: fresh.count,
                                totalJoined: rows.count,
                                minutesEarned: minutes)
        ReferralInbox.shared.pendingJoin = join
        await post(title: chrome("nawana"), body: join.notificationBody, id: "referral.join.\(join.id)")
    }

    /// The friend's published persona name, when they have one. Someone who
    /// never published stays unnamed — that they joined is the news either way.
    private static func displayName(forOwner ownerId: String) async -> String? {
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
        content.threadIdentifier = "referral"
        content.userInfo = ["kind": "referral"]

        try? await center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}

/// One announcement: friends who joined with my code since the last look.
struct ReferralJoin: Identifiable, Equatable {
    /// The newest invitee's id — stable, so a re-poll can't double-notify.
    let id: String
    /// Named only when a single friend joined AND they published a persona.
    let friendName: String?
    let friendsJoined: Int
    let totalJoined: Int
    /// 0 once past the reward cap — a friend still gets theirs, and saying
    /// "you earned 30 minutes" when nothing landed is the one thing this
    /// screen must never do.
    let minutesEarned: Int

    var notificationBody: String {
        if minutesEarned == 0 {
            return friendsJoined == 1
                ? explain("A friend joined with your code.")
                : explain("\(friendsJoined) friends joined with your code.")
        }
        if let friendName {
            return explain("\(friendName) joined with your code — \(minutesEarned) minutes are yours.")
        }
        return friendsJoined == 1
            ? explain("A friend joined with your code — \(minutesEarned) minutes are yours.")
            : explain("\(friendsJoined) friends joined with your code — \(minutesEarned) minutes are yours.")
    }
}

/// Hand-off for the sheet, same shape as `DailyCallInbox`: the poll runs
/// wherever the app happens to be, and `RootTabView` presents from here.
@MainActor
final class ReferralInbox: ObservableObject {
    static let shared = ReferralInbox()
    @Published var pendingJoin: ReferralJoin?
}

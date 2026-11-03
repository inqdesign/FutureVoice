import Foundation

/// The one free recharge after the free minutes (2026-11-03, founder: the
/// trial continues, without a store trial). The trial report's last card
/// offers "Recharge N min free" beside "Subscribe"; one tap, once per
/// account, and the learner talks on. The second wall meets the plans.
///
/// Both answers come from the server (`20261103150000_free_recharge`): the
/// amount is `billing_config.free_recharge_seconds`, so the founder can
/// change or remove it without a build, and whether THIS account may take
/// it (never subscribed, not unlimited, pool spent, not yet claimed) is
/// decided where the grant is made. The app draws the button only on a
/// fresh `available`, never from a cached or guessed answer.
enum FreeRecharge {
    struct Offer: Decodable {
        let seconds: Int
        let available: Bool
        let reason: String?
    }

    struct Claim: Decodable {
        let applied: Bool
        let reason: String?
        let seconds: Int
        let balance: Int
    }

    /// Nil = couldn't ask (offline, signed out). The card then shows
    /// Subscribe alone, which is what every build before this showed.
    static func offer() async -> Offer? {
        #if DEBUG
        // `-trialrecharge 1`: draw the two buttons in a capture run, which
        // is signed out and would otherwise get no offer.
        if UserDefaults.standard.bool(forKey: "trialrecharge") {
            return Offer(seconds: 1200, available: true, reason: nil)
        }
        #endif
        return try? await SupabaseProvider.shared
            .rpc("free_recharge_offer")
            .execute()
            .value
    }

    /// Grants the recharge, or says why not. A repeat tap gets
    /// `applied: false, reason: "claimed"` and the same balance.
    static func claim() async throws -> Claim {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "trialrecharge") {
            return Claim(applied: true, reason: nil, seconds: 1200, balance: 1200)
        }
        #endif
        return try await SupabaseProvider.shared
            .rpc("claim_free_recharge")
            .execute()
            .value
    }
}

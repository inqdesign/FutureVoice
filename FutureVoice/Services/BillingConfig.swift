import Foundation

/// The free offer as the server sets it (`public.billing_config`,
/// 20261021120000), so the founder can change it without a build:
/// how many free minutes a new account starts with (0 = none), and where the
/// store's free trial is offered when one is switched on
/// (`scripts/billing-switch.py`).
///
/// Read once per foreground and mirrored into defaults, so a launch with no
/// network is a launch behind rather than snapped back to the build's own
/// numbers. The fallbacks ARE the offer as it stood when this shipped.
enum BillingConfig {
    enum TrialOfferAt: String {
        /// The plans meet the learner when the free minutes run out.
        case afterFree = "after_free"
        /// Once, right after onboarding, to a new account that has never
        /// subscribed — only while the store actually has a trial on.
        case onboarding
    }

    private static let freeKey = "futurevoice.billing.freeTalkSeconds"
    private static let offerKey = "futurevoice.billing.trialOfferAt"

    /// What a new account starts with. The ring's "full" for a free account
    /// and the trial report's "your first N minutes" read this.
    static var freeTalkSeconds: Int {
        UserDefaults.standard.object(forKey: freeKey) as? Int ?? 1200
    }

    static var trialOfferAt: TrialOfferAt {
        UserDefaults.standard.string(forKey: offerKey).flatMap(TrialOfferAt.init) ?? .afterFree
    }

    private static let trialKey = "futurevoice.billing.trialTalkSeconds"

    /// What a trial may talk in all, when the server sets it
    /// (20261022120000). Nil = the old rule, Light's month × 7/30, which the
    /// paywall computes from the catalog itself.
    static var trialTalkSeconds: Int? {
        UserDefaults.standard.object(forKey: trialKey) as? Int
    }

    // MARK: - The trial, offered right after onboarding

    private static let offeredKey = "futurevoice.billing.onboardingTrialOffered"

    /// Whether to offer the store's trial now, once, at the end of the
    /// first-run sheets. Every clause is a way the offer would be wrong:
    /// the setting says so; this install hasn't been offered it; the account
    /// is new (under two days — a setting flipped later must not pop the plans
    /// at everyone who has used the app for a month); the account has never
    /// subscribed; and the store really has a trial this Apple ID can take
    /// (the paywall draws the trial only then, so without one this would be a
    /// bare paywall in onboarding, which is not what the switch means).
    @MainActor
    static func onboardingTrialIsDue() async -> Bool {
        guard trialOfferAt == .onboarding,
              !UserDefaults.standard.bool(forKey: offeredKey),
              let user = SupabaseProvider.shared.auth.currentSession?.user,
              !user.isAnonymous,
              Date().timeIntervalSince(user.createdAt) < 2 * 86_400 else { return false }
        let account = await AccountStatus.fetch()
        guard account.ownershipKnown, account.subscriptionStatus == "inactive",
              !account.unlimited else { return false }
        let store = StoreKitService()
        await store.load()
        return store.trialEligible
    }

    static func markOnboardingTrialOffered() {
        UserDefaults.standard.set(true, forKey: offeredKey)
    }

    /// Every foreground. A failed read keeps what was mirrored last.
    static func refresh() async {
        struct Row: Decodable {
            let free_talk_seconds: Int
            let trial_offer_at: String
        }
        guard let rows: [Row] = try? await SupabaseProvider.shared
            .from("billing_config")
            .select("free_talk_seconds,trial_offer_at")
            .limit(1)
            .execute()
            .value,
              let row = rows.first else { return }
        if (0...36_000).contains(row.free_talk_seconds) {
            UserDefaults.standard.set(row.free_talk_seconds, forKey: freeKey)
        }
        // An unknown value from a newer server is dropped, not guessed at.
        if TrialOfferAt(rawValue: row.trial_offer_at) != nil {
            UserDefaults.standard.set(row.trial_offer_at, forKey: offerKey)
        }

        // Its own query: a column the database hasn't got yet fails the whole
        // select, and must cost this number, not the two above.
        struct TrialRow: Decodable { let trial_talk_seconds: Int? }
        if let trial: [TrialRow] = try? await SupabaseProvider.shared
            .from("billing_config")
            .select("trial_talk_seconds")
            .limit(1)
            .execute()
            .value, let first = trial.first {
            if let seconds = first.trial_talk_seconds, (0...36_000).contains(seconds) {
                UserDefaults.standard.set(seconds, forKey: trialKey)
            } else {
                UserDefaults.standard.removeObject(forKey: trialKey)
            }
        }
    }
}

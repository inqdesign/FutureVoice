import Foundation

/// Single switch for the closed-beta phase. During the beta:
///   - there is no purchasable subscription, so the paywall can't sell — it
///     ends in a subscription-preference survey instead of a "Subscribe" CTA.
///   - the starting credits are final. Once spent, new paid activity (talk,
///     Watch, generation) stops; reviewing stays free.
///   - friend invites (referral top-ups) are hidden. They unlock only after
///     the beta ends — the referral code + server RPC stay intact for then.
///
/// Flip `isBeta` to false at launch and the app reverts to the real paywall
/// (trial funnel → plan purchase) and re-exposes invites.
enum BetaConfig {
    static let isBeta = true

    /// Referral / invite UI is offered only after the beta.
    static var invitesAvailable: Bool { !isBeta }

    /// The paywall collects a preference survey (rather than a purchase) while
    /// subscriptions aren't live.
    static var collectsPreferenceSurvey: Bool { isBeta }
}

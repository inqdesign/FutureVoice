import Foundation
import PostHog

/// Thin wrapper over PostHog — product analytics for the beta funnel only.
///
/// Privacy stance (keep it this way; it's what the App Privacy label promises):
///   - No ad identifiers (IDFA), no session replay, no screen-view autocapture.
///   - `distinct_id` is the Supabase user UUID — a random account id, never an
///     email or name. Anonymous until `identify` runs on sign-in.
///   - DEBUG/simulator builds opt out, so local dev never pollutes the funnel.
///
/// All call sites are already `@MainActor` (AppState / views); the SDK itself
/// is thread-safe, so this stays a plain enum of static calls.
enum Analytics {
    /// PostHog project ingestion key. This is a PUBLIC, write-only client key —
    /// the same one shipped in the web landing (`web/index.html`). Safe to
    /// embed in the client; it is NOT a secret and cannot read any data.
    private static let apiKey = "phc_QFR0wEkAigOahZAlzW9wsYzAUGQEyuurF7PueVdsDoA"
    private static let host = "https://eu.i.posthog.com"

    /// Call once, as early as possible (app init).
    static func start() {
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true   // opened / backgrounded
        config.captureScreenViews = false                 // explicit funnel events only
        config.sessionReplay = false                      // never record the screen
        #if DEBUG
        config.debug = true
        #endif
        PostHogSDK.shared.setup(config)
        // Stamp every event with the product so this project can be split from
        // DeskSquat, which shares the same PostHog project/key. Filter on
        // `app = "nawana"` for this app; DeskSquat events carry no `app` (or its
        // own value). Registered as a super property so it rides on all events.
        PostHogSDK.shared.register(["app": productTag])
        #if DEBUG
        // Keep dev + simulator noise out of the beta funnel.
        PostHogSDK.shared.optOut()
        #endif
    }

    /// Product identifier stamped on every event (see `start`). Keep in sync
    /// with the web landing's `posthog.register({app:'nawana'})`.
    static let productTag = "nawana"

    /// Team/owner accounts whose own usage must never enter analytics. Matched
    /// on the Supabase user UUID at `identify` time and dropped client-side
    /// (belt-and-suspenders with the server-side "internal & test users"
    /// filter). `optOut` persists on the device, so once matched the SDK stays
    /// silent across launches.
    /// Uppercased for a case-insensitive match — iOS `UUID.uuidString` is
    /// uppercase, so compare `userId.uppercased()` against these.
    private static let excludedUserIds: Set<String> = [
        "72BCAA7E-3DD2-4364-B197-078BA59C1CE4",   // owner
    ]

    static func capture(_ event: String, _ props: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: props)
    }

    /// Tie events to the signed-in account. `userId` is the Supabase UUID —
    /// not an email/name — so this stays a stable, non-PII identifier. An
    /// excluded (owner/team) account opts the device out entirely instead.
    static func identify(userId: String) {
        if excludedUserIds.contains(userId.uppercased()) {
            PostHogSDK.shared.optOut()
            return
        }
        PostHogSDK.shared.identify(userId)
    }

    /// On sign-out / account deletion, drop the identity so the next signed-in
    /// user isn't merged into the previous one's person.
    static func reset() {
        PostHogSDK.shared.reset()
    }
}

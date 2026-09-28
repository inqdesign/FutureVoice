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
        "C7565D27-528C-46C1-9662-37248EC8AA36",   // team
    ]

    static func capture(_ event: String, _ props: [String: Any] = [:]) {
        // Per event rather than a super property: both settings change while
        // the app runs, and a registered value would go stale until relaunch.
        let settings: [String: Any] = Telemetry.callSettings()
        PostHogSDK.shared.capture(event, properties: settings.merging(props) { _, caller in caller })
    }

    /// Tie events to the signed-in account. `userId` is the Supabase UUID —
    /// not an email/name — so this stays a stable, non-PII identifier. An
    /// excluded (owner/team) account opts the device out entirely instead.
    ///
    /// If the device is still identified as a DIFFERENT account, drop that
    /// identity first. posthog-ios ignores `identify` on an already-identified
    /// device when the id differs (it only logs "already identified with id"),
    /// and `reset` runs only on in-app sign-out / delete — so an account the
    /// SERVER deleted (an onboarding session reclaimed by
    /// `cleanup-anonymous-voices`) left the phone reporting a ghost uuid for
    /// every account that came after it, and the admin live tab could never
    /// join that person to their real row (2026-09-16).
    static func identify(userId: String) {
        if excludedUserIds.contains(userId.uppercased()) {
            PostHogSDK.shared.optOut()
            return
        }
        let current = PostHogSDK.shared.getDistinctId()
        let isIdentified = !current.isEmpty && current != PostHogSDK.shared.getAnonymousId()
        if isIdentified, current.uppercased() != userId.uppercased() {
            PostHogSDK.shared.reset()
        }
        PostHogSDK.shared.identify(userId)
    }

    /// On sign-out / account deletion, drop the identity so the next signed-in
    /// user isn't merged into the previous one's person.
    static func reset() {
        PostHogSDK.shared.reset()
    }
}

// MARK: - Person properties

extension Analytics {
    /// WHO this learner is set up as — the onboarding answers and the goals
    /// they chose. Every one of these lived only in UserDefaults (and the
    /// learner's own iCloud), so nothing outside the phone could say what
    /// anybody's daily goal was: a question like "do the 5-minute learners
    /// stay?" had no data behind it at all (2026-09-28).
    ///
    /// These are PERSON properties, not events: the current answer, replaced
    /// in place, which is what a cohort filter reads. Nothing here is PII —
    /// a goal, a level and two language codes.
    ///
    /// It is sent only when something CHANGED (`personSignatureKey`), so the
    /// common foreground costs no event; a `$set` on every launch would be
    /// one of the app's noisiest events for a number that moves twice a year.
    @MainActor
    static func notePerson(_ state: AppState, goals: GoalStore = .shared) {
        let props: [String: Any] = [
            "daily_goal_minutes": UserDefaults.standard.object(forKey: dailyGoalMinutesKey) as? Int ?? 10,
            "goal_sentences_per_day": goals.sentencesPerDay,
            "goal_words_per_day": goals.wordsPerDay,
            "goal_expressions_per_day": goals.expressionsPerDay,
            "goal_shadows_per_day": goals.shadowsPerDay,
            "target_language": state.targetLanguage,
            "native_language": state.nativeLanguage,
            "level": state.proficiency.rawValue,
            "app_language": LanguageCatalog.currentNative
        ]
        let signature = props.keys.sorted().map { "\($0)=\(props[$0] ?? "")" }.joined(separator: "|")
        guard signature != UserDefaults.standard.string(forKey: personSignatureKey) else { return }
        UserDefaults.standard.set(signature, forKey: personSignatureKey)
        // `$set` is PostHog's own property-only event.
        PostHogSDK.shared.capture("$set", properties: nil, userProperties: props)
    }

    /// The goal the setup flow writes (`SetupFlowView.finish`), read here so
    /// the two surfaces can't disagree about the key.
    static let dailyGoalMinutesKey = "futurevoice.dailyGoalMinutes"
    private static let personSignatureKey = "futurevoice.analytics.personSignature"
}

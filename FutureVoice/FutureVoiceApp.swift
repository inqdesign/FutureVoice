import Supabase
import SwiftUI
import UIKit
import UserNotifications

/// User-selectable appearance. `.system` follows iOS; the app was dark-only
/// before this existed, so every screen must stay system-color clean.
enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Settings-only, and Settings speaks the learner's own language — so
    /// this can't stay `rawValue.capitalized`, which is frozen English.
    var label: String {
        switch self {
        case .system: return explain("System")
        case .light:  return explain("Light")
        case .dark:   return explain("Dark")
        }
    }
}

/// Exists for ONE reason: `UNUserNotificationCenter.current().delegate` has to
/// be set before the app finishes launching, or a daily call answered from the
/// lock screen (cold launch) arrives with nobody listening and silently does
/// nothing. SwiftUI has no other hook that early.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Held strongly — `UNUserNotificationCenter.delegate` is a weak reference,
    /// and a delegate that deallocates takes every future answer with it.
    private let callDelegate = DailyCallNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = callDelegate
        // Categories are not persisted across launches — without this the
        // Answer / In-an-hour buttons simply don't render.
        DailyCallScheduler.registerCategory()
        // StoreKit re-delivers unfinished transactions (renewals, Ask-to-Buy
        // approvals, interrupted payments) at launch and keeps doing so until
        // they're finished. The paywall's own service is gone the moment the
        // sheet closes, so the listener has to start here.
        StoreKitService.startTransactionListener()
        return true
    }
}

@main
struct FutureVoiceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var auth = AuthService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Layout migration must precede AppState creation — store singletons
        // resolve their paths against the scoped directory on first touch.
        LanguageScope.migrateIfNeeded()
        Analytics.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(auth)
                .preferredColorScheme(appState.appearance.colorScheme)
                // The chrome locale is applied inside RootView, not here:
                // it changes when onboarding ends (UILanguage.isOnboarding),
                // and RootView's body is the one that already reads every
                // flag that gate turns on.
        }
        .onChange(of: scenePhase) { _, phase in
            // Drill grading may have moved due dates — leave with an accurate
            // reminder. Background path never prompts for permission.
            if phase == .background {
                Task { await DrillReminder.reschedule() }
            }
            // Cards drift due over time even with no store writes, so re-snapshot
            // the widget's study queue at both edges of a foreground stint.
            if phase == .active || phase == .background {
                StudyWidgetRefresher.refresh()
            }
            // Re-arm the daily call. Cheap and idempotent: a plan that still
            // matches the learner's language and clone and hasn't fired yet is
            // reused untouched, so this costs nothing on the common path. It
            // exists for the cases that would otherwise leave the phone
            // silent forever — a reinstall (pending requests gone), a plan
            // whose time passed unanswered, or a language switch.
            if phase == .active {
                appState.refreshDailyCall()
                // The Core has no push infrastructure, so an arrival is
                // noticed here and announced locally. Late by design — the
                // 30-in-a-row entry bar keeps arrivals rare enough that "next time
                // you open the app" still reads as news.
                Task { await CoreClubService.announceArrivals() }
                // Same reason, same shape: a friend joining with your code
                // is news that only exists server-side, and the grant it
                // brings lands in a number nobody watches.
                Task { await ReferralService.announceJoins() }
                // The seat grid draws each member in the palette their own
                // app wears, so the palette has to leave the device. Here
                // rather than in the theme picker: a member who changed
                // themes while signed out, or before the column existed,
                // still lands correctly on the next foreground.
                Task {
                    await CoreClubService.publishTheme(
                        UserDefaults.standard.integer(forKey: "futureselfTheme"))
                }
            }
        }
    }
}

/// Phase 1 app-wide state. UserDefaults-backed for the small primitive bits
/// (voiceCloneId, language settings); JSON-on-disk stores for richer objects.
@MainActor
final class AppState: ObservableObject {
    /// Deep-link destination inside the Practice tab. Set by RootTabView's
    /// onOpenURL (e.g. the study widget's futurevoice://vocab), consumed by
    /// PracticeTab when it appears — the tab may not be mounted yet at the
    /// moment the URL arrives on a cold launch, hence the handoff via state.
    /// A specific word/phrase (from a widget note tap) opens that item's page;
    /// nil opens the plain list (header tap, or the small widget).
    enum PracticeRoute: Equatable {
        case studying
        case vocabulary(word: String? = nil)
        case expressions(phrase: String? = nil)
        case book(kind: String, id: UUID)   // Continue widget → a book's detail page
        case review                         // review reminder → the due deck
        /// A per-item callback → open exactly that card.
        case reviewItem(kind: String, value: String)
    }
    @Published var pendingPracticeRoute: PracticeRoute?

    /// A specific item to focus (open its card) from a widget note tap. Kept
    /// separate from the route so it reaches the page EVEN WHEN it's already
    /// on screen — VocabularyView/ExpressionsView observe these and open the
    /// item, then clear it. (The route only pushes the page.)
    @Published var focusWord: String?
    @Published var focusPhrase: String?

    /// Set by the Free Talk widget's deep link — RootTabView starts a call as
    /// soon as it's up (staged, so a cold launch that isn't mounted yet still
    /// fires once the tab appears).
    @Published var pendingFreeTalk = false

    /// True while the Talk tab is showing its ROOT list (nothing pushed).
    /// ConversationHome flips it from its root's onAppear/onDisappear;
    /// RootTabView uses it to keep the floating Free-talk pill off pushed
    /// pages (Activity, scenario lists, …).
    @Published var talkRootVisible = true

    /// The Talk hero ring's live GLOBAL frame (its Futureself circle),
    /// reported by ConversationHome — RootTabView's free-talk proxy morphs
    /// from exactly this pose down into the call's mic pill.
    @Published var talkRingFrame: CGRect = .zero
    /// True while that proxy owns the surface (morphing or on call). The
    /// home ring hides itself then, so the surface never shows twice.
    @Published var talkRingProxyActive = false
    /// Mirror of the ring's minutes line ("4 of 10 min today"), kept fresh by
    /// ConversationHome.reload — the proxy renders the EXACT same two-line
    /// label, so the hand-off never shifts "Let's talk" vertically.
    @Published var talkRingHeadline = ""
    /// Bumped by RootTabView when a ring-path call closes. The home never
    /// disappears under that overlay (no onAppear), so this is what triggers
    /// the stats reload — behind the backdrop, before the reveal.
    @Published var talkHomeReloadToken = UUID()

    @Published var voiceCloneId: String? {
        didSet {
            UserDefaults.standard.set(voiceCloneId, forKey: Self.voiceCloneIdKey)
            // Remember the id so a LATER re-record doesn't orphan everything
            // already synthesized in this voice — see PhraseAudioStore.
            PhraseAudioStore.shared.registerOwnVoice(voiceCloneId)
        }
    }
    /// The accent last APPLIED to the clone (`VoiceAccent.id`), nil when the
    /// clone speaks with whatever the TTS model guesses. A remixed voice id
    /// carries no record of the accent it was remixed WITH, so without this
    /// the picker reopens with nothing checked and the learner can't tell
    /// what they already chose. Cleared by anything that mints a clone
    /// straight from the recording again — that drops the remix with it.
    @Published var voiceAccentId: String? {
        didSet { UserDefaults.standard.set(voiceAccentId, forKey: Self.voiceAccentIdKey) }
    }
    /// Which language the clone's SAMPLE was read in — the learner's native
    /// language when they took the native-script option, the target otherwise.
    ///
    /// Persisted because the voice comparison (`VoiceComparisonSheet`) has the
    /// clone re-say the opening of the script the recording contains, and
    /// outside onboarding nothing else remembers which script that was. It
    /// used to reach analytics and nowhere else, so Me → Voice would have had
    /// to guess — and guessing wrong turns a like-for-like comparison into two
    /// different sentences, which is the one thing it must not be.
    @Published var cloneScriptLanguage: String? {
        didSet { UserDefaults.standard.set(cloneScriptLanguage, forKey: Self.cloneScriptLanguageKey) }
    }
    /// Transient (never persisted): true while the voice-clone onboarding is
    /// playing its final act (cloned-voice greeting + theme pick). Setting
    /// `voiceCloneId` would otherwise make RootView swap the screen away the
    /// instant the clone lands — before the user ever hears it. The view
    /// raises this before cloning and lowers it on its final Continue.
    @Published var holdVoiceOnboarding = false
    /// True once the user tapped "Get started" on Welcome. Onboarding runs
    /// account-free from there — sign-up is deferred to the moment the voice
    /// clone actually needs the server. Persisted so a relaunch resumes the
    /// flow instead of bouncing back to Welcome.
    @Published var onboardingStarted: Bool = false {
        didSet {
            UserDefaults.standard.set(onboardingStarted, forKey: Self.onboardingStartedKey)
            if onboardingStarted && !oldValue { Analytics.capture("onboarding_started") }
        }
    }
    @Published var nativeLanguage: String = LanguageCatalog.defaultNative {
        didSet { UserDefaults.standard.set(nativeLanguage, forKey: Self.nativeLanguageKey) }
    }
    @Published var targetLanguage: String = "en" {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Self.targetLanguageKey) }
    }
    /// Target languages the user has enrolled in, enrollment order. The
    /// active one is `targetLanguage`; switching swaps the entire language-
    /// scoped store set (docs/multi-language-plan.md).
    @Published var enrolledLanguages: [String] = ["en"] {
        didSet { UserDefaults.standard.set(enrolledLanguages, forKey: LanguageScope.enrolledDefaultsKey) }
    }
    /// Transient (never persisted): set when a weekly assessment RAISES the
    /// measured level — RootTabView presents the one-time level-up sheet from
    /// it. Manual level changes (Me tab, setup) never trigger it; a measured
    /// downgrade stays silent — the Progress tab tells that story.
    @Published var levelUpAnnouncement: LevelUpAnnouncement?
    @Published var proficiency: CEFRLevel = .b1 {
        didSet {
            UserDefaults.standard.set(proficiency.rawValue, forKey: Self.proficiencyKey)
            // Keep the persisted profile's level in sync — it drives prompt
            // calibration in conversations and summaries.
            if learnerProfile.proficiencyLevel != proficiency {
                learnerProfile.proficiencyLevel = proficiency
                ProfileStore.shared.save(learnerProfile)
            }
        }
    }
    @Published var appearance: AppAppearance = .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    /// First-run setup gate. SetupFlowView (target language → level → persona)
    /// flips this once the user finishes; RootView routes to it until then.
    /// Distinct from `voiceCloneId`/`persona` so we can ask the quick-answer
    /// questions up front, before the heavier voice-clone recording.
    @Published var setupComplete: Bool = false {
        didSet {
            UserDefaults.standard.set(setupComplete, forKey: Self.setupCompleteKey)
            if setupComplete && !oldValue {
                Analytics.capture("setup_completed", [
                    "target_language": targetLanguage,
                    "level": proficiency.rawValue
                ])
            }
        }
    }
    /// Long-term learner memory for the current target language. Grows after
    /// every ended session via `recordSessionOutcome` and feeds the next
    /// conversation's system prompt — the spec §3 loop.
    @Published var learnerProfile: LearnerProfile
    @Published var persona: UserPersona?       // nil until first save
    @Published var topicSuggestions: [SuggestedTopic] = []
    @Published var counterparts: [Counterpart] = []
    @Published var watchDialogues: [WatchDialogue] = []
    @Published var scenarios: [Scenario] = []
    @Published var shadowAttempts: [ShadowAttempt] = []
    @Published var savedLines: [SavedLine] = []
    @Published var weeklyReports: [WeeklyReport] = []
    /// True while WeeklyReportEngine is generating a report. UI uses this
    /// to show a "Analyzing your week…" spinner instead of an empty state.
    @Published var weeklyReportGenerating: Bool = false

    /// What the user's clone is called — on ElevenLabs and in Me → Voice.
    /// Empty means "never named it": `voiceDisplayName` then derives one from
    /// the persona, so two users' clones are still tellable apart. Renaming
    /// goes through `renameVoice(to:)`, which also updates ElevenLabs.
    @Published private(set) var voiceName: String = "" {
        didSet { UserDefaults.standard.set(voiceName, forKey: Self.voiceNameKey) }
    }

    /// The name to SHOW and to send upstream — the user's own if they set one,
    /// otherwise "Future <persona name>". Falls back to a short slice of the
    /// account id when there's no persona name yet, so the ElevenLabs library
    /// never fills up with identical "Future Self" entries.
    var voiceDisplayName: String {
        let custom = voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultVoiceName : custom
    }

    /// The name used when the user hasn't chosen one. Kept separate from
    /// `voiceDisplayName` so the editor can tell "they left the default alone"
    /// from "they typed this exact string" — storing the derived name would
    /// freeze it against a later persona rename.
    var defaultVoiceName: String {
        let personaName = (persona?.displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !personaName.isEmpty { return "Future \(personaName)" }
        // No persona name yet (rare — setup asks for it before the clone).
        // A short stable token still beats yet another identical "Future Self"
        // in the voice library; renaming replaces it.
        return "Future Self (\(Self.voiceNameFallbackToken))"
    }

    /// Stable per-install token for the last-resort voice name.
    private static let voiceNameFallbackToken: String = {
        let key = "futurevoice.voiceNameToken"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        let s = String(UUID().uuidString.prefix(6)).lowercased()
        UserDefaults.standard.set(s, forKey: key)
        return s
    }()

    /// Rename the clone. Persists locally FIRST so the name sticks even when
    /// the upstream call fails (offline, function not deployed yet) — it is
    /// then applied on the next clone creation. Throws on upstream failure so
    /// the caller can say the two names are temporarily out of sync.
    func renameVoice(to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceName = trimmed
        guard let voiceId = voiceCloneId else { return }
        try await ElevenLabsClient.shared.renameVoice(voiceId: voiceId, name: voiceDisplayName)
    }

    private static let voiceCloneIdKey = "futurevoice.voiceCloneId"
    private static let voiceNameKey = "futurevoice.voiceName"
    private static let voiceAccentIdKey = "futurevoice.voiceAccentId"
    private static let cloneScriptLanguageKey = "futurevoice.cloneScriptLanguage"
    private static let pendingDeleteVoiceIdKey = "futurevoice.pendingDeleteVoiceId"
    private static let nativeLanguageKey = LanguageCatalog.nativeLanguageDefaultsKey
    private static let targetLanguageKey = LanguageCatalog.targetLanguageDefaultsKey
    private static let proficiencyKey = "futurevoice.proficiency"
    private static let appearanceKey = "futurevoice.appearance"
    private static let setupCompleteKey = "futurevoice.setupComplete"
    private static let onboardingStartedKey = "futurevoice.onboardingStarted"

    init() {
        let storedNative = UserDefaults.standard.string(forKey: Self.nativeLanguageKey)
            ?? LanguageCatalog.defaultNative
        let storedTarget = UserDefaults.standard.string(forKey: Self.targetLanguageKey) ?? "en"
        let storedLevel = UserDefaults.standard.string(forKey: Self.proficiencyKey)
            .flatMap(CEFRLevel.init(rawValue:)) ?? .b1
        learnerProfile = ProfileStore.shared.load(targetLanguage: storedTarget, proficiency: storedLevel)
        nativeLanguage = storedNative
        targetLanguage = storedTarget
        let storedEnrolled = UserDefaults.standard.stringArray(forKey: LanguageScope.enrolledDefaultsKey) ?? []
        enrolledLanguages = storedEnrolled.contains(storedTarget)
            ? storedEnrolled
            : storedEnrolled + [storedTarget]   // pre-multi-language install self-heals
        proficiency = storedLevel
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        voiceCloneId = UserDefaults.standard.string(forKey: Self.voiceCloneIdKey)
        voiceName = UserDefaults.standard.string(forKey: Self.voiceNameKey) ?? ""
        voiceAccentId = UserDefaults.standard.string(forKey: Self.voiceAccentIdKey)
        cloneScriptLanguage = UserDefaults.standard.string(forKey: Self.cloneScriptLanguageKey)
        pendingDeleteVoiceId = UserDefaults.standard.string(forKey: Self.pendingDeleteVoiceIdKey)
        setupComplete = UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
        onboardingStarted = UserDefaults.standard.bool(forKey: Self.onboardingStartedKey)
        persona = PersonaStore.shared.load()
        topicSuggestions = TopicStore.shared.load()
        // Self-heal Find-people rows duplicated by the old per-render id, and
        // move their talks onto the surviving person (no-op once clean).
        let counterpartRemap = CounterpartStore.shared.repairRemoteDuplicates()
        if !counterpartRemap.isEmpty {
            for var s in SessionStore.shared.load() {
                guard let old = s.counterpartId, let new = counterpartRemap[old] else { continue }
                s.counterpartId = new
                SessionStore.shared.save(s)
            }
        }
        counterparts = CounterpartStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
        scenarios = ScenarioStore.shared.load()
        shadowAttempts = ShadowAttemptStore.shared.load()
        savedLines = SavedLineStore.shared.load()
        weeklyReports = WeeklyReportStore.shared.load()
        // didSet never fires for assignments inside init — seed the lineage
        // here so an install that predates it still resolves its own audio.
        PhraseAudioStore.shared.registerOwnVoice(voiceCloneId)

        Task { await self.observeAuth() }
    }

    // MARK: - Daily call

    /// Everything the voicemail can be grounded in, read off the stores the
    /// learner has already filled. Assembled here rather than inside
    /// `VoicemailEngine` so the engine never guesses which language's data to
    /// read — it gets exactly the active scope's.
    func voicemailContext() -> VoicemailEngine.Context {
        let ended = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        let last = ended.first

        // Phrases the FLUENT SELF handed over last time. Naming one back is
        // what makes the call sound like a continuation rather than a
        // generated greeting — and it puts the phrase in front of the learner
        // one more time, which is the review this loop exists for.
        let phrases = (last?.summary?.expressionsUsed ?? [])
            + (last?.summary?.newWordsUsed ?? [])

        let days = (last?.endedAt).map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        }

        return VoicemailEngine.Context(
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            proficiency: proficiency,
            personaName: persona?.displayName,
            lastTopic: last?.displayTitle,
            lastPhrases: Array(phrases.prefix(4)),
            daysSinceLastTalk: days,
            dueCount: DrillStore.shared.dueCount()
        )
    }

    /// Write and schedule the next call. Fire-and-forget: the learner never
    /// waits on it, and a failure just means tomorrow's ring falls back to the
    /// plan already on disk.
    ///
    /// - Parameter force: rewrite the script even when a usable plan exists.
    ///   Passed after a session ends — that talk is fresher context than
    ///   whatever the standing plan was written from.
    func refreshDailyCall(force: Bool = false) {
        guard DailyCallStore.shared.isEnabled else { return }
        let context = voicemailContext()
        let voiceId = voiceCloneId
        let caller = voiceDisplayName
        Task {
            await DailyCallScheduler.refresh(context: context, voiceId: voiceId,
                                             callerName: caller, force: force)
        }
    }

    /// Called from ConversationView after `endSession` finishes saving the
    /// session. Checks unlock state and, if ready, fires the engine in the
    /// background — UI never blocks on the Gemini call.
    func maybeGenerateWeeklyReport() {
        // Archived talks are out of the evidence pool — same rule as the
        // Progress tab's score stats.
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil && $0.archivedAt == nil }
        let last = weeklyReports.first
        guard case .ready = WeeklyReportEngine.unlockState(
            endedSessions: sessions,
            lastReport: last
        ) else { return }
        guard !weeklyReportGenerating else { return }
        weeklyReportGenerating = true

        Task {
            defer { Task { @MainActor in self.weeklyReportGenerating = false } }
            do {
                let report = try await WeeklyReportEngine.generate(
                    endedSessions: sessions,
                    lastReport: last,
                    targetLanguage: self.targetLanguage,
                    nativeLanguage: self.nativeLanguage
                )
                await MainActor.run {
                    WeeklyReportStore.shared.save(report)
                    self.weeklyReports = WeeklyReportStore.shared.load()
                    // The measured level replaces the self-reported setting —
                    // from here scoring calibration, pickup-word difficulty
                    // and the talk-card label all track measurement. A manual
                    // change in Me still overrides until the next assessment.
                    if let lvl = report.cefrLevel.flatMap(CEFRLevel.init(rawValue:)),
                       lvl != self.proficiency {
                        let previous = self.proficiency
                        self.proficiency = lvl
                        if CoreVocabulary.levelRank(lvl) > CoreVocabulary.levelRank(previous) {
                            self.levelUpAnnouncement = LevelUpAnnouncement(from: previous, to: lvl)
                            Analytics.capture("level_up", [
                                "from": previous.rawValue, "to": lvl.rawValue
                            ])
                        }
                    }
                }
            } catch {
                print("weekly report generation failed:", error)
            }
        }
    }

    /// Archive / unarchive a talk. Archived talks keep their book (openable
    /// from the Practice shelf's Archived list) but stop counting as score
    /// and assessment evidence — so flipping this re-runs the latest
    /// assessment when the talk was inside its window. Unarchiving restores
    /// the evidence the same way.
    func setSessionArchived(id: UUID, _ archived: Bool) {
        guard var s = SessionStore.shared.load().first(where: { $0.id == id }),
              (s.archivedAt != nil) != archived else { return }
        s.archivedAt = archived ? Date() : nil
        SessionStore.shared.save(s)
        reassessAfterEvidenceChange(in: s)
    }

    /// Delete a talk for good: the session row, its drill cards, and its
    /// cached per-turn audio. If the talk was evidence in the latest
    /// assessment, that assessment is voided and re-run without it.
    func deleteSession(id: UUID) {
        guard let s = SessionStore.shared.load().first(where: { $0.id == id }) else { return }
        SessionStore.shared.delete(id: id)
        DrillStore.shared.deleteForSession(id)
        for turn in s.turns {
            TurnAudioStore.shared.delete(turnId: turn.id)
            if let url = turn.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        reassessAfterEvidenceChange(in: s)
    }

    /// Evidence inside an already-minted assessment changed — the user
    /// excluded a misheard turn from a session. If that session falls inside
    /// the LATEST assessment's window, the verdict is standing on repudiated
    /// evidence: void it and re-run the assessment over the same (now
    /// corrected) window. Older assessments stay — their windows closed with
    /// the evidence they had, and the growth chart should stay honest history.
    func reassessAfterEvidenceChange(in session: Session) {
        guard let latest = weeklyReports.first else { return }
        let when = session.endedAt ?? session.startedAt
        // The latest window = everything after the previous report's end.
        let windowStart = weeklyReports.dropFirst().first?.periodEnd ?? .distantPast
        guard when > windowStart, when <= latest.periodEnd else { return }
        WeeklyReportStore.shared.delete(id: latest.id)
        weeklyReports = WeeklyReportStore.shared.load()
        // With the voided report gone, the unlock conditions are met by the
        // same window that produced it — this regenerates immediately, now
        // with the excluded turns filtered out.
        maybeGenerateWeeklyReport()
    }

    /// Watches Supabase auth state. When a session appears (either restored
    /// on app launch or fresh sign-in), pull the latest cloud state down.
    /// Only thing we sync today is the active voice_clone_id — that's the
    /// one piece of data that's expensive to lose on reinstall.
    private func observeAuth() async {
        for await change in SupabaseProvider.shared.auth.authStateChanges {
            guard let session = change.session else { continue }
            // distinct_id = Supabase user UUID (a random account id, not PII).
            Analytics.identify(userId: session.user.id.uuidString)
            await self.restoreVoiceCloneFromCloud()
            // Retry any delete that never landed — an orphaned clone holds an
            // account voice slot hostage, and the ceiling is shared by every
            // user.
            await self.cleanupPreviousVoiceClone()
        }
    }

    private func restoreVoiceCloneFromCloud() async {
        // If we already have a voice locally, trust local — the user just
        // signed in on the device that originally cloned it.
        guard voiceCloneId == nil else { return }

        struct Row: Decodable { let elevenlabs_voice_id: String }
        do {
            let rows: [Row] = try await SupabaseProvider.shared
                .from("voice_clones")
                .select("elevenlabs_voice_id")
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value
            if let restored = rows.first?.elevenlabs_voice_id {
                self.voiceCloneId = restored
            }
        } catch {
            // Don't surface — onboarding will just have the user re-record,
            // which is the same outcome as a fresh install.
            print("voice clone restore failed:", error)
        }
    }

    #if DEBUG
    /// Debug-only: replay the whole first-run flow without uninstalling.
    /// Wipes the setup gate, voice clone, and persona so RootView routes back
    /// through SetupFlowView → voice clone → persona. Keeps the auth session
    /// so there's no re-login. The ElevenLabs clone is stashed for cleanup
    /// (same as a normal re-record), not orphaned.
    func resetOnboarding() {
        resetVoiceClone()              // stashes voiceCloneId for later delete, sets nil
        PersonaStore.shared.clear()
        // Or the replay skips the two screens most likely to need re-testing.
        ConsentStore.shared.reset()
        persona = nil
        setupComplete = false
    }
    #endif

    func isLineSaved(_ id: UUID) -> Bool {
        savedLines.contains { $0.id == id }
    }

    /// Bookmark / un-bookmark a line for the personal shadow archive.
    func toggleSavedLine(turn: Turn, source: String = "") {
        if isLineSaved(turn.id) {
            SavedLineStore.shared.delete(id: turn.id)
        } else {
            SavedLineStore.shared.save(SavedLine(
                id: turn.id,
                text: turn.transcript,
                source: source
            ))
        }
        savedLines = SavedLineStore.shared.load()
    }

    func removeSavedLine(id: UUID) {
        SavedLineStore.shared.delete(id: id)
        savedLines = SavedLineStore.shared.load()
    }

    func saveShadowAttempt(_ a: ShadowAttempt) {
        ShadowAttemptStore.shared.save(a)
        shadowAttempts = ShadowAttemptStore.shared.load()
        Analytics.capture("shadow_attempted", ["score": a.matchScore])
    }

    func deleteShadowAttempt(id: UUID) {
        ShadowAttemptStore.shared.delete(id: id)
        shadowAttempts = ShadowAttemptStore.shared.load()
    }

    func saveScenario(_ s: Scenario) {
        let isNew = !scenarios.contains { $0.id == s.id }
        ScenarioStore.shared.save(s)
        scenarios = ScenarioStore.shared.load()
        if isNew { Analytics.capture("scenario_created", ["is_topic": s.isTopic == true]) }
    }

    /// Rotate the stored opener pool for a scenario talk. nil when no pool
    /// exists yet — the caller generates one (ONE call) and stores it via
    /// `storeScenarioOpeners`, so every later talk on this scenario starts
    /// instantly and free.
    func nextScenarioOpener(for id: UUID) -> String? {
        guard var s = scenarios.first(where: { $0.id == id }),
              let pool = s.openers, !pool.isEmpty else { return nil }
        let cursor = (s.openerCursor ?? 0) % pool.count
        s.openerCursor = (cursor + 1) % pool.count
        saveScenario(s)
        return pool[cursor]
    }

    func storeScenarioOpeners(_ pool: [String], for id: UUID) {
        guard var s = scenarios.first(where: { $0.id == id }), !pool.isEmpty else { return }
        s.openers = pool
        // The first line is being spoken right now — next talk starts at 1.
        s.openerCursor = 1 % pool.count
        saveScenario(s)
    }

    func deleteScenario(id: UUID) {
        ScenarioStore.shared.delete(id: id)
        scenarios = ScenarioStore.shared.load()
    }

    func markScenarioUsed(id: UUID) {
        ScenarioStore.shared.markUsed(id: id)
        scenarios = ScenarioStore.shared.load()
    }

    func setScenarioArchived(id: UUID, _ archived: Bool) {
        guard var s = scenarios.first(where: { $0.id == id }) else { return }
        s.archivedAt = archived ? Date() : nil
        saveScenario(s)
    }

    /// Manual override from the curriculum page — the auto-detection below
    /// only ever SETS mastery, so a hand-checked item stays checked.
    func markCurriculumItemMastered(scenarioId: UUID, itemId: UUID) {
        guard var s = scenarios.first(where: { $0.id == scenarioId }),
              var c = s.curriculum else { return }
        for path in [\ScenarioCurriculum.words, \.expressions, \.shadowLines] {
            if let i = c[keyPath: path].firstIndex(where: { $0.id == itemId }) {
                c[keyPath: path][i].masteredAt = Date()
            }
        }
        s.curriculum = c
        saveScenario(s)
    }

    /// Every un-mastered study item across the learner's live books, flattened
    /// for `CarryoverDetector`. Archived books are done with — nothing there
    /// is still being studied.
    var openCurriculumItems: [CarryoverDetector.CurriculumItem] {
        scenarios.filter { $0.archivedAt == nil }.flatMap { scenario -> [CarryoverDetector.CurriculumItem] in
            guard let c = scenario.curriculum else { return [] }
            let words = c.words.filter { $0.masteredAt == nil }
                .map { CarryoverDetector.CurriculumItem(id: $0.id, text: $0.text, isWord: true) }
            let phrases = (c.expressions + c.shadowLines).filter { $0.masteredAt == nil }
                .map { CarryoverDetector.CurriculumItem(id: $0.id, text: $0.text, isWord: false) }
            return words + phrases
        }
    }

    /// Master the book items the learner PRODUCED in a real conversation.
    /// Saying it live in an unrelated talk is the strongest form of the
    /// "used in a real talk" rule `refreshScenarioMastery` documents — that
    /// pass just can't see it, because it only reads talks whose topic matches
    /// the book's title.
    func markCurriculumItemsUsedInConversation(itemIds: [UUID]) {
        guard !itemIds.isEmpty else { return }
        let wanted = Set(itemIds)
        for var scenario in scenarios {
            guard var c = scenario.curriculum else { continue }
            var changed = false
            for path in [\ScenarioCurriculum.words, \.expressions, \.shadowLines] {
                for i in c[keyPath: path].indices
                where c[keyPath: path][i].masteredAt == nil
                    && wanted.contains(c[keyPath: path][i].id) {
                    c[keyPath: path][i].masteredAt = Date()
                    changed = true
                }
            }
            guard changed else { continue }
            scenario.curriculum = c
            saveScenario(scenario)
        }
    }

    /// Recompute mastery for one scenario's curriculum from what the user has
    /// ACTUALLY done. Deterministic, no LLM, and it reads the app's existing
    /// learning records instead of keeping a parallel one:
    ///   - a word is mastered when `VocabStore` has it — i.e. the user used
    ///     it in any real talk (post-session ingest) or tapped "I know it"
    ///     on its word card
    ///   - an expression is mastered when its record exists in VocabStore's
    ///     expression pool — used in any real talk (session ingest) or
    ///     self-declared via "I know it" on its card — or when it appears in
    ///     the user's own turns under this scenario
    ///   - a shadow line is mastered once a saved attempt scores
    ///     ≥ `ScenarioCurriculum.shadowMasteryScore`
    /// Only ever flips items ON — un-mastering is not a thing a later refresh
    /// can do, so manual check-offs survive.
    func refreshScenarioMastery(id: UUID) {
        guard var s = scenarios.first(where: { $0.id == id }),
              var c = s.curriculum else { return }

        let spoken = SessionStore.shared.load()
            .filter { $0.topic == s.displayTitle }
            .flatMap { $0.turns }
            .filter { $0.role == .user }
            .map(\.transcript)
            .joined(separator: " ")
            .lowercased()

        func saidByUser(_ phrase: String) -> Bool {
            let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return false }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
            return spoken.range(of: pattern, options: .regularExpression) != nil
        }

        var changed = false
        for i in c.words.indices where c.words[i].masteredAt == nil {
            let word = c.words[i].text
            // The store is keyed by lemma, but records written straight off a
            // word card keep the tapped casing ("Oktoberfest") — check every
            // form so a proper-noun curriculum word still gets its checkmark.
            let known = [word, word.lowercased(), VocabStore.lookupKey(for: word)]
                .contains { VocabStore.shared.state(of: $0) != nil }
            if known || saidByUser(word) {
                c.words[i].masteredAt = Date()
                changed = true
            }
        }
        for i in c.expressions.indices where c.expressions[i].masteredAt == nil {
            let item = c.expressions[i]
            // hasUsedExpression, not hasExpression: a bookmark alone creates a
            // row, and reading that as mastery ticked items off for saving
            // them.
            if saidByUser(item.text) || VocabStore.shared.hasUsedExpression(item.text) {
                c.expressions[i].masteredAt = Date()
                changed = true
            }
        }
        for i in c.shadowLines.indices where c.shadowLines[i].masteredAt == nil {
            let best = shadowAttempts
                .filter { $0.turnId == c.shadowLines[i].id }
                .map(\.matchScore).max() ?? 0
            if best >= ScenarioCurriculum.shadowMasteryScore {
                c.shadowLines[i].masteredAt = Date()
                changed = true
            }
        }
        guard changed else { return }
        s.curriculum = c
        saveScenario(s)
    }

    func saveCounterpart(_ c: Counterpart) {
        CounterpartStore.shared.save(c)
        counterparts = CounterpartStore.shared.load()
    }

    /// Re-read the counterpart store after something wrote to it directly
    /// (the Find-people row repair) rather than through `saveCounterpart`.
    func reloadCounterparts() {
        counterparts = CounterpartStore.shared.load()
    }

    func deleteCounterpart(id: UUID) {
        CounterpartStore.shared.delete(id: id)
        WatchDialogueStore.shared.deleteAll(forCounterpart: id)
        counterparts = CounterpartStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
    }

    func saveWatchDialogue(_ d: WatchDialogue) {
        WatchDialogueStore.shared.save(d)
        watchDialogues = WatchDialogueStore.shared.load()
    }

    func deleteWatchDialogue(id: UUID) {
        WatchDialogueStore.shared.delete(id: id)
        watchDialogues = WatchDialogueStore.shared.load()
    }

    func savePersona(_ p: UserPersona) {
        PersonaStore.shared.save(p)
        persona = p
        // Old suggestions were grounded in the previous persona — wipe them
        // so the next picker open regenerates against the updated context.
        TopicStore.shared.clear()
        topicSuggestions = []
        // Keep the user's Find-people presence in step with their profile
        // (no-op when they manage their public intro by hand).
        Task { await PublicPersonaService.autoSyncMyPersona(p, language: targetLanguage) }
    }

    func updateTopicSuggestions(_ topics: [SuggestedTopic]) {
        TopicStore.shared.save(topics)
        topicSuggestions = topics
    }

    /// Holding pen for the previous voice id while the user is in re-record
    /// onboarding. We can't delete it via the API until the new clone is
    /// actually created — if we deleted up front and the user then gave up,
    /// they'd have NO voice at all.
    ///
    /// PERSISTED: this used to be in-memory only, so a delete that failed (or
    /// an app kill mid-flow) orphaned the old voice in the ElevenLabs account
    /// forever. Those leaked slots are what fills a 30-voice ceiling. Now it
    /// survives relaunch and the delete is retried at startup.
    @Published private(set) var pendingDeleteVoiceId: String? {
        didSet { UserDefaults.standard.set(pendingDeleteVoiceId, forKey: Self.pendingDeleteVoiceIdKey) }
    }

    /// Wipe the clone so the user re-records. Stashes the current id so it
    /// can be deleted from ElevenLabs once a new clone is in place.
    func resetVoiceClone() {
        pendingDeleteVoiceId = voiceCloneId
        voiceCloneId = nil
        voiceAccentId = nil
    }

    /// Post-account-deletion local wipe — the device should look factory-fresh
    /// to whoever signs in next. The server side (clone, credits, auth user)
    /// is already gone by the time this runs; here we remove every JSON store
    /// and audio file in Documents, clear all futurevoice.* defaults, and
    /// reset the in-memory state that gates RootView so a future sign-in
    /// starts at setup instead of inheriting a ghost account's data.
    func wipeLocalData() {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let contents = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
            for url in contents { try? fm.removeItem(at: url) }
        }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("futurevoice.") {
            defaults.removeObject(forKey: key)
        }
        // The lang/ tree is gone — recreate the active directory and flush
        // every scoped store's cache so post-wipe writes land somewhere real.
        LanguageScope.repointStores()
        enrolledLanguages = [targetLanguage]
        // Published state — the didSet observers re-persist the fresh values,
        // which is exactly what a first-run install would look like.
        voiceCloneId = nil
        voiceName = ""
        voiceAccentId = nil
        pendingDeleteVoiceId = nil
        PhraseAudioStore.shared.clearOwnVoiceLineage()
        // The defaults are gone above, but this singleton's published values
        // would stay warm until relaunch — and a warm `isAgeVerified` waves
        // whoever signs in next straight past the age gate.
        ConsentStore.shared.reset()
        persona = nil
        setupComplete = false
        learnerProfile = ProfileStore.shared.load(targetLanguage: targetLanguage, proficiency: proficiency)
        topicSuggestions = []
        counterparts = []
        watchDialogues = []
        scenarios = []
        shadowAttempts = []
        savedLines = []
        weeklyReports = []
        StudyWidgetRefresher.refresh()   // blank the home-screen widgets too
    }

    /// Clone (or re-clone) the voice from a recorded sample WAV. Normalizes the
    /// sample loudness, uploads to ElevenLabs, swaps in the new voice id, and
    /// cleans up the previous clone. Shared by first-run onboarding and the
    /// Settings "regenerate from saved recording" action.
    /// `scriptLanguage` is the language the sample was READ in (onboarding
    /// lets the user choose; a regeneration from the saved sample doesn't
    /// know, and passes nil). Reported so the funnel can tell whether the
    /// native-language take actually reduces re-records.
    func regenerateVoiceClone(fromSampleAt sampleURL: URL,
                              scriptLanguage: String? = nil) async throws {
        let isFirstClone = voiceCloneId == nil
        Analytics.capture("voice_clone_started", [
            "first_time": isFirstClone,
            "script_language": scriptLanguage ?? "unknown",
            "native_language": nativeLanguage,
            "level": proficiency.rawValue
        ])
        let normalized = AudioLoudness.peakNormalizedWAV(at: sampleURL)
        // Denoise only a take that actually needs it. The threshold matches
        // AudioSampleQuality's own "some background noise" line, so anything
        // it would flag to the user still gets cleaned, and only a take it
        // calls clean is passed through untouched (where the denoiser could
        // only strip voice texture). Measured here rather than in the view so
        // the Settings → Voice regeneration path gets the same decision.
        // Unreadable sample → denoise, matching the previous behaviour.
        let snr = AudioSampleQuality.analyze(url: normalized)?.estimatedSNRdB
        let denoise = (snr ?? 0) < 22
        Analytics.capture("voice_clone_denoise", ["applied": denoise,
                                                  "snr_db": Int(snr ?? -1)])
        let newId: String
        do {
            newId = try await ElevenLabsClient.shared.cloneVoice(
                // The user's chosen name (or the persona-derived default) —
                // every clone used to land upstream as the same "Future Self".
                // Never put a language in it: one clone speaks all of them.
                name: voiceDisplayName,
                sampleAudioURLs: [normalized],
                removeBackgroundNoise: denoise
            )
        } catch where error.isVoiceLimitReached && pendingDeleteVoiceId != nil {
            // The account's voice slots are full AND this user is re-recording,
            // so one of those slots is their own outgoing clone. Free it and
            // retry once: a re-record shouldn't be blocked by the voice it is
            // replacing. (Only the STAGED id — never the live one, or a second
            // failure would leave them with no voice at all.)
            Analytics.capture("voice_clone_slot_reclaimed", ["first_time": isFirstClone])
            await cleanupPreviousVoiceClone()
            do {
                newId = try await ElevenLabsClient.shared.cloneVoice(
                    name: voiceDisplayName, sampleAudioURLs: [normalized],
                    removeBackgroundNoise: denoise)
            } catch {
                reportCloneFailure(error, isFirstClone: isFirstClone, afterReclaim: true)
                throw error
            }
        } catch {
            reportCloneFailure(error, isFirstClone: isFirstClone, afterReclaim: false)
            throw error
        }
        if let old = voiceCloneId, old != newId { pendingDeleteVoiceId = old }
        voiceCloneId = newId
        // A clone straight off the recording is un-remixed again, whatever
        // accent the outgoing one carried.
        voiceAccentId = nil
        // Remember the script this sample holds, so the comparison can put the
        // same words on both sides later. A rebuild with no language given
        // (Me → Voice re-runs the saved sample) leaves the old answer alone —
        // it's the same recording, so it's still the same script.
        if let scriptLanguage { cloneScriptLanguage = scriptLanguage }
        Analytics.capture("voice_clone_succeeded", ["first_time": isFirstClone])
        await cleanupPreviousVoiceClone()
        warmFreeTalkOpeners()
    }

    /// Fire-and-forget: make the next free talk open instantly on the
    /// CURRENT voice — opener pool text + audio, bundled fallback line
    /// included (see FreeTalkOpeners.warmFirstCall). Called from every point
    /// that mints a new voice id: the opener audio cache is keyed to
    /// (text, voiceId), so a new id silently invalidates all of it at once —
    /// without a re-warm, the first free talk after onboarding (and every
    /// one right after a re-record or accent switch) waits on live TTS.
    private func warmFreeTalkOpeners() {
        let language = targetLanguage
        let personaName = persona?.displayName
        let level = proficiency
        let voice = voiceCloneId
        Task.detached(priority: .utility) {
            await FreeTalkOpeners.shared.warmFirstCall(
                language: language, personaName: personaName,
                proficiency: level, voiceId: voice)
        }
    }

    /// Swap the live clone for a remixed variant of it (the accent picker).
    /// Same replacement contract as a re-record: the outgoing id is staged
    /// and deleted only after the new voice is in place, and audio already
    /// synthesized keeps playing through the PhraseAudioStore lineage.
    func adoptRemixedVoice(_ newId: String, accentId: String) async {
        guard newId != voiceCloneId else { return }
        if let old = voiceCloneId { pendingDeleteVoiceId = old }
        voiceCloneId = newId
        voiceAccentId = accentId
        Analytics.capture("voice_accent_applied", ["accent": accentId])
        await cleanupPreviousVoiceClone()
        warmFreeTalkOpeners()
    }

    /// WHY it failed, not just THAT it failed. Without the status + reason the
    /// funnel shows a wall of identical `voice_clone_failed` rows, and "the
    /// account is out of voice slots" is indistinguishable from "the user was
    /// offline" after the fact.
    private func reportCloneFailure(_ error: Error, isFirstClone: Bool, afterReclaim: Bool) {
        Analytics.capture("voice_clone_failed", [
            "first_time": isFirstClone,
            "status": Self.failureStatus(error),
            "reason": String(error.localizedDescription.prefix(200)),
            "voice_limit_reached": error.isVoiceLimitReached,
            "after_slot_reclaim": afterReclaim
        ])
    }

    /// HTTP status behind a clone failure — 402 for the credit wall, the real
    /// code for an upstream error, the URLError code when the request never
    /// landed. Reported to analytics so failures are triageable without a
    /// device in hand.
    private static func failureStatus(_ error: Error) -> Int {
        if let e = error as? ElevenLabsError {
            switch e {
            // Both walls are 402 on the wire; a clone can only ever hit the
            // credit one, but the status has to stay faithful to what the
            // server actually answered.
            case .insufficientCredits, .sceneCapReached: return 402
            case .httpError(let status, _): return status
            case .invalidResponse: return -1
            }
        }
        return (error as NSError).code
    }

    /// Called by VoiceCloneOnboardingView after a new clone succeeds, and at
    /// launch. Best-effort for the USER — it never blocks them — but the id is
    /// only forgotten once the delete actually succeeds, so a transient failure
    /// retries on the next launch instead of leaking the voice slot.
    func cleanupPreviousVoiceClone() async {
        guard let oldId = pendingDeleteVoiceId else { return }
        // Never delete the voice currently in use (a restore could have handed
        // the same id back).
        guard oldId != voiceCloneId else { pendingDeleteVoiceId = nil; return }
        do {
            try await ElevenLabsClient.shared.deleteVoice(voiceId: oldId)
            pendingDeleteVoiceId = nil
        } catch {
            // 403 "not owned" / 404 means it's already gone upstream — stop
            // retrying. Anything else stays queued for the next launch.
            if let e = error as? ElevenLabsError, case .httpError(let status, _) = e,
               status == 403 || status == 404 {
                pendingDeleteVoiceId = nil
            }
        }
    }

    /// Fold a finished session into the learner profile and persist. Called
    /// from ConversationView.endSession right after the summary is computed —
    /// this is what makes the next conversation aware of recurring mistakes.
    func recordSessionOutcome(summary: SessionSummary, turns: [Turn]) {
        let speakingSeconds = turns
            .filter { $0.role == .user }
            .reduce(0.0) { $0 + Double($1.durationMs) / 1000.0 }
        learnerProfile.absorb(summary: summary, speakingSeconds: speakingSeconds)
        ProfileStore.shared.save(learnerProfile)
        Analytics.capture("conversation_ended", [
            "user_turns": turns.filter { $0.role == .user }.count,
            "speaking_seconds": Int(speakingSeconds.rounded())
        ])
    }

    // MARK: - Language enrollment & switching (docs/multi-language-plan.md)

    /// First-run setup: the chosen target REPLACES the default enrollment
    /// (a fresh install self-enrolls in "en" before setup has asked anything).
    /// Repoints stores when the choice differs from the default so the very
    /// first session writes into the right lang/<code>/ directory.
    func completeSetup(target: String, native: String, level: CEFRLevel) {
        nativeLanguage = native
        enrolledLanguages = [target]
        if targetLanguage != target {
            targetLanguage = target
            LanguageScope.repointStores()
            reloadLanguageScopedState()
        }
        proficiency = level        // didSet syncs the profile
        setupComplete = true
    }

    /// Switch the active practice language. Order matters: persist the
    /// pointer first (store path resolution reads the same defaults key),
    /// then repoint every scoped store, then reload the published state those
    /// stores back. The switcher UI is only reachable from the Talk root, so
    /// a switch can't land mid-conversation.
    func switchLanguage(to code: String) {
        guard code != targetLanguage, enrolledLanguages.contains(code) else { return }
        targetLanguage = code                    // didSet persists the pointer
        LanguageScope.repointStores()
        reloadLanguageScopedState()
        StudyWidgetRefresher.refresh()
        Analytics.capture("language_switched", ["language": code])
    }

    /// Level of any enrolled language, active or not. The active one is live
    /// in `proficiency`; the rest sit in their own profile row, which is why
    /// the settings list can show a level per language without switching.
    func level(for code: String) -> CEFRLevel {
        code == targetLanguage
            ? proficiency
            : ProfileStore.shared.load(targetLanguage: code, proficiency: .b1).proficiencyLevel
    }

    /// Set the level of any enrolled language. For the active one this goes
    /// through `proficiency` (whose didSet syncs the loaded profile); for the
    /// others it writes that language's profile row straight to disk, so a
    /// later switch picks it up via `reloadLanguageScopedState`.
    func setLevel(_ level: CEFRLevel, for code: String) {
        guard level != self.level(for: code) else { return }
        if code == targetLanguage {
            proficiency = level
            return
        }
        var profile = ProfileStore.shared.load(targetLanguage: code, proficiency: level)
        profile.proficiencyLevel = level
        ProfileStore.shared.save(profile)
    }

    /// Enroll a new practice language and switch to it. Deliberately leaves
    /// the voice clone alone — one cloned voice speaks every language.
    func addLanguage(_ code: String, level: CEFRLevel) {
        guard LanguageCatalog.language(code) != nil else { return }
        if !enrolledLanguages.contains(code) {
            enrolledLanguages.append(code)
            Analytics.capture("language_added", ["language": code, "level": level.rawValue])
        }
        // Seed the profile at the chosen level so the first conversation is
        // calibrated before any session evidence exists.
        var seeded = ProfileStore.shared.load(targetLanguage: code, proficiency: level)
        seeded.proficiencyLevel = level
        ProfileStore.shared.save(seeded)
        switchLanguage(to: code)
    }

    /// Unenroll a language. On-disk data (lang/<code>/ and its profile row)
    /// is kept so re-adding restores all progress; only the enrollment goes.
    func removeLanguage(_ code: String) {
        guard enrolledLanguages.count > 1, enrolledLanguages.contains(code) else { return }
        if targetLanguage == code,
           let fallback = enrolledLanguages.first(where: { $0 != code }) {
            switchLanguage(to: fallback)
        }
        enrolledLanguages.removeAll { $0 == code }
    }

    /// Re-reads everything from disk after `BackupService.restore` laid a
    /// backup down underneath a running app.
    ///
    /// Without this the restore looks like it failed. Two separate reasons,
    /// both silent: the stores resolve their paths through
    /// `LanguageScope.active`, so a restored `targetLanguage` has to reach
    /// this object before anything is read; and every published property here
    /// re-persists itself on `didSet`, so the pre-restore values would write
    /// themselves back over the restored files on the next edit.
    ///
    /// Order matters — the language pointer moves first, stores repoint
    /// against it, and only then is content read. `reloadLanguageScopedState`
    /// takes the level from the restored profile, so `proficiency`'s didSet
    /// finds them already equal and never saves over it.
    func adoptRestoredData() {
        let defaults = UserDefaults.standard
        if let native = defaults.string(forKey: Self.nativeLanguageKey) { nativeLanguage = native }
        let enrolled = defaults.stringArray(forKey: LanguageScope.enrolledDefaultsKey) ?? []
        if !enrolled.isEmpty { enrolledLanguages = enrolled }
        if let target = defaults.string(forKey: Self.targetLanguageKey) { targetLanguage = target }
        if let raw = defaults.string(forKey: Self.appearanceKey),
           let value = AppAppearance(rawValue: raw) { appearance = value }

        LanguageScope.repointStores()
        PracticeLog.shared.reloadFromDisk()
        reloadLanguageScopedState()
        // Global (unscoped) stores the restore also overwrote.
        persona = PersonaStore.shared.load()
        counterparts = CounterpartStore.shared.load()
        StudyWidgetRefresher.refresh()
    }

    /// Everything published that a language-scoped store backs. Persona and
    /// counterparts are global — a switch leaves them alone.
    private func reloadLanguageScopedState() {
        learnerProfile = ProfileStore.shared.load(targetLanguage: targetLanguage, proficiency: proficiency)
        proficiency = learnerProfile.proficiencyLevel
        topicSuggestions = TopicStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
        scenarios = ScenarioStore.shared.load()
        shadowAttempts = ShadowAttemptStore.shared.load()
        savedLines = SavedLineStore.shared.load()
        weeklyReports = WeeklyReportStore.shared.load()
    }
}

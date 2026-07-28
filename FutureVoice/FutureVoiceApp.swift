import Supabase
import SwiftUI

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

    var label: String { rawValue.capitalized }
}

@main
struct FutureVoiceApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var auth = AuthService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(auth)
                .preferredColorScheme(appState.appearance.colorScheme)
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
        case vocabulary(word: String? = nil)
        case expressions(phrase: String? = nil)
    }
    @Published var pendingPracticeRoute: PracticeRoute?

    /// A specific item to focus (open its card) from a widget note tap. Kept
    /// separate from the route so it reaches the page EVEN WHEN it's already
    /// on screen — VocabularyView/ExpressionsView observe these and open the
    /// item, then clear it. (The route only pushes the page.)
    @Published var focusWord: String?
    @Published var focusPhrase: String?

    /// True while the Talk tab is showing its ROOT list (nothing pushed).
    /// ConversationHome flips it from its root's onAppear/onDisappear;
    /// RootTabView uses it to keep the floating Free-talk pill off pushed
    /// pages (Activity, scenario lists, …).
    @Published var talkRootVisible = true

    @Published var voiceCloneId: String? {
        didSet { UserDefaults.standard.set(voiceCloneId, forKey: Self.voiceCloneIdKey) }
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
        didSet { UserDefaults.standard.set(onboardingStarted, forKey: Self.onboardingStartedKey) }
    }
    @Published var nativeLanguage: String = "ko" {
        didSet { UserDefaults.standard.set(nativeLanguage, forKey: Self.nativeLanguageKey) }
    }
    @Published var targetLanguage: String = "en" {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Self.targetLanguageKey) }
    }
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
        didSet { UserDefaults.standard.set(setupComplete, forKey: Self.setupCompleteKey) }
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

    private static let voiceCloneIdKey = "futurevoice.voiceCloneId"
    private static let nativeLanguageKey = "futurevoice.nativeLanguage"
    private static let targetLanguageKey = LanguageCatalog.targetLanguageDefaultsKey
    private static let proficiencyKey = "futurevoice.proficiency"
    private static let appearanceKey = "futurevoice.appearance"
    private static let setupCompleteKey = "futurevoice.setupComplete"
    private static let onboardingStartedKey = "futurevoice.onboardingStarted"

    init() {
        let storedNative = UserDefaults.standard.string(forKey: Self.nativeLanguageKey) ?? "ko"
        let storedTarget = UserDefaults.standard.string(forKey: Self.targetLanguageKey) ?? "en"
        let storedLevel = UserDefaults.standard.string(forKey: Self.proficiencyKey)
            .flatMap(CEFRLevel.init(rawValue:)) ?? .b1
        learnerProfile = ProfileStore.shared.load(targetLanguage: storedTarget, proficiency: storedLevel)
        nativeLanguage = storedNative
        targetLanguage = storedTarget
        proficiency = storedLevel
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        voiceCloneId = UserDefaults.standard.string(forKey: Self.voiceCloneIdKey)
        setupComplete = UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
        onboardingStarted = UserDefaults.standard.bool(forKey: Self.onboardingStartedKey)
        persona = PersonaStore.shared.load()
        topicSuggestions = TopicStore.shared.load()
        counterparts = CounterpartStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
        scenarios = ScenarioStore.shared.load()
        shadowAttempts = ShadowAttemptStore.shared.load()
        savedLines = SavedLineStore.shared.load()
        weeklyReports = WeeklyReportStore.shared.load()

        Task { await self.observeAuth() }
    }

    /// Called from ConversationView after `endSession` finishes saving the
    /// session. Checks unlock state and, if ready, fires the engine in the
    /// background — UI never blocks on the Gemini call.
    func maybeGenerateWeeklyReport() {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }
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
                    targetLanguage: self.targetLanguage
                )
                await MainActor.run {
                    WeeklyReportStore.shared.save(report)
                    self.weeklyReports = WeeklyReportStore.shared.load()
                }
            } catch {
                print("weekly report generation failed:", error)
            }
        }
    }

    /// Watches Supabase auth state. When a session appears (either restored
    /// on app launch or fresh sign-in), pull the latest cloud state down.
    /// Only thing we sync today is the active voice_clone_id — that's the
    /// one piece of data that's expensive to lose on reinstall.
    private func observeAuth() async {
        for await change in SupabaseProvider.shared.auth.authStateChanges {
            guard change.session != nil else { continue }
            await self.restoreVoiceCloneFromCloud()
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
    }

    func deleteShadowAttempt(id: UUID) {
        ShadowAttemptStore.shared.delete(id: id)
        shadowAttempts = ShadowAttemptStore.shared.load()
    }

    func saveScenario(_ s: Scenario) {
        ScenarioStore.shared.save(s)
        scenarios = ScenarioStore.shared.load()
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
            if saidByUser(item.text) || VocabStore.shared.hasExpression(item.text) {
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
    }

    func updateTopicSuggestions(_ topics: [SuggestedTopic]) {
        TopicStore.shared.save(topics)
        topicSuggestions = topics
    }

    /// In-memory holding pen for the previous voice id while the user is
    /// in re-record onboarding. We can't delete it via the API until the new
    /// clone is actually created — if we deleted up front and the user then
    /// gave up, they'd have NO voice at all.
    @Published private(set) var pendingDeleteVoiceId: String?

    /// Wipe the clone so the user re-records. Stashes the current id so it
    /// can be deleted from ElevenLabs once a new clone is in place.
    func resetVoiceClone() {
        pendingDeleteVoiceId = voiceCloneId
        voiceCloneId = nil
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
        // Published state — the didSet observers re-persist the fresh values,
        // which is exactly what a first-run install would look like.
        voiceCloneId = nil
        pendingDeleteVoiceId = nil
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
    func regenerateVoiceClone(fromSampleAt sampleURL: URL) async throws {
        let normalized = AudioLoudness.peakNormalizedWAV(at: sampleURL)
        let newId = try await ElevenLabsClient.shared.cloneVoice(
            name: "Future Self — \(targetLanguage.uppercased())",
            sampleAudioURLs: [normalized]
        )
        if let old = voiceCloneId, old != newId { pendingDeleteVoiceId = old }
        voiceCloneId = newId
        await cleanupPreviousVoiceClone()
    }

    /// Called by VoiceCloneOnboardingView after a new clone succeeds.
    /// Best-effort delete — failures are swallowed so a transient ElevenLabs
    /// hiccup doesn't block the user.
    func cleanupPreviousVoiceClone() async {
        guard let oldId = pendingDeleteVoiceId else { return }
        pendingDeleteVoiceId = nil
        try? await ElevenLabsClient.shared.deleteVoice(voiceId: oldId)
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
    }
}

import Supabase
import SwiftUI

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
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // Drill grading may have moved due dates — leave with an accurate
            // reminder. Background path never prompts for permission.
            if phase == .background {
                Task { await DrillReminder.reschedule() }
            }
        }
    }
}

/// Phase 1 app-wide state. UserDefaults-backed for the small primitive bits
/// (voiceCloneId, language settings); JSON-on-disk stores for richer objects.
@MainActor
final class AppState: ObservableObject {
    @Published var voiceCloneId: String? {
        didSet { UserDefaults.standard.set(voiceCloneId, forKey: Self.voiceCloneIdKey) }
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
    @Published var weeklyReports: [WeeklyReport] = []
    /// True while WeeklyReportEngine is generating a report. UI uses this
    /// to show a "Analyzing your week…" spinner instead of an empty state.
    @Published var weeklyReportGenerating: Bool = false

    private static let voiceCloneIdKey = "futurevoice.voiceCloneId"
    private static let nativeLanguageKey = "futurevoice.nativeLanguage"
    private static let targetLanguageKey = "futurevoice.targetLanguage"
    private static let proficiencyKey = "futurevoice.proficiency"

    init() {
        let storedNative = UserDefaults.standard.string(forKey: Self.nativeLanguageKey) ?? "ko"
        let storedTarget = UserDefaults.standard.string(forKey: Self.targetLanguageKey) ?? "en"
        let storedLevel = UserDefaults.standard.string(forKey: Self.proficiencyKey)
            .flatMap(CEFRLevel.init(rawValue:)) ?? .b1
        learnerProfile = ProfileStore.shared.load(targetLanguage: storedTarget, proficiency: storedLevel)
        nativeLanguage = storedNative
        targetLanguage = storedTarget
        proficiency = storedLevel
        voiceCloneId = UserDefaults.standard.string(forKey: Self.voiceCloneIdKey)
        persona = PersonaStore.shared.load()
        topicSuggestions = TopicStore.shared.load()
        counterparts = CounterpartStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
        scenarios = ScenarioStore.shared.load()
        shadowAttempts = ShadowAttemptStore.shared.load()
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

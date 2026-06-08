import SwiftUI

@main
struct FutureVoiceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
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
    @Published var nativeLanguage: String = "ko"
    @Published var targetLanguage: String = "en"
    @Published var proficiency: CEFRLevel = .b1
    @Published var persona: UserPersona?       // nil until first save
    @Published var topicSuggestions: [SuggestedTopic] = []
    @Published var counterparts: [Counterpart] = []
    @Published var watchDialogues: [WatchDialogue] = []
    @Published var scenarios: [Scenario] = []
    @Published var shadowAttempts: [ShadowAttempt] = []

    private static let voiceCloneIdKey = "futurevoice.voiceCloneId"

    init() {
        voiceCloneId = UserDefaults.standard.string(forKey: Self.voiceCloneIdKey)
        persona = PersonaStore.shared.load()
        topicSuggestions = TopicStore.shared.load()
        counterparts = CounterpartStore.shared.load()
        watchDialogues = WatchDialogueStore.shared.load()
        scenarios = ScenarioStore.shared.load()
        shadowAttempts = ShadowAttemptStore.shared.load()
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

    /// Empty profile for the spike — Phase 2 wires this to Supabase.
    func makeEmptyProfile(userId: UUID) -> LearnerProfile {
        LearnerProfile(
            id: UUID(),
            userId: userId,
            targetLanguage: targetLanguage,
            proficiencyLevel: proficiency,
            recurringMistakes: [],
            weakVocabAreas: [],
            strongPatterns: [],
            totalSessions: 0,
            totalSpeakingSeconds: 0,
            lastSessionAt: nil,
            summaryEmbedding: nil
        )
    }
}

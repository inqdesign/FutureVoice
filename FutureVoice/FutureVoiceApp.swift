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

/// Phase 1 app-wide state. Everything lives in memory — persistence comes in Phase 2.
@MainActor
final class AppState: ObservableObject {
    @Published var voiceCloneId: String?       // ElevenLabs voice_id after onboarding
    @Published var nativeLanguage: String = "ko"
    @Published var targetLanguage: String = "en"
    @Published var proficiency: CEFRLevel = .b1

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

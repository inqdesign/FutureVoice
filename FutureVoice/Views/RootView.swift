import SwiftUI

/// Phase 1 entry point. If we don't yet have a cloned voice, show onboarding;
/// otherwise drop straight into the conversation playground.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.voiceCloneId == nil {
            VoiceCloneOnboardingView()
        } else if appState.persona == nil {
            PersonaOnboardingView()
        } else {
            RootTabView()
        }
    }
}

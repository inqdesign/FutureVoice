import SwiftUI

/// Phase 1 entry point. Sign in first, then voice-clone onboarding, then
/// persona, then the main tab UI. The auth gate is non-bypassable — without
/// a Supabase session we can't proxy ElevenLabs/Gemini calls.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        if auth.session == nil {
            SignInView()
        } else if appState.voiceCloneId == nil {
            VoiceCloneOnboardingView()
        } else if appState.persona == nil {
            PersonaOnboardingView()
        } else {
            RootTabView()
        }
    }
}

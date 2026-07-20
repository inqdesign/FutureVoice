import SwiftUI

/// App entry point. Sign in first, then quick-answer setup (target language,
/// …), then voice-clone onboarding, then persona, then the main tab UI. The
/// auth gate is non-bypassable — without a Supabase session we can't proxy
/// ElevenLabs/Gemini calls.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService

    init() { Self.applyRoundedNavBar() }

    var body: some View {
        content.fontDesign(.rounded)
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "capture"),
           let capture = DebugCapture.view(for: name, appState: appState) {
            capture
        } else if let preview = Self.onboardingPreview {
            preview
        } else {
            gatedContent
        }
        #else
        gatedContent
        #endif
    }

    @ViewBuilder
    private var gatedContent: some View {
        if !auth.didResolveInitialSession {
            // Match the (blank) launch screen until we know whether there's a
            // stored session — a returning user then lands straight on Home
            // with no Welcome-screen flash.
            Color(.systemBackground).ignoresSafeArea()
        } else if auth.session == nil {
            WelcomeView()
        } else if !appState.setupComplete {
            SetupFlowView()
        } else if appState.voiceCloneId == nil {
            VoiceCloneOnboardingView()
        } else if appState.persona == nil {
            PersonaOnboardingView()
        } else {
            RootTabView()
        }
    }

    #if DEBUG
    /// Screenshot harness. Launch with `-onboardingPreview <screen>` to jump
    /// straight to one onboarding view, bypassing the auth gate — lets the
    /// simulator capture each first-run screen without an Apple sign-in.
    /// Screens: welcome · setup · voice · persona · betaWelcome.
    private static var onboardingPreview: AnyView? {
        switch UserDefaults.standard.string(forKey: "onboardingPreview") {
        case "welcome":      return AnyView(WelcomeView())
        case "setup":        return AnyView(SetupFlowView())
        case "voice":        return AnyView(VoiceCloneOnboardingView())
        case "persona":      return AnyView(PersonaOnboardingView())
        case "betaWelcome":  return AnyView(BetaWelcomeView())
        default:             return nil
        }
    }
    #endif

    /// Make navigation-bar titles (which UIKit renders, so `.fontDesign` can't
    /// reach them) use SF Pro Rounded too.
    private static func applyRoundedNavBar() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: d, size: size)
        }
        let large: [NSAttributedString.Key: Any] = [.font: rounded(34, .bold)]
        let inline: [NSAttributedString.Key: Any] = [.font: rounded(17, .semibold)]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = large
        standard.titleTextAttributes = inline

        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.largeTitleTextAttributes = large
        transparent.titleTextAttributes = inline

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = transparent
    }
}

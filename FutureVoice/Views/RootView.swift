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
        } else if debugSkipAuth {
            // Skip-sign-in must win over the onboardingPreview jump, otherwise
            // tapping Skip on a `-onboardingPreview welcome` launch stays stuck
            // on Welcome. Fall straight into the real (auth-bypassed) flow.
            gatedContent
        } else if let preview = Self.onboardingPreview {
            preview
        } else {
            gatedContent
        }
        #else
        gatedContent
        #endif
    }

    #if DEBUG
    /// DEBUG-only: walk the onboarding flow without an Apple sign-in (set by
    /// WelcomeView's hidden skip button). UI-preview only — provider calls
    /// still require a real session, so nothing downstream can leak past it.
    @AppStorage("debugSkipAuth") private var debugSkipAuth = false
    private var authBypassed: Bool { debugSkipAuth }
    #else
    private var authBypassed: Bool { false }
    #endif

    @ViewBuilder
    private var gatedContent: some View {
        if !auth.didResolveInitialSession && !authBypassed {
            // Match the (blank) launch screen until we know whether there's a
            // stored session — a returning user then lands straight on Home
            // with no Welcome-screen flash.
            Color(.systemBackground).ignoresSafeArea()
        } else if auth.session == nil && !authBypassed {
            WelcomeView()
        } else if !appState.setupComplete {
            SetupFlowView()
        } else if appState.voiceCloneId == nil {
            VoiceCloneOnboardingView()
        } else if appState.persona == nil {
            PersonaIntakeView()
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
        case "persona":      return AnyView(PersonaIntakeView())
        case "betaWelcome":  return AnyView(BetaWelcomeView())
        default:             return nil
        }
    }
    #endif

    /// Make navigation-bar titles (which UIKit renders, so `.fontDesign` can't
    /// reach them) use SF Pro Rounded too.
    private static func applyRoundedNavBar() {
        let large: [NSAttributedString.Key: Any] = [.font: roundedNavFont(34, .bold)]
        let inline: [NSAttributedString.Key: Any] = [.font: roundedNavFont(17, .semibold)]

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

    /// Page/navigation titles render in Geist Pixel (bundled). Falls back to
    /// SF Pro Rounded if the font ever fails to load, so titles never vanish.
    static func roundedNavFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        if let pixel = UIFont(name: "GeistPixel-Square", size: size) { return pixel }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

extension Font {
    /// Geist Pixel — the app's display face (page titles, big CEFR levels,
    /// hero numbers). `.custom` falls back to the system font if the bundled
    /// file is ever missing, so text never disappears.
    static func geistPixel(_ size: CGFloat) -> Font {
        .custom("GeistPixel-Square", size: size)
    }
}

/// Hides the navigation bar's own background like
/// `.toolbarBackground(.hidden, for: .navigationBar)` — but that modifier
/// installs SwiftUI's own transparent appearance, which drops the
/// SF-Pro-Rounded title attributes from `applyRoundedNavBar` and the title
/// falls back to plain SF Pro. This shim sets the same transparent appearance
/// on the hosting controller's navigation item WITH the rounded fonts kept.
/// Attach with `.background(TransparentRoundedNavBar())` instead of the
/// SwiftUI modifier.
struct TransparentRoundedNavBar: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Shim() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Shim: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }
        private func apply() {
            // The navigation item that owns the bar styling belongs to the
            // ancestor sitting directly inside the UINavigationController.
            var vc: UIViewController? = parent
            while let c = vc, !(c.parent is UINavigationController) { vc = c.parent }
            guard let host = vc else { return }
            let a = UINavigationBarAppearance()
            a.configureWithTransparentBackground()
            a.largeTitleTextAttributes = [.font: RootView.roundedNavFont(34, .bold)]
            a.titleTextAttributes = [.font: RootView.roundedNavFont(17, .semibold)]
            host.navigationItem.standardAppearance = a
            host.navigationItem.compactAppearance = a
            host.navigationItem.scrollEdgeAppearance = a
        }
    }
}

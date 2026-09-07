import SwiftUI

/// App entry point. Sign in first, then quick-answer setup (level, native
/// language), then persona, then voice-clone onboarding LAST — the heaviest
/// ask sits at the top of the investment ladder and its Meet act drops
/// straight into the first call. The auth gate is non-bypassable — without a
/// Supabase session we can't proxy ElevenLabs/Gemini calls.
///
/// Two short steps trail the clone, each shown once and each setting its own
/// flag on every exit: the daily call (the clone's first job) and the plans
/// (`OnboardingPaywallView`, skipped silently for anyone with nothing to buy).
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService

    /// The whole app's accent follows the Futureself palette the user picked,
    /// so every tinted control (buttons, `.foregroundStyle(.tint)`, and the
    /// `Color.accentColor` chrome) matches the call button's living surface.
    /// Defaults to `.blue` — the same palette a fresh install starts on.
    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue
    /// Whether the daily-call step has been shown. Set by
    /// `DailyCallOnboardingView` on BOTH exits (enabled or skipped), so
    /// declining it doesn't turn the screen into a wall.
    @AppStorage("futurevoice.dailyCall.onboarded") private var dailyCallOnboarded = false
    /// Whether the plans have been offered once, at the end of onboarding.
    /// Set by `OnboardingPaywallView` on every exit — including the silent
    /// one it takes for an account that has nothing to buy.
    @AppStorage("futurevoice.paywall.onboarded") private var paywallOnboarded = false

    init() { Self.applyRoundedNavBar() }

    var body: some View {
        let accent = (FutureselfTheme(rawValue: storedTheme) ?? .blue).tint
        // `.tint` drives inherited controls and `.foregroundStyle(.tint)`;
        // `.accentColor` is what a literal `Color.accentColor` resolves to
        // (it does NOT follow `.tint`). The app uses both, so set both — the
        // deprecation on `.accentColor` is fine, it's still the only knob that
        // reaches `Color.accentColor` descendants.
        content
            .fontDesign(.rounded)
            .tint(accent)
            .accentColor(accent)
            // The app's ONE UI language — the one the learner picked in setup
            // and can change in Me → App language. Every `Text("literal")` in
            // the app resolves against this locale with no per-call code.
            // It used to be the language being LEARNED; see
            // `UILanguage.chromeLanguage` for why that's gone.
            .environment(\.locale, Locale(identifier: UILanguage.chromeLanguage))
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
        if !auth.didResolveInitialSession && !authBypassed
            && !appState.onboardingStarted && !appState.holdVoiceOnboarding {
            // Match the launch screen EXACTLY until we know whether there's a
            // stored session — a returning user then lands straight on Home
            // with no Welcome-screen flash. Same asset, same colour, same
            // centring as `UILaunchScreen` in Info.plist: resolving the
            // session can include a token refresh over the network, and a
            // plain background here read as the logo blinking off into a
            // blank page before Talk arrived (reported 2026-09-07).
            //
            // `holdVoiceOnboarding` vetoes this branch and the next one. The
            // flag means "a voice-clone act is on stage, don't move", and a
            // session that blinks — a token refresh mid-flow republishes
            // `auth.session` — used to outrank it: the chain fell to Welcome
            // for a frame and came back, which destroys and rebuilds the
            // whole voice screen. Every `@State` on it resets, so anything
            // open on top (the accent picker, mid-generate) silently closes.
            launchScreenTwin
        } else if auth.session == nil && !authBypassed
                    && !appState.onboardingStarted && !appState.holdVoiceOnboarding {
            // Welcome gates on "has the journey begun", NOT on the session:
            // "Get started" enters onboarding account-free, and sign-up is
            // deferred to the voice-clone step (the first server-bound act).
            // The sign-in path here is for returning users restoring.
            WelcomeView()
        } else if !appState.setupComplete {
            SetupFlowView()
        } else if appState.persona == nil {
            // Light taps before the heavy ask: persona's cards build the
            // investment (and the first call's context) BEFORE the voice
            // recording, so the clone lands as onboarding's finale — Meet act,
            // then straight into the first call.
            PersonaIntakeView()
        } else if appState.voiceCloneId == nil || appState.holdVoiceOnboarding
                    || (auth.isAnonymous && !authBypassed) {
            // holdVoiceOnboarding keeps this screen up through the final act
            // (greeting + theme pick) after the clone id has already landed.
            //
            // The anonymous clause is the crash/kill guard: the voice is now
            // built on a pre-signup session, and a session is not an account —
            // letting it through would hand someone an app whose data dies with
            // the install. The view reopens on its sign-up step.
            VoiceCloneOnboardingView()
        } else if !dailyCallOnboarded {
            // AFTER the clone, because the daily call is the clone's first
            // real job — they've just heard themselves speak fluently, so
            // "they'll phone you tomorrow" reads as a promise instead of a
            // permissions request. Existing installs see it once too; that's
            // how they learn the feature exists.
            DailyCallOnboardingView()
        } else if !paywallOnboarded {
            // LAST, and only for an account with something to buy. The voice
            // exists and has spoken by now, so the plans are priced against
            // something heard rather than promised — and the first tap on
            // Talk stops being where a hard paywall introduces itself.
            OnboardingPaywallView()
        } else {
            // A language switch swaps the entire scoped store set underneath
            // the tabs — rebuild the tree so every view re-reads from the new
            // language's stores (the stores themselves are repointed in
            // LanguageScope.repointStores; this only resets view state).
            RootTabView()
                .id(appState.targetLanguage)
        }
    }

    /// The static launch screen, redrawn in SwiftUI so the hand-off from
    /// `UILaunchScreen` to the first frame is invisible. Keep it in step with
    /// the `LaunchLogo` / `LaunchBackground` assets — nothing else may draw
    /// here, since anything the launch screen can't show would pop in.
    private var launchScreenTwin: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchLogo")
        }
        .ignoresSafeArea()
    }

    #if DEBUG
    /// Screenshot harness. Launch with `-onboardingPreview <screen>` to jump
    /// straight to one onboarding view, bypassing the auth gate — lets the
    /// simulator capture each first-run screen without an Apple sign-in.
    /// Screens: welcome · setup · voice · persona.
    private static var onboardingPreview: AnyView? {
        switch UserDefaults.standard.string(forKey: "onboardingPreview") {
        case "welcome":      return AnyView(WelcomeView())
        case "setup":        return AnyView(SetupFlowView())
        case "voice":        return AnyView(VoiceCloneOnboardingView())
        case "persona":      return AnyView(PersonaIntakeView())
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
        if let pixel = UIFont.appPixel(size) { return pixel }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

extension Font {
    /// Geist Pixel — the app's display face (page titles, big CEFR levels,
    /// hero numbers). Falls back to the system font if the bundled file is ever
    /// missing, so text never disappears.
    ///
    /// IMPORTANT: prefer the `View.geistPixel(_:)` modifier below. The app
    /// applies `.fontDesign(.rounded)` at the root, which re-designs (and so
    /// silently discards) a custom font in every descendant Text — so setting
    /// this Font alone renders as SF Rounded, not pixels. The View modifier
    /// pairs it with the required `.fontDesign(nil)` reset.
    static func geistPixel(_ size: CGFloat) -> Font {
        guard let ui = UIFont.appPixel(size) else { return .custom("GeistPixel-Square", size: size) }
        return Font(ui)
    }
}

extension UIFont {
    /// The display face as ONE voice across scripts. Geist Pixel carries no
    /// Hangul, so Korean titles used to drop to the system font mid-line —
    /// "복습" in SF beside "Talk" in pixels. The cascade hands those glyphs to
    /// Galmuri (bundled, subset), which is a pixel face too, so a mixed title
    /// like "nawana로 대화" reads in one design.
    ///
    /// Returns nil only if the bundled Latin face is missing, so callers keep
    /// their own fallback. Scaled through UIFontMetrics because the SwiftUI
    /// `.custom(_:size:)` this replaced tracked Dynamic Type.
    static func appPixel(_ size: CGFloat) -> UIFont? {
        guard UIFont(name: "GeistPixel-Square", size: size) != nil else { return nil }
        let descriptor = UIFontDescriptor(name: "GeistPixel-Square", size: size)
            .addingAttributes([.cascadeList: [UIFontDescriptor(name: "Galmuri14-Regular", size: size)]])
        return UIFontMetrics.default.scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

extension View {
    /// Renders text in Geist Pixel. Applies the font AND resets the inherited
    /// font design — without the reset, the root `.fontDesign(.rounded)` would
    /// override the custom face and the text would fall back to SF Rounded.
    func geistPixel(_ size: CGFloat) -> some View {
        font(.geistPixel(size)).fontDesign(nil)
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

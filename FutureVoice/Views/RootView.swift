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
    /// A signed-in account with practice already in iCloud, on an install
    /// that hasn't been set up: offer to continue from it (`SyncContinuePromptView`).
    @State private var showSyncOffer = false
    /// The same install, where the OTHER device never turned sync on — so
    /// there is nothing to offer and onboarding would read as an empty
    /// account (`SyncOtherDeviceHintView`).
    @State private var showOtherDeviceHint = false

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
            .task(id: auth.session?.user.id.uuidString ?? "") {
                await checkSecondDevice()
            }
            // The clone is adopted from the server by `restoreVoiceCloneFromCloud`,
            // which races the task above — and it is the whole tell that this
            // account has practice elsewhere. Re-ask when it lands, but never
            // while one of the two screens is up: the re-check would pull the
            // offer out from under a pull that is already running.
            .onChange(of: appState.voiceCloneId) { _, _ in
                guard !showSyncOffer, !showOtherDeviceHint else { return }
                Task { await checkSecondDevice() }
            }
    }

    /// The second device's question, asked once per account per install,
    /// only where setup hasn't happened yet — after that the toggle in Me is
    /// the place. Never shown for an anonymous session: nothing to key on.
    ///
    /// Two answers, not one. A zone means the practice is already in iCloud
    /// and can be pulled now (`SyncContinuePromptView`). NO zone plus an
    /// active voice clone means the practice exists but is sitting on a
    /// device that never turned sync on — which is where the opt-in lives,
    /// and is the one thing this install can't do anything about
    /// (`SyncOtherDeviceHintView`). Onboarding is what's left.
    private func checkSecondDevice() async {
        guard !appState.setupComplete, auth.isSignedIn,
              let uid = auth.session?.user.id.uuidString,
              !SyncEngine.shared.isEnabled
        else { showSyncOffer = false; showOtherDeviceHint = false; return }
        let cloud = await SyncEngine.shared.cloudHasData()
        if cloud == true {
            showOtherDeviceHint = false
            showSyncOffer = !SyncStore.wasOffered(userId: uid)
            return
        }
        // The account's ACTIVE clone, adopted from the server on sign-in: a
        // fresh install holding one is an account that recorded a voice on
        // another device. A clone made HERE can't reach this branch — setup
        // is complete long before the voice step.
        showSyncOffer = false
        showOtherDeviceHint = appState.voiceCloneId != nil
            && !SyncStore.wasOtherDeviceHinted(userId: uid)
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
                .animation(.easeOut(duration: 0.25), value: auth.didResolveInitialSession)
        }
        #else
        gatedContent
            // The launch-screen twin gives way to the page as a short fade,
            // not a cut: the cut read as the page snapping in under the
            // logo on every cold launch (2026-09-28). Keyed to the one
            // change that ends the twin, so nothing else in the gate
            // animates.
            .animation(.easeOut(duration: 0.25), value: auth.didResolveInitialSession)
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
        } else if showSyncOffer && !appState.setupComplete {
            SyncContinuePromptView { showSyncOffer = false }
        } else if showOtherDeviceHint && !appState.setupComplete {
            SyncOtherDeviceHintView(
                onFound: {
                    showOtherDeviceHint = false
                    showSyncOffer = true
                },
                onSkip: {
                    if let uid = auth.session?.user.id.uuidString {
                        SyncStore.setOtherDeviceHinted(userId: uid)
                    }
                    showOtherDeviceHint = false
                })
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
        // Same rule as `Font.geistPixel`: a chrome language the pixel cascade
        // can't spell (Chinese) gets the system face for the WHOLE title
        // rather than a title that is half pixel, half SF.
        if UILanguage.pixelFaceCoversChrome, let pixel = UIFont.appPixel(size) { return pixel }
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
        // The pixel cascade covers Latin, Hangul and kana/kanji, but NOT the
        // Traditional Chinese repertoire (Galmuri has 説/録/毎, not 說/錄/每),
        // and a missing glyph falls to the system font PER CHARACTER — a title
        // half pixel, half SF. For a chrome language the face can't spell,
        // the whole title goes system so it at least reads as one voice.
        // Exported pictures (the day card) stay pixel via `brandPixel`.
        guard UILanguage.pixelFaceCoversChrome else { return .system(size: size, weight: .semibold) }
        return brandPixel(size)
    }

    /// The pixel face regardless of chrome language — for surfaces whose
    /// text is pinned to English (the day card) and for anything else that
    /// draws only Latin/digits.
    static func brandPixel(_ size: CGFloat) -> Font {
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

    /// `geistPixel` for English-pinned exports — see `Font.brandPixel`.
    func brandPixel(_ size: CGFloat) -> some View {
        font(.brandPixel(size)).fontDesign(nil)
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

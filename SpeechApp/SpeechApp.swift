import SwiftUI
import AuthenticationServices

/// The speech app: nawana's Speech tab on its own. Same sources, same
/// Supabase project and account (`SPEECH_APP` set); this folder holds only
/// what the app needs around the tab — sign-in, the languages, settings.
@main
struct SpeechApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var auth = AuthService()

    init() {
        LanguageScope.migrateIfNeeded()
        Analytics.start()
    }

    var body: some Scene {
        WindowGroup {
            SpeechRootView()
                .environmentObject(appState)
                .environmentObject(auth)
                // One look for the whole app, a black stage (2026-11-12, founder).
                .preferredColorScheme(.dark)
                .tint(Arena.accent)
        }
    }
}

/// Signed out → welcome, then sign in. Then the tabs. English only for
/// now: `AppState` starts on English, the phone's own language for
/// everything explained, and B1, so there is nothing to ask.
struct SpeechRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.scenePhase) private var scenePhase

    /// The plan lives on the account and is read from the server, so a
    /// subscription bought or ended in nawana counts here on the next look.
    private func rereadPlan() {
        BillingGate.shared.invalidate()
        BillingGate.shared.warm()
    }

    /// `-speechPreview welcome|signin` opens an onboarding step on a signed-in
    /// simulator (nawana's `-onboardingPreview`).
    private var previewStep: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "speechPreview")
        #else
        return nil
        #endif
    }

    @Environment(\.displayScale) private var displayScale
    @State private var curtain = true

    private var launchMark: some View {
        ZStack {
            Color("LaunchBackground")
            Image("LaunchLogo")
        }
        .ignoresSafeArea()
    }

    /// What the curtain waits for: the pictures decoded, the board loaded
    /// (its 3D podium is drawn from it), the medal stills made, then a beat
    /// for the home to draw its loaded state. Never more than 4 seconds: a
    /// slow network costs the learner a podium that fills in later, not a
    /// launch that hangs.
    private func warmBehindCurtain() async {
        let started = Date()
        let scale = displayScale
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                async let art: Void = ChallengeArt.prepare()
                let boardBy = Date().addingTimeInterval(3)
                while await MainActor.run(body: { SpeechChallenges.shared.overall == nil }),
                      Date() < boardBy, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let scores = await MainActor.run {
                    SpeechChallenges.shared.standings.values.compactMap(\.myBest)
                }
                await MedalScene.prepare(scale: scale, scores: scores)
                await art
                // The loaded home draws (and its 3D compiles) under the mark.
                try? await Task.sleep(for: .milliseconds(450))
            }
            group.addTask { try? await Task.sleep(for: .seconds(4)) }
            await group.next()
            group.cancelAll()
        }
        // Long enough to read as a beat, not a flicker.
        let shown = Date().timeIntervalSince(started)
        if shown < 0.6 { try? await Task.sleep(for: .seconds(0.6 - shown)) }
    }

    var body: some View {
        Group {
            if previewStep == "signin" {
                NavigationStack { SpeechSignInView() }
            } else if previewStep == "welcome" {
                SpeechWelcomeView()
            } else if !auth.didResolveInitialSession {
                // The launch screen's twin (same colour, same mark, same
                // centring as `UILaunchScreen`) until the stored sign-in is
                // read: before this, a signed-in launch showed the welcome
                // page for a moment on its way to the tabs.
                launchMark
            } else if !auth.isSignedIn {
                SpeechWelcomeView()
            } else {
                // The home is drawn UNDER the launch mark and the mark stays
                // until it has settled (2026-11-13, founder: "it can stay on
                // the splash a little longer, as long as nothing stutters").
                // Its first layout, the 3D mic's first frames, the pictures
                // and the medal stills all happen behind it; a card tapped
                // in the first seconds no longer meets that work.
                ZStack {
                    SpeechAppTabs()
                    if curtain {
                        launchMark
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
                .task {
                    guard curtain else { return }
                    await warmBehindCurtain()
                    withAnimation(.easeOut(duration: 0.35)) { curtain = false }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: auth.didResolveInitialSession)
        .environment(\.locale, Locale(identifier: UILanguage.chromeLanguage))
        .onChange(of: auth.session?.user.id) { _, userId in
            if userId == nil {
                SpeechChallenges.forgetIdentity()
                SpeechGroups.shared.forget()
            }
            rereadPlan()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rereadPlan() }
        }
        #if DEBUG
        .task { await SpeechDevSignIn.runIfAsked() }
        #endif
    }
}

#if DEBUG
/// `-devEmail … -devPassword …` signs a simulator in, which has no Apple ID
/// session to sign in with (the same arguments nawana's debug harness takes).
enum SpeechDevSignIn {
    static func runIfAsked() async {
        let d = UserDefaults.standard
        guard let email = d.string(forKey: "devEmail"),
              let password = d.string(forKey: "devPassword") else { return }
        _ = try? await SupabaseProvider.shared.auth.signIn(email: email, password: password)
    }
}
#endif

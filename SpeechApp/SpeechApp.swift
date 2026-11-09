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
                .preferredColorScheme(appState.appearance.colorScheme)
        }
    }
}

/// Signed out → sign in. Signed in, languages not picked → the one setup
/// page. Then the Speech tab.
struct SpeechRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @AppStorage(SpeechSetup.doneKey) private var setupDone = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                SpeechWelcomeView()
            } else if !setupDone {
                SpeechSetupView { setupDone = true }
            } else {
                SpeechTab()
            }
        }
        .environment(\.locale, Locale(identifier: UILanguage.chromeLanguage))
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

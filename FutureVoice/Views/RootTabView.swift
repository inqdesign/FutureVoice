import SwiftUI

/// Four-tab structure built around the one engine that feeds everything —
/// Talk. You speak (Talk), study what it produced (Practice: review + shadow +
/// vocabulary), immerse by watching your fluent self (Watch), and manage
/// yourself (You: progress dashboard + account + settings). Progress used to
/// be its own tab but it's low-frequency analytics, so it folds under You;
/// vocabulary moved into Practice where it belongs as a study activity.
struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = .talk
    /// Beta intro shows ONCE, right after onboarding — in place of a paywall
    /// (no subscription during the beta). Explains the free quota + invites.
    @AppStorage("futurevoice.betaWelcomeSeen") private var betaWelcomeSeen = false
    @State private var showingBetaWelcome = false

    enum Tab: Hashable {
        case talk, practice, watch, you
    }

    var body: some View {
        TabView(selection: $selection) {
            ConversationHome()
                .tabItem { Label("Talk", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.talk)

            PracticeTab()
                .tabItem { Label("Practice", systemImage: "lightbulb.max") }
                .tag(Tab.practice)

            WatchTab()
                .tabItem { Label("Watch", systemImage: "person.2.wave.2") }
                .tag(Tab.watch)

            MeTab()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(Tab.you)
        }
        .onAppear {
            if !betaWelcomeSeen { showingBetaWelcome = true }
        }
        .fullScreenCover(isPresented: $showingBetaWelcome, onDismiss: { betaWelcomeSeen = true }) {
            BetaWelcomeView()
        }
    }
}

import SwiftUI

/// Native four-tab structure: Home (a cross-cutting dashboard + where you start
/// a conversation), Practice (review + shadow + vocabulary), Watch (personas),
/// and You (progress + account + settings). Starting a talk lives on Home — the
/// native tab bar can't host a custom action button, so it's a screen action.
struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = .home
    /// Beta intro shows ONCE, right after onboarding — in place of a paywall
    /// (no subscription during the beta). Explains the free quota + invites.
    @AppStorage("futurevoice.betaWelcomeSeen") private var betaWelcomeSeen = false
    @State private var showingBetaWelcome = false

    enum Tab: Hashable {
        case home, practice, watch, progress
    }

    var body: some View {
        TabView(selection: $selection) {
            ConversationHome()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            PracticeTab()
                .tabItem { Label("Practice", systemImage: "lightbulb.max") }
                .tag(Tab.practice)

            WatchTab()
                .tabItem { Label("Watch", systemImage: "person.2.wave.2") }
                .tag(Tab.watch)

            ProgressTab()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
        }
        .onAppear {
            if !betaWelcomeSeen { showingBetaWelcome = true }
        }
        .fullScreenCover(isPresented: $showingBetaWelcome, onDismiss: { betaWelcomeSeen = true }) {
            BetaWelcomeView()
        }
    }
}

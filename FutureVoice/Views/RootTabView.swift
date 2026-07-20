import SwiftUI

/// Native four-tab structure: Talk (the conversation home — a cross-cutting
/// dashboard + where you start a call; account/settings via MeTab from its
/// toolbar), Watch (topic + scenario books), Practice (review + shadow +
/// vocabulary), and Progress (measured CEFR + skills). Starting a talk lives
/// on the Talk screen — the native tab bar can't host a custom action button,
/// so it's a screen action.
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
                .tabItem { Label("Talk", systemImage: "phone.fill") }
                .tag(Tab.home)

            WatchTab()
                .tabItem { Label("Watch", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.watch)

            PracticeTab()
                .tabItem { Label("Practice", systemImage: "lightbulb.max") }
                .tag(Tab.practice)

            ProgressTab()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
        }
        .onAppear {
            if !betaWelcomeSeen { showingBetaWelcome = true }
            // Populate the home-screen widgets on first entry. The scenePhase
            // refresh only fires on background↔active transitions, so a cold
            // launch that goes straight to foreground wouldn't otherwise
            // publish a fresh snapshot.
            StudyWidgetRefresher.refresh()
        }
        // Study widget taps land in the Practice tab — futurevoice://vocab
        // additionally pushes the vocabulary notebook once the tab is up.
        // Note the transcript word links (futurevoice://word/…) are
        // intercepted locally by ConversationDetailView's OpenURLAction and
        // never reach here.
        .onOpenURL { url in
            guard url.scheme == "futurevoice" else { return }
            switch url.host {
            case "practice":
                selection = .practice
            case "vocab":
                selection = .practice
                appState.pendingPracticeRoute = .vocabulary
            case "expressions":
                selection = .practice
                appState.pendingPracticeRoute = .expressions
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showingBetaWelcome, onDismiss: { betaWelcomeSeen = true }) {
            BetaWelcomeView()
        }
    }
}

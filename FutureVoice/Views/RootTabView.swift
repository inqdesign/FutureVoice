import SwiftUI

/// Five-tab structure: the three practice modes (Talk / Practice / Watch),
/// then Progress (every language-development signal in one hub) and
/// Settings (account + configuration, nothing else). Growth and settings
/// used to share one "Me" tab, which buried both.
struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = .talk
    /// Trial-first paywall shows ONCE, right after onboarding completes —
    /// the Speak placement. Skippable; lives on in Settings → View plans.
    @AppStorage("futurevoice.paywallSeen") private var paywallSeen = false
    @State private var showingPaywall = false

    enum Tab: Hashable {
        case talk, practice, watch, progress, settings
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

            ProgressTab()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)

            MeTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onAppear {
            if !paywallSeen { showingPaywall = true }
        }
        .fullScreenCover(isPresented: $showingPaywall, onDismiss: { paywallSeen = true }) {
            PaywallView()
        }
    }
}

import SwiftUI

/// Phase 2 entry surface — replaces the single-screen ConversationView root
/// with a four-tab structure: Talk / Practice / Watch / Me. Each tab owns its
/// own NavigationStack so toolbars and titles don't collide.
struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = .talk

    enum Tab: Hashable {
        case talk, practice, watch, me
    }

    var body: some View {
        TabView(selection: $selection) {
            ConversationView()
                .tabItem { Label("Talk", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.talk)

            PracticeTab()
                .tabItem { Label("Practice", systemImage: "lightbulb.max") }
                .tag(Tab.practice)

            WatchTab()
                .tabItem { Label("Watch", systemImage: "person.2.wave.2") }
                .tag(Tab.watch)

            MeTab()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(Tab.me)
        }
    }
}

import SwiftUI

/// The bottom tabs: challenges, my scripts, ranking, me. Writing a script
/// starts from the "+" on My scripts.
struct SpeechAppTabs: View {
    private enum Item: Hashable { case challenges, scripts, ranking, me }

    @State private var selected: Item = .challenges

    var body: some View {
        TabView(selection: $selected) {
            SpeechTab(fixedPage: .challenges, openRanking: { selected = .ranking },
                      openMe: { selected = .me })
                .tabItem { Label("Challenges", systemImage: "trophy") }
                .tag(Item.challenges)
            SpeechTab(fixedPage: .mine)
                .tabItem { Label("My scripts", systemImage: "doc.text") }
                .tag(Item.scripts)
            NavigationStack {
                SpeechOverallBoardView(inTab: true)
            }
            .tabItem { Label("Ranking", systemImage: "list.number") }
            .tag(Item.ranking)
            SpeechMeView()
                .tabItem { Label("Me", systemImage: "person") }
                .tag(Item.me)
        }
        .tint(Arena.accent)
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "speechTab") {
            case "scripts": selected = .scripts
            case "ranking": selected = .ranking
            case "me": selected = .me
            default: break
            }
        }
        #endif
    }
}

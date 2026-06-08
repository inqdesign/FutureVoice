import SwiftUI

/// Tab home for Watch mode. Lists the user's saved counterparts; tapping one
/// pushes into a WatchSetupSheet (handled inside CounterpartsListView).
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewVoice = false

    var body: some View {
        NavigationStack {
            CounterpartsListView(showingNewVoice: $showingNewVoice)
                .navigationTitle("Watch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingNewVoice = true } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                }
        }
    }
}

import SwiftUI

/// Tab home for Watch mode. Two sections: recent dialogues across everyone
/// (replays are free — audio is content-cached) and the people library.
/// Surfacing past dialogues here, instead of burying them inside each
/// person's detail page, makes re-listening a one-tap habit.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewVoice = false

    private static let recentLimit = 5

    var body: some View {
        NavigationStack {
            Group {
                if appState.counterparts.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewVoice = true } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView()
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Content

    private var recentDialogues: [WatchDialogue] {
        Array(
            appState.watchDialogues
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(Self.recentLimit)
        )
    }

    private var content: some View {
        let recent = recentDialogues
        return List {
            if !recent.isEmpty {
                Section {
                    ForEach(recent) { d in
                        if let c = counterpart(for: d) {
                            NavigationLink {
                                WatchView(counterpart: c, savedDialogue: d)
                                    .environmentObject(appState)
                            } label: {
                                dialogueRow(d, counterpart: c)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { appState.deleteWatchDialogue(id: recent[i].id) }
                    }
                } header: {
                    Text("Recent dialogues")
                } footer: {
                    Text("Replays are free — the audio is already cached. Each person's full archive lives on their page.")
                }
            }

            Section("People") {
                ForEach(appState.counterparts) { c in
                    NavigationLink {
                        CounterpartDetailView(counterpart: c)
                            .environmentObject(appState)
                    } label: {
                        personRow(c)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.deleteCounterpart(id: c.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func counterpart(for d: WatchDialogue) -> Counterpart? {
        appState.counterparts.first { $0.id == d.counterpartId }
    }

    // MARK: - Rows

    private func dialogueRow(_ d: WatchDialogue, counterpart: Counterpart) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(d.displayTitle)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(counterpart.name)
                Text("·")
                Text(d.createdAt, style: .relative)
                Text("·")
                Text("\(d.turns.count) turns")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func personRow(_ c: Counterpart) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(c.name).font(.body.weight(.semibold))
                    if !c.relationship.isEmpty {
                        Text("· \(c.relationship)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("voiced by \(VoicePreset.by(id: c.voicePresetId).displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No one here yet", systemImage: "person.2")
        } description: {
            Text("Add someone from your real life — your best friend, a Kita parent, a coworker. The avatar will have natural conversations with them you can watch.")
        } actions: {
            Button("Add someone") { showingNewVoice = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

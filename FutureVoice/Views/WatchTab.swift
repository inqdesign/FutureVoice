import SwiftUI

/// Watch home, organized around PERSONAS — the people from the user's life
/// they converse with. A horizontal row of persona avatars (create-new
/// first) makes "I talk with many personas" the visual concept; the
/// conversation feed below is the shared output of all of them.
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
                        Label("New persona", systemImage: "plus")
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
            personasSection

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
                    Text("Conversations")
                } footer: {
                    Text("Replays are free — the audio is already cached. Each persona's full archive lives on their page.")
                }
            }
        }
    }

    // MARK: - Persona row

    private var personasSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    newPersonaCard
                    ForEach(appState.counterparts) { c in
                        NavigationLink {
                            CounterpartDetailView(counterpart: c)
                                .environmentObject(appState)
                        } label: {
                            personaAvatar(c)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteCounterpart(id: c.id)
                            } label: {
                                Label("Delete persona", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Your personas")
        }
    }

    private func personaAvatar(_ c: Counterpart) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(Self.initials(c.name))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(c.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(c.relationship)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }

    private var newPersonaCard: some View {
        Button { showingNewVoice = true } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 64, height: 64)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text("New")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                Text("persona")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private func counterpart(for d: WatchDialogue) -> Counterpart? {
        appState.counterparts.first { $0.id == d.counterpartId }
    }

    // MARK: - Rows

    private func dialogueRow(_ d: WatchDialogue, counterpart: Counterpart) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(Self.initials(counterpart.name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
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
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Create your first persona", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Bring someone from your real life into the app — your best friend, a Kita parent, your manager. Then watch yourself hold fluent conversations with them.")
        } actions: {
            Button("Create persona") { showingNewVoice = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

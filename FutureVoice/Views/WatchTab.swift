import SwiftUI

/// Watch home, organized around PERSONAS — the people from the user's life
/// they converse with. A horizontal row of persona avatars (create-new
/// first) makes "I talk with many personas" the visual concept; the
/// conversation feed below is the shared output of all of them.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewVoice = false
    @State private var showingNewScenario = false
    @State private var talkScenario: Scenario?
    @State private var watchScenarioTarget: Scenario?

    private static let recentLimit = 5

    var body: some View {
        NavigationStack {
            Group {
                if appState.counterparts.isEmpty && appState.watchDialogues.isEmpty && appState.scenarios.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Scenarios")
            .toolbarTitleDisplayMode(.inlineLarge)
            // No toolbar "+": each section owns its own add — the "New persona"
            // card in the People row and "New situation" in Situations — so a
            // single global "+" that only made personas was a confusing dupe.
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingNewScenario) {
                ScenarioBuilderSheet(counterparts: appState.counterparts) { newScenario in
                    appState.saveScenario(newScenario)
                }
                .environmentObject(appState)
            }
            .fullScreenCover(item: $talkScenario) { s in
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $watchScenarioTarget) { s in
                // Watch with the linked persona's real voice when set; else a
                // generic preset partner built from the role.
                let cp = s.counterpartId
                    .flatMap { id in appState.counterparts.first { $0.id == id } }
                    ?? ScenariosListSheet.watchCounterpart(for: s)
                WatchView(counterpart: cp,
                          customScenario: ScenariosListSheet.watchScenarioText(s))
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
            situationsSection

            if !recent.isEmpty {
                Section {
                    ForEach(recent) { d in
                        // Real counterpart when one exists; otherwise a
                        // reconstructed scenario partner (role + saved voice) so
                        // scenario watches still show up and replay here.
                        let c = counterpart(for: d) ?? scenarioCounterpart(for: d)
                        NavigationLink {
                            WatchView(counterpart: c, savedDialogue: d)
                                .environmentObject(appState)
                        } label: {
                            dialogueRow(d, counterpart: c)
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
            // Without a header this section left a large empty band up top,
            // out of step with "Situations" below which has one.
            Text("People")
        }
    }

    // MARK: - Situations (scenario library)

    private var situationsSection: some View {
        Section {
            ForEach(appState.scenarios) { s in
                HStack(spacing: 10) {
                    Button { talkScenario = s } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.displayTitle).font(.body).foregroundStyle(.primary)
                            if let name = linkedPersonaName(s) {
                                Label(name, systemImage: "person.crop.circle.fill")
                                    .font(.caption).foregroundStyle(.tint).lineLimit(1)
                            } else if !s.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(s.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { watchScenarioTarget = s } label: {
                        Label("Watch", systemImage: "play.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { appState.deleteScenario(id: s.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button { showingNewScenario = true } label: {
                Label("New situation", systemImage: "plus.circle")
            }
        } header: {
            Text("Situations")
        } footer: {
            Text("Tap a situation to talk it yourself, or Watch to hear your fluent self play it out with the other person.")
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

    /// Name of the persona linked to a scenario, if any — shown on the row so
    /// it's clear who you'll watch it with.
    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    /// Rebuild a throwaway partner for a scenario watch (no saved Counterpart)
    /// from the name + voice stored on the dialogue, so it lists and replays.
    private func scenarioCounterpart(for d: WatchDialogue) -> Counterpart {
        var c = Counterpart.empty
        c.name = d.speakerName ?? d.scenarioTitle
        c.voicePresetId = d.voicePresetId ?? VoicePreset.catalog.first!.id
        return c
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
                    Text(d.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
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
            Label("Practice a conversation", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Set up a situation and start right away — no persona needed. Or add someone from your real life for conversations that feel personal.")
        } actions: {
            Button("New situation") { showingNewScenario = true }
                .buttonStyle(.borderedProminent)
            Button("Create persona") { showingNewVoice = true }
                .buttonStyle(.bordered)
        }
    }
}

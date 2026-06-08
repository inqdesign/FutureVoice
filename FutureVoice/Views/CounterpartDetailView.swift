import SwiftUI

/// Read-only profile + scenario library + past-dialogue archive for one
/// counterpart. Tap row in the list → land here → Edit (top trailing) or
/// Start watching (bottom CTA) or tap a saved scenario / past dialogue.
///
/// Tracks the counterpart by ID and reads live from `appState.counterparts`
/// so updates (Edit / Scenarios refresh) reflect immediately without a
/// re-push.
struct CounterpartDetailView: View {
    let counterpartId: UUID
    @EnvironmentObject private var appState: AppState
    @State private var showingEdit = false
    @State private var showingWatch = false
    @State private var loadingScenarios = false
    @State private var scenarioError: String?
    @State private var customWatchTarget: CustomLaunch?

    struct CustomLaunch: Identifiable {
        let id = UUID()
        let counterpart: Counterpart
        let topic: SuggestedTopic
    }

    init(counterpartId: UUID) {
        self.counterpartId = counterpartId
    }

    /// Backwards-compat init used by NavigationLink call sites that already
    /// passed a Counterpart by value.
    init(counterpart: Counterpart) {
        self.counterpartId = counterpart.id
    }

    private var counterpart: Counterpart? {
        appState.counterparts.first(where: { $0.id == counterpartId })
    }

    var body: some View {
        Group {
            if let c = counterpart {
                body(for: c)
            } else {
                ContentUnavailableView("This person has been deleted",
                                       systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    @ViewBuilder
    private func body(for c: Counterpart) -> some View {
        List {
            Section { headerRow(c) }

            sectionIfAny("About them", has: !c.location.isEmpty) {
                row(c.location)
            }

            sectionIfAny("Your history together",
                         has: !c.howWeMet.isEmpty || !c.background.isEmpty) {
                row(c.howWeMet, label: "How you met")
                row(c.background, label: "Shared context")
            }

            sectionIfAny("How they talk",
                         has: !c.conversationStyle.isEmpty || !c.commonTopics.isEmpty) {
                row(c.conversationStyle, label: "Style")
                row(c.commonTopics, label: "Common topics")
            }

            sectionIfAny("Notes", has: !c.freeNotes.isEmpty) {
                row(c.freeNotes)
            }

            scenariosSection(for: c)
            pastDialoguesSection(for: c)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(c.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showingWatch = true
            } label: {
                Label("Start watching", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .sheet(isPresented: $showingEdit) {
            CounterpartFormView(initial: c)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingWatch) {
            WatchSetupSheet(counterpart: c)
                .environmentObject(appState)
        }
        .sheet(item: $customWatchTarget) { target in
            NavigationStack {
                WatchView(counterpart: target.counterpart, topic: target.topic)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Header

    private func headerRow(_ c: Counterpart) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                    .font(.title2.weight(.semibold))
                if !c.relationship.isEmpty {
                    Text(c.relationship)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("voiced by \(VoicePreset.by(id: c.voicePresetId).displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Scenarios

    @ViewBuilder
    private func scenariosSection(for c: Counterpart) -> some View {
        Section {
            if c.savedScenarios.isEmpty {
                if loadingScenarios {
                    HStack {
                        ProgressView()
                        Text("Building scenarios for \(c.name)…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await regenerateScenarios(for: c) }
                    } label: {
                        Label("Generate scenarios for \(c.name)",
                              systemImage: "sparkles")
                    }
                }
            } else {
                ForEach(c.savedScenarios) { scenario in
                    Button {
                        customWatchTarget = CustomLaunch(counterpart: c, topic: scenario)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scenario.title)
                                .foregroundStyle(.primary)
                            if !scenario.blurb.isEmpty {
                                Text(scenario.blurb)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let err = scenarioError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Scenarios")
                Spacer()
                if !c.savedScenarios.isEmpty {
                    Button {
                        Task { await regenerateScenarios(for: c) }
                    } label: {
                        if loadingScenarios {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .disabled(loadingScenarios)
                }
            }
        } footer: {
            Text("Grounded in your relationship with \(c.name) — situations you'd actually be in together. Tap to watch a dialogue play out.")
        }
    }

    private func regenerateScenarios(for c: Counterpart) async {
        loadingScenarios = true
        scenarioError = nil
        defer { loadingScenarios = false }
        do {
            let fresh = try await TopicEngine.suggestForCounterpart(
                persona: appState.persona,
                counterpart: c,
                targetLanguage: appState.targetLanguage
            )
            var updated = c
            updated.savedScenarios = fresh
            appState.saveCounterpart(updated)
        } catch {
            self.scenarioError = "Couldn't refresh scenarios: \(error.localizedDescription)"
        }
    }

    // MARK: - Past dialogues

    @ViewBuilder
    private func pastDialoguesSection(for c: Counterpart) -> some View {
        let past = appState.watchDialogues
            .filter { $0.counterpartId == c.id }
            .sorted { $0.createdAt > $1.createdAt }
        if !past.isEmpty {
            Section("Past dialogues") {
                ForEach(past) { d in
                    NavigationLink {
                        WatchView(counterpart: c, savedDialogue: d)
                            .environmentObject(appState)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.scenarioTitle)
                                .font(.body)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(d.createdAt, style: .relative)
                                Text("·")
                                Text("\(d.turns.count) turns")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { appState.deleteWatchDialogue(id: past[i].id) }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionIfAny<Content: View>(_ title: String,
                                              has: Bool,
                                              @ViewBuilder content: () -> Content) -> some View {
        if has {
            Section(title) { content() }
        }
    }

    @ViewBuilder
    private func row(_ text: String, label: String? = nil) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let label = label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(trimmed)
                    .font(.body)
            }
            .padding(.vertical, 2)
        }
    }
}

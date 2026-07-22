import SwiftUI

/// MANAGEMENT page for one counterpart — profile, cached situation ideas,
/// and the past-dialogue archive. Watching is deliberately NOT launched from
/// here: the one watch flow lives on the Watch tab (tap the persona bubble →
/// situation composer). Keeping the two apart means every scene goes through
/// the same composer and mints the same Practice book.
///
/// Tracks the counterpart by ID and reads live from `appState.counterparts`
/// so updates (Edit / Ideas refresh) reflect immediately without a re-push.
struct CounterpartDetailView: View {
    let counterpartId: UUID
    @EnvironmentObject private var appState: AppState
    @State private var showingEdit = false
    @State private var loadingScenarios = false
    @State private var scenarioError: String?

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
        .sheet(isPresented: $showingEdit) {
            CounterpartFormView(initial: c)
                .environmentObject(appState)
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
            }
            if let err = scenarioError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Situation ideas")
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
            Text("Grounded in your relationship with \(c.name) — these appear as ideas when you tap them on the Watch tab.")
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
                            Text(d.displayTitle)
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

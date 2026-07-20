import SwiftUI

/// The Watch tab's "+" picker — mirrors the Talk tab's topic picker
/// (`ScenariosListSheet`): pick a story matched to your interests (or type
/// any topic) and it becomes a topic BOOK — a `Scenario` with `isTopic` set —
/// running the exact same curriculum pipeline as a situation book: one
/// generated scene to watch, words/expressions/shadow lines to master, Talk
/// to practice it live. Building a situation book lives in the toolbar "+",
/// same as the Talk picker.
///
/// The partner defaults to a generic friend (the scene's counterpart role);
/// picking one of your real people links the book to them (`counterpartId`),
/// so the scene uses their persona and voice.
struct WatchTopicSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Called with the created (or re-opened) book; the host navigates into
    /// ScenarioDetailView, where the curriculum generates on open.
    let onCreated: (Scenario) -> Void

    /// nil = the generic friend partner.
    @State private var partnerId: UUID?
    @State private var customTopic = ""
    @State private var showingBuilder = false

    var body: some View {
        NavigationStack {
            Form {
                partnerSection
                NewsTopicSection(
                    footer: "Tap a story to make it a book — a scene to watch, plus its words and lines to master.",
                    onPick: { item in
                        create(title: item.title, blurb: item.blurb)
                    }
                )
                customTopicSection
            }
            .navigationTitle("What to watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Create") {
                        create(title: customTopic.trimmingCharacters(in: .whitespaces), blurb: "")
                    }
                    .disabled(customTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button { showingBuilder = true } label: {
                        Label("Build a scenario", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                ScenarioBuilderSheet(counterparts: appState.counterparts) { newScenario in
                    appState.saveScenario(newScenario)
                    onCreated(newScenario)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Create

    private func create(title: String, blurb: String) {
        // Same story picked twice → reopen the existing book instead of
        // shelving a duplicate (each book costs a curriculum generation).
        if let existing = appState.scenarios.first(where: {
            $0.isTopic == true && $0.environment == title
        }) {
            onCreated(existing)
            dismiss()
            return
        }
        let partner = partnerId.flatMap { id in appState.counterparts.first { $0.id == id } }
        var s = Scenario(
            environment: title,
            // Mirrors the builder's rule: a linked persona's relationship is
            // the role; otherwise a generic friend plays the other side.
            role: (partner?.relationship.isEmpty == false ? partner!.relationship : partner?.name)
                ?? "a friend",
            notes: blurb
        )
        s.counterpartId = partnerId
        s.isTopic = true
        appState.saveScenario(s)
        onCreated(s)
        dismiss()
    }

    // MARK: - Partner

    @ViewBuilder
    private var partnerSection: some View {
        Section {
            if appState.counterparts.isEmpty {
                Label("A friend", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Partner", selection: $partnerId) {
                    Text("A friend").tag(UUID?.none)
                    ForEach(appState.counterparts) { c in
                        Text(c.name).tag(UUID?.some(c.id))
                    }
                }
            }
        } header: {
            Text("Talking with")
        } footer: {
            Text("Your fluent self takes one side of the scene; the partner takes the other.")
        }
    }

    // MARK: - Custom topic

    private var customTopicSection: some View {
        Section("Or any topic on your mind") {
            TextField("e.g. Whether the new F1 season format is actually better",
                      text: $customTopic, axis: .vertical)
                .lineLimit(2...4)
        }
    }
}

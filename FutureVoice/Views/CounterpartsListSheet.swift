import SwiftUI

/// People the user actually interacts with in their life. Each one becomes
/// a "counterpart" the avatar can have a Watch-mode dialogue with.
/// Reusable body view — tab-embeddable, supplies its own sheet plumbing.
/// Exposes a toolbar-friendly "Add" trigger via the @Binding showingNewVoice.
struct CounterpartsListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showingNewVoice: Bool

    // Editing/watch live inside `CounterpartDetailView` now; the list only
    // routes to detail and offers Delete via swipe.

    var body: some View {
        Group {
            if appState.counterparts.isEmpty {
                ContentUnavailableView {
                    Label("No one here yet", systemImage: "person.2")
                } description: {
                    Text("Add someone from your real life — your best friend, a Kita parent, a coworker. The avatar will have natural conversations with them you can watch.")
                } actions: {
                    Button("Add someone") { showingNewVoice = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(appState.counterparts) { c in
                        // Tap → detail view (read-only summary + Edit / Watch
                        // CTAs). Native iOS pattern, makes edit discoverable
                        // without a swipe and gives the user a place to see
                        // everything they've stored about that person.
                        NavigationLink {
                            CounterpartDetailView(counterpart: c)
                                .environmentObject(appState)
                        } label: {
                            row(c)
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
        .sheet(isPresented: $showingNewVoice) {
            CounterpartVoiceIntakeView()
                .environmentObject(appState)
        }
    }

    private func row(_ c: Counterpart) -> some View {
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
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Form

struct CounterpartFormView: View {
    let initial: Counterpart?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Counterpart

    init(initial: Counterpart?) {
        self.initial = initial
        _draft = State(initialValue: initial ?? .empty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Relationship (e.g. Best friend, Kita parent, Manager)",
                              text: $draft.relationship)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Who")
                } footer: {
                    Text("Required. Everything below is optional but the more you fill in, the more the simulated dialogues feel like the real person.")
                }

                Section("About them") {
                    TextField("Where they live, what they do",
                              text: $draft.location, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Your history together") {
                    TextField("How you met (and how long)",
                              text: $draft.howWeMet, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Shared context, memories, inside jokes",
                              text: $draft.background, axis: .vertical)
                        .lineLimit(2...8)
                }

                Section("How they talk") {
                    TextField("Style (e.g. Direct, loves jokes / Formal, careful)",
                              text: $draft.conversationStyle, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("What you usually talk about",
                              text: $draft.commonTopics, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Voice") {
                    Picker("Voice", selection: $draft.voicePresetId) {
                        ForEach(VoicePreset.catalog) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.displayName)
                                Text("\(preset.gender) · \(preset.accent) · \(preset.description)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(preset.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Anything else") {
                    TextField("Free notes — quirks, recent events, anything that helps",
                              text: $draft.freeNotes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(initial == nil ? "New person" : "Edit person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        appState.saveCounterpart(draft)
                        dismiss()
                    }
                    .disabled(!draft.isMinimallyComplete)
                }
            }
        }
    }
}

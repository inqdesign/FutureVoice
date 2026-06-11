import SwiftUI

// The counterpart LIST moved into WatchTab (it owns the recent-dialogues +
// people layout now). This file keeps the shared add/edit form.

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

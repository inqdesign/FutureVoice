import SwiftUI

/// Focused editor for the user's interests — the signal behind the "In the
/// news" topics. Reachable straight from the topic picker so tuning what shows
/// up is one tap away, without diving into the full persona screen.
struct InterestsEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var interests: [String] = []
    @State private var draft = ""
    @State private var loaded = false

    private static let presets = [
        "AI / tech", "parenting", "language learning", "music", "podcasts",
        "cooking", "travel", "sports", "fashion", "finance", "science", "art"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    chipGrid
                    TextField("Add your own (comma-separated)", text: $draft)
                        .onSubmit(mergeDraft)
                } header: {
                    Text("Your interests")
                } footer: {
                    Text("Tap to toggle, or type your own and hit return. Current stories matched to these show up under “In the news”.")
                }
            }
            .navigationTitle("Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Load once — re-firing onAppear (keyboard / detent changes)
                // must not wipe the user's in-progress toggles.
                guard !loaded else { return }
                interests = appState.persona?.interests ?? []
                loaded = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var chipGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Self.presets, id: \.self) { tag in
                let on = interests.contains(tag)
                Button {
                    toggle(tag)
                } label: {
                    Text(tag)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                        .background(
                            Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ tag: String) {
        if let idx = interests.firstIndex(of: tag) {
            interests.remove(at: idx)
        } else {
            interests.append(tag)
        }
    }

    private func mergeDraft() {
        let pieces = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in pieces where !interests.contains(p) { interests.append(p) }
        draft = ""
    }

    private func save() {
        mergeDraft()
        var p = appState.persona ?? .empty
        p.interests = interests
        appState.savePersona(p)
        dismiss()
    }
}

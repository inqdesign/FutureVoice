import SwiftUI

/// First-run persona collection. Three lightweight screens — name, life
/// context, English world — that the fluent-self avatar uses as ground truth
/// for every subsequent conversation. Skipping a field is fine; richer
/// persona = more lived-in English from the avatar.
///
/// Re-used by `PersonaEditSheet` for later edits.
struct PersonaOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0
    @State private var persona: UserPersona
    @State private var isEditing: Bool
    @State private var interestsDraft: String = ""
    @State private var situationsDraft: String = ""

    init(initialPersona: UserPersona? = nil) {
        _persona = State(initialValue: initialPersona ?? .empty)
        _isEditing = State(initialValue: initialPersona != nil)
    }

    private static let interestPresets = [
        "AI / tech", "parenting", "language learning", "music", "podcasts",
        "cooking", "travel", "sports", "fashion", "finance", "science", "art"
    ]
    private static let situationPresets = [
        "Work meetings", "Client calls", "Kita / school",
        "Doctor / clinic", "Travel", "Online shopping",
        "Customer service", "Streaming / shows", "Reading articles",
        "Daily small talk"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Form {
                    Group {
                        switch step {
                        case 0: nameStep
                        case 1: lifeStep
                        default: worldStep
                        }
                    }
                }
                Spacer(minLength: 0)
                bottomBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch step {
        case 0: return isEditing ? "Profile" : "Hi"
        case 1: return "Your life"
        default: return "Your English world"
        }
    }

    // MARK: - Step 1 · Name

    private var nameStep: some View {
        Section {
            TextField("What should I call you?", text: $persona.displayName)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Your fluent self wants to know you")
        } footer: {
            Text("The more you share, the more I'll sound like a version of you — not a textbook.")
        }
    }

    // MARK: - Step 2 · Life

    private var lifeStep: some View {
        Group {
            Section("Where you live") {
                TextField("City", text: $persona.city)
                    .textInputAutocapitalization(.words)
                TextField("Country", text: $persona.country)
                    .textInputAutocapitalization(.words)
                TextField("How long? (optional)", text: $persona.lengthOfStay)
            }
            Section("What you do") {
                TextField("e.g. Solo founder of an AI app for parents", text: $persona.occupation, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Who you live with (optional)") {
                TextField("e.g. Wife and 4yo daughter at Kita", text: $persona.household, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    // MARK: - Step 3 · World

    private var worldStep: some View {
        Group {
            Section {
                chipGrid(presets: Self.interestPresets, selected: persona.interests) { tag in
                    toggle(&persona.interests, tag)
                }
                TextField("Add your own (comma-separated)", text: $interestsDraft)
                    .onSubmit { mergeDraft(into: &persona.interests, from: &interestsDraft) }
            } header: {
                Text("Interests")
            } footer: {
                Text("Tap to toggle. Or type your own and hit return.")
            }

            Section {
                chipGrid(presets: Self.situationPresets, selected: persona.englishSituations) { tag in
                    toggle(&persona.englishSituations, tag)
                }
                TextField("Add your own (comma-separated)", text: $situationsDraft)
                    .onSubmit { mergeDraft(into: &persona.englishSituations, from: &situationsDraft) }
            } header: {
                Text("When do you most need English?")
            }

            Section("Anything else (optional)") {
                TextField("Quirks, preferences, anything that helps me sound like you", text: $persona.freeNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Chip grid

    @ViewBuilder
    private func chipGrid(presets: [String], selected: [String], onTap: @escaping (String) -> Void) -> some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(presets, id: \.self) { tag in
                let on = selected.contains(tag)
                Button {
                    onTap(tag)
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

    private func toggle(_ list: inout [String], _ value: String) {
        if let idx = list.firstIndex(of: value) {
            list.remove(at: idx)
        } else {
            list.append(value)
        }
    }

    private func mergeDraft(into list: inout [String], from draft: inout String) {
        let pieces = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in pieces where !list.contains(p) { list.append(p) }
        draft = ""
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    step -= 1
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button {
                if step < 2 {
                    step += 1
                } else {
                    finish()
                }
            } label: {
                Text(step < 2 ? "Next" : (isEditing ? "Save" : "Start talking"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !persona.displayName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return !persona.city.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func finish() {
        // Make sure any unsubmitted free text gets folded in.
        mergeDraft(into: &persona.interests, from: &interestsDraft)
        mergeDraft(into: &persona.englishSituations, from: &situationsDraft)
        appState.savePersona(persona)
        dismiss()   // closes the edit sheet; on first-onboarding RootView swaps anyway
    }
}

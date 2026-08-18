import SwiftUI
import PhotosUI

/// Persona EDIT form (Me → Profile) — three lightweight screens covering the
/// same fields the guided first-run flow (`PersonaIntakeView`) collects. The
/// persona is the fluent-self avatar's ground truth for every conversation;
/// richer persona = more lived-in speech from the avatar.
struct PersonaOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0
    @State private var persona: UserPersona
    @State private var isEditing: Bool
    @State private var interestsDraft: String = ""
    @State private var situationsDraft: String = ""
    @State private var avatarPick: PhotosPickerItem?

    init(initialPersona: UserPersona? = nil) {
        var p = initialPersona ?? .empty
        // First-run only: seed the name from what Apple gave us at sign-in, so
        // the user isn't retyping something we already know. They can edit it.
        if initialPersona == nil, p.displayName.isEmpty,
           let appleName = UserDefaults.standard.string(forKey: AuthService.appleNameKey) {
            p.displayName = appleName
        }
        _persona = State(initialValue: p)
        _isEditing = State(initialValue: initialPersona != nil)
    }

    // Also the preset source for `PersonaIntakeView`'s chip cards.
    static let interestPresets = [
        "AI / tech", "parenting", "language learning", "music", "podcasts",
        "cooking", "travel", "sports", "fashion", "finance", "science", "art"
    ]
    static let situationPresets = [
        "Work meetings", "Client calls", "Kita / school",
        "Doctor / clinic", "Travel", "Online shopping",
        "Customer service", "Streaming / shows", "Reading articles",
        "Daily small talk"
    ]

    /// What a preset chip READS as. The stored value stays English on purpose:
    /// it is written into `persona.interests` / `.situations`, injected into
    /// every prompt built from the persona, and matched by string to decide
    /// which chip is on — localizing the value would rewrite saved profiles and
    /// un-select every chip an existing user had already picked. Only the label
    /// moves. A tag the learner typed themselves falls through unchanged, which
    /// is correct: it is already in their words.
    static func presetLabel(_ tag: String) -> String {
        switch tag {
        case "AI / tech":         return chrome("AI / tech")
        case "parenting":         return chrome("parenting")
        case "language learning": return chrome("language learning")
        case "music":             return chrome("music")
        case "podcasts":          return chrome("podcasts")
        case "cooking":           return chrome("cooking")
        case "travel":            return chrome("travel")
        case "sports":            return chrome("sports")
        case "fashion":           return chrome("fashion")
        case "finance":           return chrome("finance")
        case "science":           return chrome("science")
        case "art":               return chrome("art")
        case "Work meetings":     return chrome("Work meetings")
        case "Client calls":      return chrome("Client calls")
        case "Kita / school":     return chrome("Kita / school")
        case "Doctor / clinic":   return chrome("Doctor / clinic")
        case "Travel":            return chrome("Travel")
        case "Online shopping":   return chrome("Online shopping")
        case "Customer service":  return chrome("Customer service")
        case "Streaming / shows": return chrome("Streaming / shows")
        case "Reading articles":  return chrome("Reading articles")
        case "Daily small talk":  return chrome("Daily small talk")
        default:                  return tag
        }
    }

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
        case 0: return isEditing ? chrome("Profile") : chrome("Hi")
        case 1: return chrome("Your life")
        default: return chrome("Your \(LanguageCatalog.learnerName(appState.targetLanguage)) world")
        }
    }

    // MARK: - Step 1 · Name

    private var nameStep: some View {
        Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $avatarPick, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatar(initials: persona.displayName, size: 88)
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 4)

            TextField("What should I call you?", text: $persona.displayName)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Your fluent self wants to know you")
        } footer: {
            Text(explain("The more you share, the more I'll sound like a version of you — not a textbook."))
        }
        .onChange(of: avatarPick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    AvatarStore.shared.save(img)
                }
            }
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
                Text(explain("Tap to toggle. Or type your own and hit return."))
            }

            Section {
                chipGrid(presets: Self.situationPresets, selected: persona.situations) { tag in
                    toggle(&persona.situations, tag)
                }
                TextField("Add your own (comma-separated)", text: $situationsDraft)
                    .onSubmit { mergeDraft(into: &persona.situations, from: &situationsDraft) }
            } header: {
                Text(explain("What do you want to be able to do in \(LanguageCatalog.learnerName(appState.targetLanguage))?"))
            } footer: {
                Text(explain("What you pick becomes your goal — practice aims at it."))
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
                    Text(Self.presetLabel(tag))
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
        mergeDraft(into: &persona.situations, from: &situationsDraft)
        appState.savePersona(persona)
        dismiss()   // closes the edit sheet; on first-onboarding RootView swaps anyway
    }
}

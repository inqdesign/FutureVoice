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
    /// "Show the talk" on a remembered line — the session it was heard in.
    @State private var talkToShow: Session?

    init(initialPersona: UserPersona? = nil, startStep: Int = 0) {
        _step = State(initialValue: startStep)
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
        .sheet(item: $talkToShow) { session in
            NavigationStack {
                ConversationDetailView(session: session)
                    .environmentObject(appState)
            }
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
            // On the list's own row background, not a clear one: a floating
            // avatar over the grouped backdrop reads as cut off from the name
            // field under it, which is the same card. The separator is hidden
            // because the list insets it to the row's leading CONTENT, and
            // this row's content is centered — it drew a half-width line.
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)

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
            rememberedSection
        }
    }

    /// The half of this profile the learner didn't type: what the fluent self
    /// picked up in their calls. Editable and deletable — it can only be as
    /// right as what it heard, and what it heard came through a transcriber:
    /// a misheard name or a wrong number lands here as a fact about the
    /// learner, and until 2026-09-03 the only remedy was to delete the whole
    /// line and hope the next call re-learned it right. A line emptied in
    /// place is dropped on save, so clearing is the same gesture as fixing.
    ///
    /// Two lists since 2026-09-16, by `PersonaNote.Kind`: the durable lines
    /// ("What I know about you") and the ones that fade ("Right now"). Every
    /// row shows the sentence the line was distilled from (`heard`) as its
    /// evidence, and a "Strangers hear" line that says what leaves the
    /// notebook — nothing, the gist, or everything (`PersonaNote.share`),
    /// with the model's reason for its pick. The learner moves the rung from
    /// the trailing button or the long-press menu; the moves are recorded on
    /// save (`recordShareCorrections`) so the next summary call sorts the way
    /// this person does. The last section is the paragraph strangers actually
    /// get, composed live from the draft, so a change to a rung is visible in
    /// the same screen.
    @ViewBuilder
    private var rememberedSection: some View {
        let hasFacts = persona.learnedNotes.contains { $0.kind == .fact }
        let hasRecent = persona.learnedNotes.contains { $0.kind == .now }
        if hasFacts {
            Section {
                ForEach($persona.learnedNotes) { $note in
                    if note.kind == .fact { noteRow($note) }
                }
            } header: {
                Text("What I know about you")
            } footer: {
                Text(explain("From your talks. Tap a line to fix what I misheard. For each one, choose what strangers hear — nothing, just the gist, or everything. I always know the whole line."))
            }
        }
        if hasRecent {
            Section {
                ForEach($persona.learnedNotes) { $note in
                    if note.kind == .now { noteRow($note) }
                }
            } header: {
                Text("Right now")
            } footer: {
                Text(explain("True for a while. I forget these on my own after a month — or tell me when it's over."))
            }
        }
        if hasFacts || hasRecent {
            Section {
                ComposedIntroLoader(persona: persona, language: appState.targetLanguage)
            } header: {
                Text("What strangers can see")
            } footer: {
                Text(explain("The intro another learner's phone speaks as you in Find people. Change it or take it down in Me → Find people."))
            }
        }
    }

    private func noteRow(_ note: Binding<PersonaNote>) -> some View {
        let n = note.wrappedValue
        let gistBinding = Binding<String>(
            get: { note.wrappedValue.gist ?? "" },
            set: { note.wrappedValue.gist = $0.isEmpty ? nil : $0 })
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: note.text, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                // The evidence: what they actually said, and when. A learner
                // deciding whether to fix a line needs to see what it was
                // made from, not just that it exists.
                if let heard = n.heard, !heard.isEmpty {
                    Text(explain("You said “\(heard)”"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(n.learnedAt, format: .relative(presentation: .named))
                    if n.kind == .now, let fade = fadeLabel(n) {
                        Text("·")
                        Text(fade)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // What leaves the notebook, and the model's reason for it.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Strangers hear:")
                        .foregroundStyle(.secondary)
                    switch n.share {
                    case .nothing:
                        Text("nothing")
                    case .all:
                        Text("everything")
                    case .gist:
                        TextField(chrome("the gist, in a few words"), text: gistBinding, axis: .vertical)
                            .lineLimit(1...2)
                    }
                }
                .font(.caption)
                if let why = n.why, !why.isEmpty {
                    Text(why)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Menu {
                sharePicker(note)
            } label: {
                Image(systemName: shareIcon(n.share))
                    .font(.subheadline)
                    .foregroundStyle(n.share == .all ? Color.secondary : Color.accentColor)
                    .frame(width: 24)
            }
            .accessibilityLabel(shareLabel(n.share))
        }
        .contextMenu {
            if let sid = n.sessionId,
               let session = SessionStore.shared.loadAcrossLanguages().first(where: { $0.id == sid }) {
                Button {
                    talkToShow = session
                } label: {
                    Label("Show the talk", systemImage: "waveform")
                }
            }
            Menu {
                sharePicker(note)
            } label: {
                Label("Strangers hear", systemImage: shareIcon(n.share))
            }
            if n.kind == .now {
                Button {
                    forget(n.id)
                } label: {
                    Label("That's over now", systemImage: "checkmark")
                }
            }
            Button(role: .destructive) {
                forget(n.id)
            } label: {
                Label("Forget this", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                forget(n.id)
            } label: {
                Label("Forget this", systemImage: "trash")
            }
        }
    }

    /// The three rungs. "The gist" is offered only when there is one to
    /// hand out — the model found no honest outline for some lines, and a
    /// rung that would send nothing is not a choice.
    @ViewBuilder
    private func sharePicker(_ note: Binding<PersonaNote>) -> some View {
        let hasGist = !(note.wrappedValue.gist ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        Picker("Strangers hear", selection: note.share) {
            Label("Nothing", systemImage: shareIcon(.nothing)).tag(PersonaNote.Share.nothing)
            if hasGist || note.wrappedValue.share == .gist {
                Label("Just the gist", systemImage: shareIcon(.gist)).tag(PersonaNote.Share.gist)
            }
            Label("Everything", systemImage: shareIcon(.all)).tag(PersonaNote.Share.all)
        }
    }

    private func shareIcon(_ share: PersonaNote.Share) -> String {
        switch share {
        case .nothing: return "lock.fill"
        case .gist: return "text.redaction"
        case .all: return "lock.open"
        }
    }

    private func shareLabel(_ share: PersonaNote.Share) -> String {
        switch share {
        case .nothing: return explain("Strangers hear nothing — only your fluent self knows this")
        case .gist: return explain("Strangers hear the gist — the outline, not the details")
        case .all: return explain("Strangers hear everything — may appear in your Find people intro")
        }
    }

    /// "fades in 3 weeks" for a `now` line — how long until the app forgets
    /// it on its own.
    private func fadeLabel(_ n: PersonaNote) -> String? {
        let left = n.learnedAt.addingTimeInterval(PersonaNote.nowHorizon).timeIntervalSinceNow
        guard left > 0 else { return nil }
        let days = Int(left / 86_400)
        if days >= 14 { return explain("fades in \(days / 7) weeks") }
        if days >= 2 { return explain("fades in \(days) days") }
        return explain("fades tomorrow")
    }

    private func forget(_ id: UUID) {
        persona.learnedNotes.removeAll { $0.id == id }
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
                    // Editing: each page is saved as it's left, so a sheet
                    // swiped away on page three keeps what pages one and two
                    // said. First run keeps the single save at the end —
                    // a persona on file is what swaps RootView out of setup.
                    if isEditing { commit() }
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
        commit()
        dismiss()   // closes the edit sheet; on first-onboarding RootView swaps anyway
    }

    /// Writes the draft as it stands. Skipped when nothing changed, because
    /// `savePersona` also wipes topic suggestions and re-syncs the public
    /// intro — a Next that edited nothing must not do either.
    private func commit() {
        // Make sure any unsubmitted free text gets folded in.
        mergeDraft(into: &persona.interests, from: &interestsDraft)
        mergeDraft(into: &persona.situations, from: &situationsDraft)
        // A remembered line edited down to nothing was meant as a delete.
        persona.learnedNotes = persona.learnedNotes.compactMap { note in
            let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var kept = note
            kept.text = text
            return kept
        }
        // What the learner moved by hand is what the next summary call
        // learns to sort from. Compared against what is on file — the last
        // page saved, or the profile as the sheet opened — never the draft.
        persona.recordShareCorrections(from: appState.persona?.learnedNotes ?? [])
        if let saved = appState.persona, Self.sameContent(saved, persona) { return }
        appState.savePersona(persona)
    }

    private static func sameContent(_ a: UserPersona, _ b: UserPersona) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let da = try? encoder.encode(a), let db = try? encoder.encode(b) else { return false }
        return da == db
    }
}

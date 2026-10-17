import SwiftUI

/// New person, on ONE card (2026-10-16, founder: "간편하게 — 이게 너무
/// 복잡해"). It was eight: name, relationship, how you talk, three
/// relationship-tailored question cards, interests, style. Now the card asks
/// only what a form can't guess — the face and name, who they are to you,
/// and one free note (spoken or typed, any language) — and the parse fills
/// the form, where everything else (how you two talk, what you call each
/// other, topics, manner) is prefilled to confirm. A public figure still
/// skips the note: the model knows them, the lookup names them.
struct CounterpartVoiceIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Seeded from the app language on appear; "en" is only the value held
    /// for the instant before that runs.
    @State private var locale = "en"
    @State private var name = ""
    @State private var kind: RelationshipKind?
    @State private var kindDetail = ""
    @State private var note = ""
    @State private var isParsing = false
    @State private var error: String?
    @State private var prefilled: Counterpart?
    @State private var showManualForm = false
    /// The photo picked on the card. The person does not exist yet, so it
    /// rides along to the form and is saved with them.
    @State private var photo: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        whoSection
                        relationshipSection
                        if kind != .publicFigure { noteSection }
                        if let e = error {
                            Label(e, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Button("Rather just fill in a form?") {
                            showManualForm = true
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                IntakeBottomBar(
                    backVisible: false,
                    nextTitle: chrome("Continue"),
                    nextEnabled: canContinue,
                    isWorking: isParsing,
                    onBack: {},
                    onNext: { Task { await parseAndContinue() } }
                )
            }
            .navigationTitle("Tell me about them")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Same rule as the form it hands off to: once there's something
            // to lose, only Cancel closes this — never a stray swipe.
            .interactiveDismissDisabled(!name.trimmingCharacters(in: .whitespaces).isEmpty)
            .sheet(item: $prefilled, onDismiss: { dismiss() }) { draft in
                CounterpartFormView(initial: draft, photo: photo)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showManualForm, onDismiss: { dismiss() }) {
                CounterpartFormView(initial: nil, photo: photo)
                    .environmentObject(appState)
            }
            .onAppear {
                locale = SpeakOrTypeField.defaultLocale(
                    appLanguage: appState.nativeLanguage,
                    targetLanguage: appState.targetLanguage)
                #if DEBUG
                // Screenshot harness: `-intakeStep <any>` fills the card with stand-in data.
                if UserDefaults.standard.string(forKey: "intakeStep") != nil {
                    name = "Boram"
                    // `-intakeKind "Public figure"` picks another relationship.
                    kind = UserDefaults.standard.string(forKey: "intakeKind")
                        .flatMap(RelationshipKind.init(rawValue:)) ?? .fellowParent
                }
                #endif
            }
        }
    }

    // MARK: - Sections

    /// Same shape as the two sections under it: a label, then one grey
    /// card — the face and the name on a single row, like Contacts.
    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explain("Name"))
                .font(.headline)
            HStack(spacing: 14) {
                // Their face, optional. Photo library, camera, or a file;
                // saved small and square with the person, never sent anywhere.
                PersonPhotoButton(onImage: { photo = $0 },
                                  onRemove: photo == nil ? nil : { photo = nil }) {
                    PersonPhotoCircle(image: photo, name: name, size: 56)
                }
                .buttonStyle(.plain)
                TextField("Their name — as you call them", text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.title3)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var relationshipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explain("Who are they to you?"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(RelationshipKind.allCases) { k in
                        Button {
                            kind = k
                        } label: {
                            IntakeChipLabel(text: k.title, isOn: kind == k)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("More precisely? — e.g. College roommate", text: $kindDetail)
                    // Writing the relationship IS answering, so it lights
                    // Other, which the learner can still change.
                    .onChange(of: kindDetail) { _, text in
                        if kind == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            kind = .other
                        }
                    }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if kind == .publicFigure {
                Text(explain("We'll find who they are — you just confirm. Their voice is a preset, never their real one."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The one free note — everything the old question cards asked, in the
    /// learner's own words, optional.
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explain("What else should I know about them?"))
                .font(.headline)
            SpeakOrTypeField(
                text: $note,
                locale: $locale,
                placeholder: explain("Anything more? Type — or tap the mic and talk."))
        }
    }

    // MARK: - Flow

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kind != nil
    }

    private var relationshipLabel: String {
        kindDetail.isEmpty ? (kind?.title ?? "") : kindDetail
    }

    private func parseAndContinue() async {
        isParsing = true
        defer { isParsing = false }
        error = nil

        // A public figure: the model already knows the person, so the only
        // question is WHICH one — look that up and hand the form an identity
        // to confirm. Not found still opens nothing; the error says so and
        // the name can be fixed here.
        if kind == .publicFigure {
            var draft = Counterpart.empty
            draft.name = name
            draft.relationship = kindDetail.isEmpty ? RelationshipKind.publicFigure.title : kindDetail
            draft.relationshipKind = RelationshipKind.publicFigure.rawValue
            draft.isPublicFigure = true
            do {
                draft.publicIdentity = try await CounterpartParser.identifyPublicFigure(
                    name: name, nativeLanguage: appState.nativeLanguage)
                draft.factsRefreshedAt = Date()
            } catch {
                self.error = explain("Couldn't look them up: \(error.localizedDescription)")
                return
            }
            prefilled = draft
            return
        }

        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            // Nothing to extract — skip the LLM and go straight to the form.
            var draft = Counterpart.empty
            draft.name = name
            draft.relationship = relationshipLabel
            applyDefaults(to: &draft)
            prefilled = draft
            return
        }

        let kindLabel = [kind?.rawValue ?? "", kindDetail]
            .filter { !$0.isEmpty }.joined(separator: " — ")
        var sections = ["Their name: \(name)"]
        if !kindLabel.isEmpty { sections.append("Relationship to me: \(kindLabel)") }
        sections.append("About them: \(typed)")

        do {
            var draft = try await CounterpartParser.parse(
                spokenDescription: sections.joined(separator: "\n\n"),
                languageHint: locale,
                nativeLanguage: appState.nativeLanguage)
            // What the user typed outright wins over the parse.
            draft.name = name
            // The parser is told not to invent, so it can return no
            // relationship; the form's Save needs one.
            if draft.relationship.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.relationship = relationshipLabel
            }
            applyDefaults(to: &draft)
            prefilled = draft
        } catch {
            self.error = explain("Couldn't parse: \(error.localizedDescription)")
        }
    }

    /// The relationship's own speech levels, so the form opens on them as a
    /// confirmation — the card no longer asks how the two of them talk.
    private func applyDefaults(to draft: inout Counterpart) {
        draft.relationshipKind = kind?.rawValue
        let d = Counterpart.defaultRegisters(forKind: kind?.rawValue)
        draft.myRegister = d.mine
        draft.theirRegister = d.theirs
    }
}

// MARK: - Relationship

/// The relationship chips on the card. `rawValue` is the stored key.
private enum RelationshipKind: String, CaseIterable, Identifiable {
    case friend = "Friend"
    case family = "Family"
    case partner = "Partner"
    case coworker = "Coworker"
    case manager = "Manager"
    case fellowParent = "Fellow parent"
    case neighbor = "Neighbor"
    case teacher = "Teacher"
    /// A singer, an actor, an athlete — someone not in the learner's life.
    /// Its own kind, not "Other": the name is looked up, grounded, so the
    /// person is the public record rather than the learner's guess.
    case publicFigure = "Public figure"
    case other = "Other"

    var id: String { rawValue }

    /// The chip's label. `rawValue` is the stored KEY (`relationshipKind`,
    /// read by PeopleSky and the register defaults) and stays English.
    var title: String {
        switch self {
        case .friend:       return explain("Friend")
        case .family:       return explain("Family")
        case .partner:      return explain("Partner")
        case .coworker:     return explain("Coworker")
        case .manager:      return explain("Manager")
        case .fellowParent: return explain("Fellow parent")
        case .neighbor:     return explain("Neighbor")
        case .teacher:      return explain("Teacher")
        case .publicFigure: return explain("Public figure")
        case .other:        return explain("Other")
        }
    }

}

import SwiftUI

/// Guided new-person flow, one card per category — same skeleton as persona
/// onboarding (`PersonaIntakeView`). Name is typed, the relationship is a
/// chip pick, and the relationship then TAILORS the three narrative cards
/// (a fellow Kita parent gets asked about the kids; a manager about 1:1s).
/// Narrative cards are tap-first — common answers as chips (with free-text
/// add) plus a speak-or-type field for what a chip can't say; picks and
/// narration merge into one answer, parsed into a `Counterpart` draft with
/// Gemini, and land in the form prefilled so the user can tweak + pick a
/// voice. A straight-to-form escape stays for users
/// who'd rather just type fields.
struct CounterpartVoiceIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // who → relationship → how you talk → 3 tailored narrative cards →
    // interests → style
    private enum Step: Int, CaseIterable {
        case who, relationship, speech, narrative1, narrative2, narrative3, interests, style
    }

    @State private var step: Step = .who
    /// Seeded from the app language on appear; "en" is only the value held
    /// for the instant before that runs.
    @State private var locale = "en"
    @State private var name = ""
    @State private var kind: RelationshipKind?
    @State private var kindDetail = ""
    @State private var narrativeAnswers = ["", "", ""]
    /// Chip picks per narrative card — joined into the answer alongside
    /// whatever was spoken or typed.
    @State private var narrativeChips: [[String]] = [[], [], []]
    @State private var interests: [String] = []
    @State private var styleTraits: [String] = []
    @State private var styleNotes = ""
    // How the two of them talk — the card right after the relationship,
    // prefilled from it so it reads as a confirmation. `speechTouched` stops
    // a later change of relationship from overwriting what they picked.
    @State private var myRegister: SpeechRegister = .polite
    @State private var theirRegister: SpeechRegister = .polite
    @State private var iCallThem = ""
    @State private var theyCallMe = ""
    @State private var speechTouched = false
    @State private var isParsing = false
    @State private var error: String?
    @State private var prefilled: Counterpart?
    @State private var showManualForm = false
    /// The photo picked on the first card. The person does not exist yet,
    /// so it rides along to the form and is saved with them.
    @State private var photo: UIImage?

    private static let stylePresets = [
        "Direct", "Playful", "Sarcastic", "Formal", "Warm",
        "Talkative", "Quiet", "Blunt", "Fast talker", "Careful"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double((steps.firstIndex(of: step) ?? 0) + 1),
                             total: Double(steps.count))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepContent
                        if let e = error {
                            Label(e, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
                }
                .scrollDismissesKeyboard(.interactively)
                .animation(.snappy, value: step)
                IntakeBottomBar(
                    backVisible: step != .who,
                    nextTitle: neighbor(1) == nil ? chrome("Continue") : chrome("Next"),
                    nextEnabled: canAdvance,
                    isWorking: isParsing,
                    onBack: { withAnimation { step = neighbor(-1) ?? .who } },
                    onNext: advance
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
            .onChange(of: kind) { _, k in
                guard !speechTouched else { return }
                let d = Counterpart.defaultRegisters(forKind: k?.rawValue)
                myRegister = d.mine
                theirRegister = d.theirs
            }
            .onAppear {
                locale = SpeakOrTypeField.defaultLocale(
                    appLanguage: appState.nativeLanguage,
                    targetLanguage: appState.targetLanguage)
                #if DEBUG
                // Screenshot harness: `-intakeStep <n>` jumps to a card with stand-in data.
                if let raw = UserDefaults.standard.string(forKey: "intakeStep"),
                   let i = Int(raw), let s = Step(rawValue: i) {
                    name = "Boram"
                    // `-intakeKind "Public figure"` picks another relationship.
                    kind = UserDefaults.standard.string(forKey: "intakeKind")
                        .flatMap(RelationshipKind.init(rawValue:)) ?? .fellowParent
                    step = s
                }
                #endif
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .who:          whoStep
        case .relationship: relationshipStep
        case .speech:       speechStep
        case .narrative1:   narrativeStep(0)
        case .narrative2:   narrativeStep(1)
        case .narrative3:   narrativeStep(2)
        case .interests:    interestsStep
        case .style:        styleStep
        }
    }

    private var whoStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "Who are we adding?",
                detail: "Someone you actually talk to — dialogues get simulated with them, in their manner.")
            // Their face, optional. Photo library, camera, or a file; saved
            // small and square with the person, never sent anywhere.
            VStack(spacing: 8) {
                PersonPhotoButton(onImage: { photo = $0 },
                                  onRemove: photo == nil ? nil : { photo = nil }) {
                    PersonPhotoCircle(image: photo, name: name)
                }
                .buttonStyle(.plain)
                Text(explain("A photo is optional. Without one, their initials stand in."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            TextField("Their name — as you call them", text: $name)
                .textInputAutocapitalization(.words)
                .font(.title3)
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Rather just fill in a form?") {
                showManualForm = true
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var relationshipStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "Who are they to you?",
                detail: "This shapes what I ask next — a manager and a best friend live in different worlds.")
            VStack(alignment: .leading, spacing: 10) {
                let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(RelationshipKind.allCases) { k in
                        Button {
                            kind = k
                        } label: {
                            IntakeChipLabel(text: k.rawValue, isOn: kind == k)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("More precisely? — e.g. College roommate", text: $kindDetail)
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

    /// How the learner and this person speak to each other. The profile
    /// cards say who the person IS; nothing said how the two of them TALK,
    /// so a best friend was voiced in polite speech. Both directions, because
    /// Korean and Japanese let them differ.
    private var speechStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: name.isEmpty
                    ? explain("How do you two talk?")
                    : explain("How do you and \(name) talk?"),
                detail: explain("Calls and scenes speak this way. You can change it later."))
            VStack(alignment: .leading, spacing: 18) {
                registerPicker(title: explain("You talk to them"), selection: $myRegister)
                registerPicker(title: name.isEmpty
                                   ? explain("They talk to you")
                                   : explain("\(name) talks to you"),
                               selection: $theirRegister)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 0) {
                TextField("What you call them (optional)", text: $iCallThem)
                    .padding(14)
                Divider().padding(.leading, 14)
                TextField("What they call you (optional)", text: $theyCallMe)
                    .padding(14)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func registerPicker(title: String, selection: Binding<SpeechRegister>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Picker(title, selection: Binding(
                get: { selection.wrappedValue },
                set: { speechTouched = true; selection.wrappedValue = $0 })) {
                ForEach(SpeechRegister.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            if let term = selection.wrappedValue.term(in: appState.targetLanguage) {
                Text(explain("In \(LanguageCatalog.name(appState.targetLanguage, in: appState.nativeLanguage)): \(term)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func narrativeStep(_ index: Int) -> some View {
        let card = (kind ?? .other).cards[index]
        return VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(question: card.question, detail: card.detail)
            // Tap-first: common answers as chips (+ free-text add); the
            // speak/type field below carries anything a chip can't say.
            ChipPickerField(
                presets: card.chips,
                selection: $narrativeChips[index])
            SpeakOrTypeField(
                text: $narrativeAnswers[index],
                locale: $locale,
                placeholder: "Anything more? Type — or tap the mic and talk.")
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: name.isEmpty ? "What are they into?" : "What's \(name) into?",
                detail: "Tap what fits — these become what you two talk about.")
            ChipPickerField(
                presets: PersonaOnboardingView.interestPresets,
                selection: $interests)
        }
    }

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: name.isEmpty ? "How do they talk?" : "How does \(name) talk?",
                detail: "Tap what fits — the simulated \(name.isEmpty ? "person" : name) should sound like the real one.")
            ChipPickerField(
                presets: Self.stylePresets,
                selection: $styleTraits,
                allowsCustom: false)
            TextField("In your own words (optional) — e.g. switches to English when excited",
                      text: $styleNotes, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Flow

    /// The steps this person actually has. A relationship can ask fewer
    /// than three narrative questions (a public figure asks two), and a card
    /// kept only to fill a slot is one the learner can't see the point of.
    private var steps: [Step] {
        // A public figure is known to the model: the name is the intake, and
        // the grounded lookup fills the rest for the form to confirm.
        if kind == .publicFigure { return [.who, .relationship] }
        let cardCount = (kind ?? .other).cards.count
        return Step.allCases.filter { s in
            switch s {
            case .narrative1: return cardCount > 0
            case .narrative2: return cardCount > 1
            case .narrative3: return cardCount > 2
            default: return true
            }
        }
    }

    private func neighbor(_ offset: Int) -> Step? {
        guard let i = steps.firstIndex(of: step), steps.indices.contains(i + offset) else { return nil }
        return steps[i + offset]
    }

    private var canAdvance: Bool {
        switch step {
        case .who:          return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .relationship: return kind != nil
        default:            return true
        }
    }

    private func advance() {
        if neighbor(1) == nil {
            Task { await parseAndContinue() }
        } else {
            withAnimation { step = neighbor(1) ?? .style }
        }
    }

    private func parseAndContinue() async {
        isParsing = true
        defer { isParsing = false }
        error = nil

        // A public figure: the model already knows the person, so the only
        // question is WHICH one — look that up and hand the form an identity
        // to confirm. Nothing else about them is written down. Not found
        // still opens the form, where the name can be fixed and looked up
        // again; that is the one place to confirm or correct.
        if kind == .publicFigure {
            var draft = Counterpart.empty
            draft.name = name
            draft.relationship = kindDetail.isEmpty ? RelationshipKind.publicFigure.rawValue : kindDetail
            draft.relationshipKind = RelationshipKind.publicFigure.rawValue
            draft.isPublicFigure = true
            do {
                draft.publicIdentity = try await CounterpartParser.identifyPublicFigure(
                    name: name, nativeLanguage: appState.nativeLanguage)
                draft.factsRefreshedAt = Date()
            } catch {
                self.error = "Couldn't look them up: \(error.localizedDescription)"
                return
            }
            prefilled = draft
            return
        }

        let kindLabel = [kind?.rawValue ?? "", kindDetail]
            .filter { !$0.isEmpty }.joined(separator: " — ")
        let styleLine = (styleTraits.joined(separator: ", ")
            + (styleNotes.isEmpty ? "" : ". \(styleNotes)"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cards = (kind ?? .other).cards

        var sections = ["Their name: \(name)"]
        if !kindLabel.isEmpty { sections.append("Relationship to me: \(kindLabel)") }
        for (i, card) in cards.enumerated() {
            // Chip picks + whatever was spoken/typed form ONE answer.
            var parts: [String] = []
            if !narrativeChips[i].isEmpty {
                parts.append(narrativeChips[i].joined(separator: ", "))
            }
            let typed = narrativeAnswers[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty { parts.append(typed) }
            if !parts.isEmpty {
                sections.append("Q: \(card.question)\nA: \(parts.joined(separator: ". "))")
            }
        }
        if !interests.isEmpty {
            sections.append("What they're into: \(interests.joined(separator: ", "))")
        }
        if !styleLine.isEmpty { sections.append("How they talk: \(styleLine)") }

        if narrativeAnswers.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty })
            && narrativeChips.allSatisfy(\.isEmpty) {
            // Nothing to extract — skip the LLM and go straight to the form.
            var draft = Counterpart.empty
            draft.name = name
            draft.relationship = kindDetail.isEmpty ? (kind?.rawValue ?? "") : kindDetail
            draft.conversationStyle = styleLine
            draft.commonTopics = interests.joined(separator: ", ")
            applySpeech(to: &draft)
            prefilled = draft
            return
        }

        do {
            var draft = try await CounterpartParser.parse(
                spokenDescription: sections.joined(separator: "\n\n"),
                languageHint: locale,
                nativeLanguage: appState.nativeLanguage)
            // What the user typed outright wins over the parse.
            draft.name = name
            // The relationship card is REQUIRED, so the user always gave one —
            // but the parser is told not to invent, and for someone who isn't
            // in their life (a celebrity: "BTS 정국" + Other) it returns "".
            // The form's Save needs a relationship, so an empty one left Save
            // greyed out and the only exit threw the person away.
            if draft.relationship.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.relationship = kindDetail.isEmpty ? (kind?.rawValue ?? "") : kindDetail
            }
            applySpeech(to: &draft)
            prefilled = draft
        } catch {
            self.error = "Couldn't parse: \(error.localizedDescription)"
        }
    }

    /// What the speech card settled, onto the draft the form opens with.
    private func applySpeech(to draft: inout Counterpart) {
        draft.relationshipKind = kind?.rawValue
        // Only what the learner actually saw and settled; a skipped card
        // leaves the person on its cast's default (polite, never corrected).
        guard steps.contains(.speech) else { return }
        draft.myRegister = myRegister
        draft.theirRegister = theirRegister
        draft.iCallThem = iCallThem.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.theyCallMe = theyCallMe.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Relationship-tailored questions

/// The relationship pick on card 2 — each kind supplies the three narrative
/// cards that follow, so questions land in that relationship's world instead
/// of staying generic. Adding a kind or reworking copy happens only here.
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
    /// Its own kind, not "Other": the cards ask why this person and where
    /// the learner imagines meeting them, and the parse runs grounded so the
    /// profile is the public record rather than the learner's guess.
    case publicFigure = "Public figure"
    case other = "Other"

    var id: String { rawValue }

    struct NarrativeCard {
        let question: String
        let detail: String
        /// Tappable common answers for this question — picked ones join the
        /// narrative answer verbatim; the free-text row adds custom ones.
        let chips: [String]
    }

    private static let tapOrTalk = "Tap what fits, add your own — or just talk, your native language is fine."

    var cards: [NarrativeCard] {
        switch self {
        case .friend: return [
            .init(question: "How did you two meet?",
                  detail: Self.tapOrTalk,
                  chips: ["From school", "From work", "Through friends",
                          "Online", "Childhood friends", "Met recently"]),
            .init(question: "What's their life like right now?",
                  detail: "",
                  chips: ["Works full-time", "Studying", "Recently moved",
                          "Raising kids", "Lives nearby", "Lives abroad"]),
            .init(question: "What's just between you two?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Inside jokes", "We tease each other", "Deep talks",
                          "Mostly banter", "Shared hobby",
                          "They know everything about me"])
        ]
        case .family: return [
            .init(question: "Who are they in your family?",
                  detail: Self.tapOrTalk,
                  chips: ["Older sibling", "Younger sibling", "Parent",
                          "Grandparent", "Cousin", "In-law"]),
            .init(question: "What's going on in their life?",
                  detail: "",
                  chips: ["Busy with work", "Retired", "New hobby",
                          "Just moved", "Raising kids", "Health ups and downs"]),
            .init(question: "What do you two usually talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Family news", "Food and recipes", "Health",
                          "Old memories", "Money and plans",
                          "They nag me lovingly"])
        ]
        case .partner: return [
            .init(question: "How did your story start?",
                  detail: Self.tapOrTalk,
                  chips: ["Together for years", "Newly dating", "Met through friends",
                          "Met online", "Living together", "Long distance"]),
            .init(question: "What fills your conversations these days?",
                  detail: "",
                  chips: ["Daily logistics", "Future plans", "Food and cooking",
                          "Travel plans", "Work stories", "Our pets"]),
            .init(question: "What's your dynamic like?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Playful teasing", "Pet names", "Lots of inside jokes",
                          "Calm and cozy", "We debate everything",
                          "They call me out"])
        ]
        case .coworker: return [
            .init(question: "How do you work together?",
                  detail: Self.tapOrTalk,
                  chips: ["Same team", "Cross-team", "We share projects",
                          "Desk neighbors", "Worked together for years",
                          "They're new"]),
            .init(question: "What do your work chats look like?",
                  detail: "",
                  chips: ["Daily standups", "Reviews", "Lunch together",
                          "Coffee breaks", "Mostly chat apps", "Casual between us"]),
            .init(question: "What's the context around you two?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Deadline crunch", "Office jokes", "New project starting",
                          "We vent together", "After-work drinks",
                          "Company changes going on"])
        ]
        case .manager: return [
            .init(question: "What's your working relationship?",
                  detail: Self.tapOrTalk,
                  chips: ["My direct manager", "Weekly 1:1s", "Manager for years",
                          "New to me", "Skip-level", "We talk daily"]),
            .init(question: "What do you usually discuss?",
                  detail: "",
                  chips: ["Project updates", "Feedback", "Career growth",
                          "Priorities", "Pretty formal", "Fairly casual"]),
            .init(question: "What else should I know about them?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Direct style", "Supportive", "Detail-oriented",
                          "Big-picture person", "Busy calendar",
                          "Knows my life a bit"])
        ]
        case .fellowParent: return [
            .init(question: "How are your families connected?",
                  detail: Self.tapOrTalk,
                  chips: ["Same Kita", "Same school", "Same class",
                          "Playground friends", "Kids are best friends",
                          "Known for years"]),
            .init(question: "Where do you usually run into each other?",
                  detail: "",
                  chips: ["Drop-off", "Pick-up", "Playdates",
                          "Birthday parties", "School events", "The playground"]),
            .init(question: "What do you two talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["The kids", "School news", "Logistics and schedules",
                          "Weekend plans", "Parenting tips", "Neighborhood news"])
        ]
        case .neighbor: return [
            .init(question: "How did you become neighbors?",
                  detail: Self.tapOrTalk,
                  chips: ["Next door", "Same building", "Same street",
                          "Neighbors for years", "I moved in recently",
                          "They moved in recently"]),
            .init(question: "Where do your chats happen?",
                  detail: "",
                  chips: ["Hallway", "Elevator", "Garden or yard",
                          "On the street", "Neighborhood events",
                          "Walking the dog"]),
            .init(question: "What do you usually talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Neighborhood news", "The weather", "Their family",
                          "Pets", "Home projects", "We trade favors"])
        ]
        case .teacher: return [
            .init(question: "Whose teacher — and of what?",
                  detail: Self.tapOrTalk,
                  chips: ["My teacher", "My kid's teacher", "Language teacher",
                          "Music teacher", "Sports coach", "Known for a while"]),
            .init(question: "When do you talk with them?",
                  detail: "",
                  chips: ["In class", "Office hours", "Parent meetings",
                          "Over messages", "Pretty formal", "Fairly relaxed"]),
            .init(question: "What else should I know about them?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Strict but fair", "Encouraging", "Patient",
                          "Talks fast", "Recent school events",
                          "I want to ask more questions"])
        ]
        // No cards: the model already knows a public figure, so their name
        // is the whole intake (see `steps`). Cards asking where you'd meet
        // them, what you'd say, which side of them you follow and what you'd
        // talk about were each tried and cut on 2026-09-28 — every one either
        // shrank the person to a scene or asked the learner to do the
        // model's job.
        case .publicFigure: return []
        case .other: return [
            .init(question: "How do you know each other?",
                  detail: Self.tapOrTalk,
                  chips: ["Through friends", "From work", "From a hobby",
                          "From the neighborhood", "Online", "Met recently"]),
            .init(question: "What's their life like?",
                  detail: "",
                  chips: ["Works full-time", "Studying", "Raising kids",
                          "Lives nearby", "Lives abroad", "Busy lately"]),
            .init(question: "What's the context between you?",
                  detail: "This is what makes the dialogues feel real.",
                  chips: ["Recurring topics", "Inside jokes", "We meet regularly",
                          "Mostly texting", "They know my life well",
                          "Still getting to know each other"])
        ]
        }
    }
}

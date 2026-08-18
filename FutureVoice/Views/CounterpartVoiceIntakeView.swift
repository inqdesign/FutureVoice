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

    // who → relationship → 3 tailored narrative cards → interests → style
    private enum Step: Int, CaseIterable {
        case who, relationship, narrative1, narrative2, narrative3, interests, style
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
    @State private var isParsing = false
    @State private var error: String?
    @State private var prefilled: Counterpart?
    @State private var showManualForm = false

    private static let stylePresets = [
        "Direct", "Playful", "Sarcastic", "Formal", "Warm",
        "Talkative", "Quiet", "Blunt", "Fast talker", "Careful"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
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
                    nextTitle: step == .style ? chrome("Continue") : chrome("Next"),
                    nextEnabled: canAdvance,
                    isWorking: isParsing,
                    onBack: { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .who } },
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
            .sheet(item: $prefilled, onDismiss: { dismiss() }) { draft in
                CounterpartFormView(initial: draft)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showManualForm, onDismiss: { dismiss() }) {
                CounterpartFormView(initial: nil)
                    .environmentObject(appState)
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
                    kind = .fellowParent
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

    private var canAdvance: Bool {
        switch step {
        case .who:          return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .relationship: return kind != nil
        default:            return true
        }
    }

    private func advance() {
        if step == .style {
            Task { await parseAndContinue() }
        } else {
            withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .style }
        }
    }

    private func parseAndContinue() async {
        isParsing = true
        defer { isParsing = false }
        error = nil

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
            prefilled = draft
        } catch {
            self.error = "Couldn't parse: \(error.localizedDescription)"
        }
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

import SwiftUI

/// Guided new-person flow, one card per category — same skeleton as persona
/// onboarding (`PersonaIntakeView`). Name is typed, the relationship is a
/// chip pick, and the relationship then TAILORS the three narrative cards
/// (a fellow Kita parent gets asked about the kids; a manager about 1:1s).
/// Narrative answers are speak-first with a typing fallback, parsed into a
/// `Counterpart` draft with Gemini, and land in the form prefilled so the
/// user can tweak + pick a voice. A straight-to-form escape stays for users
/// who'd rather just type fields.
struct CounterpartVoiceIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // who → relationship → 3 tailored narrative cards → interests → style
    private enum Step: Int, CaseIterable {
        case who, relationship, narrative1, narrative2, narrative3, interests, style
    }

    @State private var step: Step = .who
    @State private var locale = "ko"
    @State private var name = ""
    @State private var kind: RelationshipKind?
    @State private var kindDetail = ""
    @State private var narrativeAnswers = ["", "", ""]
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
                    nextTitle: step == .style ? "Continue" : "Next",
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
                locale = appState.nativeLanguage
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
            IntakeHints(bullets: card.hints)
            SpeakOrTypeField(
                text: $narrativeAnswers[index],
                locale: $locale)
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
        for (card, answer) in zip(cards, narrativeAnswers) where !answer.isEmpty {
            sections.append("Q: \(card.question)\nA: \(answer)")
        }
        if !interests.isEmpty {
            sections.append("What they're into: \(interests.joined(separator: ", "))")
        }
        if !styleLine.isEmpty { sections.append("How they talk: \(styleLine)") }

        if narrativeAnswers.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
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
                languageHint: locale)
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
        let hints: [String]
    }

    private static let speakFreely = "Speak freely — your native language is fine."

    var cards: [NarrativeCard] {
        switch self {
        case .friend: return [
            .init(question: "How did you two meet?",
                  detail: Self.speakFreely,
                  hints: ["Where and when you met",
                          "How long you've been friends",
                          "How often you talk these days"]),
            .init(question: "What's their life like right now?",
                  detail: "",
                  hints: ["What they do",
                          "Where they live",
                          "Big things going on for them lately"]),
            .init(question: "What's just between you two?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Inside jokes and running topics",
                          "Recent events in their life",
                          "What they know (and don't) about your life"])
        ]
        case .family: return [
            .init(question: "Who are they in your family?",
                  detail: Self.speakFreely,
                  hints: ["Sibling, parent, cousin — and what you call them",
                          "Where they live now",
                          "How often you talk or visit"]),
            .init(question: "What's going on in their life?",
                  detail: "",
                  hints: ["Work, health, hobbies",
                          "Recent family events",
                          "What they're busy with lately"]),
            .init(question: "What do you two usually talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Topics that always come up",
                          "Family running jokes",
                          "What they nag or ask you about"])
        ]
        case .partner: return [
            .init(question: "How did your story start?",
                  detail: Self.speakFreely,
                  hints: ["How long you've been together",
                          "How you met",
                          "Living together or apart?"]),
            .init(question: "What fills your conversations these days?",
                  detail: "",
                  hints: ["Daily routines you share",
                          "Plans you're making together",
                          "What you did last weekend"]),
            .init(question: "What's your dynamic like?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["How you tease each other",
                          "Pet names or running jokes",
                          "What they always call you out on"])
        ]
        case .coworker: return [
            .init(question: "How do you work together?",
                  detail: Self.speakFreely,
                  hints: ["Same team or cross-team — your roles",
                          "How long you've worked together",
                          "Projects you share"]),
            .init(question: "What do your work chats look like?",
                  detail: "",
                  hints: ["Standups, reviews, lunch talk?",
                          "Topics that come up daily",
                          "Formal or casual between you two?"]),
            .init(question: "What's the context around you two?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Current projects or deadlines",
                          "Office running jokes",
                          "What's happening at the company lately"])
        ]
        case .manager: return [
            .init(question: "What's your working relationship?",
                  detail: Self.speakFreely,
                  hints: ["Their role and yours",
                          "How long they've been your manager",
                          "1:1s, reviews — how often you talk"]),
            .init(question: "What do you usually discuss?",
                  detail: "",
                  hints: ["Projects, feedback, career talk",
                          "How formal your conversations are",
                          "What they care about most"]),
            .init(question: "What else should I know about them?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Their management style",
                          "Recent team events",
                          "What they know about your life outside work"])
        ]
        case .fellowParent: return [
            .init(question: "How are your families connected?",
                  detail: Self.speakFreely,
                  hints: ["Your kids' names and ages",
                          "Same Kita, school, or playground?",
                          "How long you've known each other"]),
            .init(question: "Where do you usually run into each other?",
                  detail: "",
                  hints: ["Drop-off, pick-up, playdates",
                          "Birthday parties, school events",
                          "How often you end up chatting"]),
            .init(question: "What do you two talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["The kids, obviously — what else?",
                          "School news and logistics",
                          "What you know about their family"])
        ]
        case .neighbor: return [
            .init(question: "How did you become neighbors?",
                  detail: Self.speakFreely,
                  hints: ["Next door, same building, same street?",
                          "How long you've lived nearby",
                          "How you first got talking"]),
            .init(question: "Where do your chats happen?",
                  detail: "",
                  hints: ["Hallway, elevator, garden",
                          "Neighborhood events",
                          "How often you bump into each other"]),
            .init(question: "What do you usually talk about?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Neighborhood news",
                          "Their family, pets, projects",
                          "Favors you've traded"])
        ]
        case .teacher: return [
            .init(question: "Whose teacher — and of what?",
                  detail: Self.speakFreely,
                  hints: ["Your teacher, or your kid's?",
                          "What they teach",
                          "How long you've known them"]),
            .init(question: "When do you talk with them?",
                  detail: "",
                  hints: ["Class, office hours, parent meetings",
                          "How formal it is between you",
                          "In person or over messages?"]),
            .init(question: "What else should I know about them?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Their style in class or meetings",
                          "Recent school events",
                          "What you wish you could discuss more easily"])
        ]
        case .other: return [
            .init(question: "How do you know each other?",
                  detail: Self.speakFreely,
                  hints: ["Where and when you met",
                          "How long you've known each other",
                          "How often you talk"]),
            .init(question: "What's their life like?",
                  detail: "",
                  hints: ["What they do",
                          "Where they live",
                          "Big things going on for them lately"]),
            .init(question: "What's the context between you?",
                  detail: "This is what makes the dialogues feel real.",
                  hints: ["Recurring topics, inside jokes",
                          "Recent events",
                          "What they know about your life"])
        ]
        }
    }
}

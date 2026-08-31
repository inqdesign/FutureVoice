import SwiftUI

/// Watch — simulate a specific situation BEFORE it happens and mine ideas
/// from it: how the fluent self opens, handles the awkward beats, which
/// expressions it reaches for. Three ways in, all landing in the same
/// situation composer:
///
///   1. People row (Instagram-stories style) — tap a persona → composer
///      scoped to them, with relationship-grounded situation ideas.
///   2. "Make your own situation" — the default: describe the real thing
///      coming up ("Lufthansa cabin-crew interview next week") in a blank
///      composer. No person required; the scene casts whoever fits.
///   3. Likely situations — light category chips; tapping one opens the
///      composer pre-scoped to that category, with AI ideas loading right
///      away.
///
/// Watching mints the scenario book that Practice reviews later.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var composer: ComposerConfig?
    @State private var watchScene: WatchTarget?

    /// What to play + whether to write a new take. A saved scenario is a
    /// TEMPLATE — tapping its card generates a fresh scene every time
    /// (replaying past material is Practice's job); a just-minted scenario
    /// from the composer generates its first scene.
    struct WatchTarget: Identifiable, Hashable {
        let scenario: Scenario
        let fresh: Bool
        var id: UUID { scenario.id }
    }
    @State private var showingNewVoice = false
    @State private var showingFind = false
    /// A Find-people stranger to start a live call with (fullScreenCover).
    @State private var callPerson: Counterpart?
    /// A bookmarked stranger tapped in the stories row — opens their card
    /// (intro, past talks, Preview/Talk) rather than the situation composer.
    @State private var personCard: Counterpart?
    /// Bookmarks live in UserDefaults, which publishes nothing — re-read them
    /// whenever the tab appears or the Find sheet closes.
    @State private var bookmarkedRemoteIds: Set<String> = []

    struct ComposerConfig: Identifiable {
        let id = UUID()
        var person: Counterpart?
        /// Pre-selected category (from a "Likely situations" card).
        var category: ScenarioComposerSheet.Category?
        /// Set when a saved scenario card was tapped — the composer opens
        /// prefilled as a settings sheet (edit, delete, or Watch a fresh take)
        /// instead of generating immediately.
        var editing: Scenario?
    }

    var body: some View {
        NavigationStack {
            // A ScrollView, NOT a List: every section here is a custom grid or
            // card. Inside a List each grid lives in one row, and the
            // inset-grouped cell mask rounds the row's corners — visibly
            // clipping whatever chip/card sits at an edge — and long-press
            // context menus preview the WHOLE row instead of one card.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    peopleSection
                    makeYourOwnSection
                    scenariosSection
                    likelySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Watch")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // ONE people page: your own people and the shared pool,
                    // merged — the header button answers "who can I talk to".
                    Button { showingFind = true } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("People")
                }
            }
            .sheet(item: $composer) { cfg in
                // The ONE unified composer — same as Talk's "+", but its action
                // is Watch (play the scene). Saves the scenario, then plays it.
                // A saved card opens the SAME sheet in edit mode (cfg.editing):
                // review/tweak the settings, delete, or Watch a fresh take.
                ScenarioComposerSheet(person: cfg.person,
                                      host: .watch,
                                      initialCategory: cfg.category,
                                      editing: cfg.editing,
                                      ctaTitle: "Watch", ctaIcon: "play.fill",
                                      onDelete: cfg.editing.map { s in
                                          { appState.deleteScenario(id: s.id); composer = nil }
                                      }) { scenario in
                    appState.saveScenario(scenario)
                    composer = nil
                    // Editing an existing scenario → its Watch is a fresh take
                    // into the same book; a just-minted one plays its first.
                    watchScene = WatchTarget(scenario: scenario, fresh: cfg.editing != nil)
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView().environmentObject(appState)
            }
            .onAppear { bookmarkedRemoteIds = PublicPersonaService.bookmarkedIds() }
            .sheet(item: $personCard) { person in
                NavigationStack {
                    FindPersonCard(
                        person: person,
                        bookmarks: $bookmarkedRemoteIds,
                        onTalk: { p in personCard = nil; callPerson = p },
                        onWatch: { p in
                            personCard = nil
                            watchScene = WatchTarget(scenario: freeTalkScenario(with: p),
                                                     fresh: true)
                        },
                        onCompose: { p in
                            personCard = nil
                            composer = ComposerConfig(person: p)
                        })
                        .environmentObject(appState)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { personCard = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingFind,
                   onDismiss: { bookmarkedRemoteIds = PublicPersonaService.bookmarkedIds() }) {
                // Find people — strangers from the shared pool. Talk starts a
                // live call in THEIR preset voice; Preview plays the fluent
                // self and this person just TALKING — meeting a stranger is
                // already the situation, so it never asks the user to invent
                // one first (that's what "Make your own situation" is for).
                FindPeopleSheet(
                    onNew: { showingFind = false; showingNewVoice = true },
                    onTalk: { person in
                        showingFind = false
                        callPerson = person
                    },
                    onWatch: { person in
                        showingFind = false
                        watchScene = WatchTarget(scenario: freeTalkScenario(with: person),
                                                 fresh: true)
                    },
                    onCompose: { person in
                        showingFind = false
                        composer = ComposerConfig(person: person)
                    })
                    .environmentObject(appState)
            }
            .fullScreenCover(item: $callPerson) { person in
                ConversationView(initialCounterpart: person)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $watchScene) { t in
                SceneWatchView(scenarioId: t.scenario.id, freshTake: t.fresh)
                    .environmentObject(appState)
            }
        }
    }

    /// The scenario behind "Watch" on a Find-people card: no situation to
    /// build, just the two of them talking. Reused (not re-minted) per person
    /// so every watch lands in the SAME book — the study material from
    /// meeting this person accumulates instead of scattering across one-shot
    /// scenarios, and the second watch replays instead of regenerating.
    ///
    /// Kept DELIBERATELY short. The person's intro, background and style are
    /// already injected by `ScenarioCurriculumEngine`'s counterpart block;
    /// repeating them here only made the prompt longer, and a longer prompt is
    /// a longer wait before the first line is spoken.
    private func freeTalkScenario(with person: Counterpart) -> Scenario {
        if let existing = appState.scenarios.first(where: {
            $0.counterpartId == person.id && $0.category == Self.meetingCategory
        }) {
            return existing
        }
        var s = Scenario(
            environment: "Talking with someone you've just met, already past the hellos",
            role: person.relationship.isEmpty ? person.name : person.relationship,
            // Two rules, in order. FIRST the overlap (the engine computes it
            // and hands it over): strangers open on what they share, and
            // picking a fact off one side's biography at random is what made
            // scenes land on strange subjects — especially against a real
            // user's thin auto-published intro, where there was nothing to
            // pick and the model filled the gap itself. THEN the ban on the
            // interview, because "getting to know each other" is a shape the
            // model will fill identically for everyone.
            notes: "Build the scene on the COMMON GROUND given below — that is "
                + "the subject. Get specific about it fast. NOT a "
                + "get-to-know-you interview: no running through where are you "
                + "from / what do you do / what are your hobbies. Land "
                + "mid-subject, the way real talk does."
        )
        s.counterpartId = person.id
        s.isMeeting = true
        s.category = Self.meetingCategory
        s.categoryIcon = "person.2.wave.2"
        s.summary = "Free talk with \(person.name)"
        appState.saveScenario(s)
        return s
    }

    private static let meetingCategory = "Meeting"

    /// Who the stories row shows: the people the user MADE, plus the Find
    /// people strangers they bookmarked. Having talked with someone is not
    /// enough to earn a slot here — one curious call would otherwise pin a
    /// stranger next to the user's actual friends forever. Every person
    /// talked with is still one tap away under Find people → "People you've
    /// met"; the bookmark is what promotes them to this row.
    private var rowPeople: [Counterpart] {
        let own = appState.counterparts.filter { $0.remoteId == nil }
        let kept = appState.counterparts.filter {
            guard let rid = $0.remoteId else { return false }
            return bookmarkedRemoteIds.contains(rid)
        }
        return own + kept
    }

    // MARK: - 1. People (stories row)

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // No Find button here any more: the page header's person.2 opens
            // the ONE people page (your people + the shared pool), so the row
            // needs no second door beside it.
            sectionHeader("People")
            // Making a person is pinned to the left, outside the scroller —
            // as the last bubble it slid off the row the moment the user had
            // a few people, exactly like Find people did before it moved up
            // into the header.
            HStack(alignment: .top, spacing: 16) {
                addPersonBubble
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(rowPeople) { c in
                            personBubble(c)
                        }
                    }
                    // Full-bleed scroller: cancel the page's side padding so
                    // avatars run to the trailing edge, then restore it inside.
                    .padding(.trailing, 20)
                }
                .padding(.trailing, -20)
            }
            .padding(.vertical, 6)
            Text(explain("Your own people, plus anyone you bookmarked from the People page. Talking with someone doesn't add them here — bookmark them to keep them."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func personBubble(_ c: Counterpart) -> some View {
        Button {
            // EVERY bubble opens the person's card. They sit in one row, so
            // they have to answer a tap the same way — one used to jump
            // straight into the situation composer while the other opened a
            // card, which made two identical-looking circles behave like two
            // different controls. The card is the richer answer: who they are,
            // the talks so far, and every action they support (the composer
            // among them, for the people the user made).
            personCard = c
        } label: {
            VStack(spacing: 6) {
                PersonBubble(name: c.name)
                Text(c.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
    }

    private var addPersonBubble: some View {
        Button { showingNewVoice = true } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: 64, height: 64)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Create")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New person")
    }

    // MARK: - Your scenarios (the same list Talk shows — watch them here too)

    private var savedScenarios: [Scenario] {
        // Meetings are excluded: a talk with someone from Find people is
        // not a situation the user built, and it belongs in Practice with the
        // rest of the review material, not in this list.
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    @ViewBuilder
    private var scenariosSection: some View {
        if !savedScenarios.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Your scenarios")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(savedScenarios) { s in
                        scenarioCard(s)
                    }
                }
                Text(explain("Tap a card to review or tweak it, then watch — every watch writes a fresh take. Past takes live in Practice."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Grouped-list-style section title, hand-rolled since the page left List.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func scenarioCard(_ s: Scenario) -> some View {
        let personaName = s.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }?.name
        }
        let partner = personaName
            ?? (s.role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.role)
        // The concrete situation under the tidy title — only when the title
        // isn't already the environment text (rows with no summary show the
        // environment AS the title, so a blurb would just repeat it).
        let env = s.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        let blurb = env.caseInsensitiveCompare(s.cardTitle) == .orderedSame ? nil : env
        return Button {
            // Settings sheet first, not straight to generation — check the
            // situation/voice, tweak or delete, then Watch from there.
            composer = ComposerConfig(editing: s)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if let personaName {
                        Text(Books.initials(personaName))
                            .font(.title3.weight(.bold)).foregroundStyle(.tint)
                    } else {
                        Image(systemName: s.categoryIcon ?? Books.roleIcon(for: s.role))
                            .font(.title2).foregroundStyle(.tint)
                    }
                    Spacer(minLength: 8)
                    // Tap opens the settings sheet; Watch (a fresh take) is its
                    // CTA — the play glyph still names the card's end action.
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let category = s.category, personaName == nil {
                        Text(category)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(s.cardTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blurb {
                        Text(blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if let partner {
                        Text("with \(partner)").lineLimit(1)
                    }
                    if partner != nil && s.lastUsedAt != nil {
                        Text(verbatim: "·")
                    }
                    if let last = s.lastUsedAt {
                        Text(last, format: .relative(presentation: .named)).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            // Fill the row's height so a short card matches its taller sibling
            // (LazyVGrid sizes the row to the tallest cell).
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Long-press preview hugs THIS card's rounded rect (outside a
            // List it would default to the view's rectangular bounds).
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteScenario(id: s.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - 2. Make your own (the default)

    private var makeYourOwnSection: some View {
        Button {
            composer = ComposerConfig()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make your own situation")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(explain("The real thing coming up — an interview, a call, a visit. Describe it, watch it handled."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Likely situations (category cards → the unified composer)

    private var likelySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Likely situations")
            // Deliberately LIGHTER than the scenario cards above: these are
            // starting points that open the composer, not saved content that
            // plays. Chip styling (same as the composer's own choice chips)
            // keeps the two tap behaviors visually distinct.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(prioritizedTree) { node in
                    categoryChip(node)
                }
            }
            Text(explain("Tap a category — the composer suggests specific scenarios you can watch."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryChip(_ node: SituationBranch) -> some View {
        Button {
            // Jump into the unified composer pre-scoped to this category.
            composer = ComposerConfig(
                category: ScenarioComposerSheet.Category(title: node.label, icon: node.icon))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: node.icon)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                Text(node.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The grid, reordered so categories matching the persona's "when do you
    /// most need it" picks come first (tree order within each group). The
    /// onboarding chips are the whole point of asking — this is where they
    /// visibly pay off.
    private var prioritizedTree: [SituationBranch] {
        let picked = appState.persona?.situations ?? []
        guard !picked.isEmpty else { return Self.situationTree }
        let wanted = Set(picked.flatMap { Self.categoryLabels(forSituation: $0) })
        guard !wanted.isEmpty else { return Self.situationTree }
        let (hits, rest) = Self.situationTree.reduce(into: ([SituationBranch](), [SituationBranch]())) {
            acc, node in
            if wanted.contains(node.label) { acc.0.append(node) } else { acc.1.append(node) }
        }
        return hits + rest
    }

    /// Map one persona situation (an onboarding preset or the user's own
    /// words) to grid category labels. Presets map explicitly; free text
    /// matches a category when its label appears in the text.
    private static func categoryLabels(forSituation s: String) -> [String] {
        let presetMap: [String: [String]] = [
            "Work meetings": ["Work"],
            "Client calls": ["Work"],
            "Doctor / clinic": ["Health"],
            "Travel": ["Travel"],
            "Online shopping": ["Shopping"],
            "Customer service": ["Shopping"],
            "Daily small talk": ["Cafe"]
        ]
        if let mapped = presetMap[s] { return mapped }
        let lowered = s.lowercased()
        return situationTree.map(\.label).filter { lowered.contains($0.lowercased()) }
    }

    // MARK: - The chain data

    struct SituationBranch: Identifiable {
        let id = UUID()
        let label: String
        /// Card symbol — only meaningful on top-level (grid) entries.
        var icon: String = "bubble.left.and.bubble.right"
        var children: [SituationBranch] = []
        /// Set on leaves: the assembled, ready-to-edit situation.
        var situation: String?
    }

    static let situationTree: [SituationBranch] = [
        SituationBranch(label: "Cafe", icon: "cup.and.saucer.fill", children: [
            SituationBranch(label: "Ordering", children: [
                SituationBranch(label: "Order came out wrong",
                                situation: "At a cafe: my order came out wrong, and I want to point it out politely and get it fixed."),
                SituationBranch(label: "Asking for a recommendation",
                                situation: "At a cafe: I can't decide, so I ask the barista what they'd recommend and chat a little."),
                SituationBranch(label: "Complicated custom order",
                                situation: "At a cafe: ordering a drink with several modifications, and the barista has follow-up questions.")
            ]),
            SituationBranch(label: "Paying", children: [
                SituationBranch(label: "Card declined",
                                situation: "At a cafe: my card gets declined at the register and I sort it out without holding up the line.")
            ])
        ]),
        SituationBranch(label: "Travel", icon: "airplane", children: [
            SituationBranch(label: "Immigration control", children: [
                SituationBranch(label: "Purpose-of-visit questions",
                                situation: "At immigration control: the officer asks why I'm visiting, how long I'm staying, and where."),
                SituationBranch(label: "Problem with my documents",
                                situation: "At immigration control: something's off with my documents and I explain calmly.")
            ]),
            SituationBranch(label: "Hotel", children: [
                SituationBranch(label: "Room isn't ready",
                                situation: "Hotel front desk: I arrive early, the room isn't ready, and I negotiate my options."),
                SituationBranch(label: "Something's wrong with the room",
                                situation: "Hotel front desk: the room has a problem and I ask to have it fixed or changed.")
            ])
        ]),
        SituationBranch(label: "Work", icon: "briefcase.fill", children: [
            SituationBranch(label: "Interview", children: [
                SituationBranch(label: "Job interview",
                                situation: "A job interview: introducing myself, walking through my experience, and why I want this role.")
            ]),
            SituationBranch(label: "Meeting", children: [
                SituationBranch(label: "Presenting my idea",
                                situation: "A team meeting: I present my idea, field questions, and handle pushback.")
            ]),
            SituationBranch(label: "With my manager", children: [
                SituationBranch(label: "Asking for time off",
                                situation: "A one-on-one with my manager: asking for time off next month and handling their concerns.")
            ])
        ]),
        SituationBranch(label: "Health", icon: "cross.case.fill", children: [
            SituationBranch(label: "Doctor's visit", children: [
                SituationBranch(label: "Describing a symptom",
                                situation: "At the doctor's office: describing a symptom I've had for a week and answering their questions.")
            ])
        ]),
        SituationBranch(label: "Shopping", icon: "bag.fill", children: [
            SituationBranch(label: "Returns", children: [
                SituationBranch(label: "No receipt",
                                situation: "At a store: returning an item without the receipt, and the clerk is skeptical.")
            ])
        ])
    ]
}

// MARK: - PersonBubble

/// THE counterpart avatar — initials on a tinted circle. Every surface that
/// shows a person (the stories row, the composer header, onboarding's People
/// visual) renders through this one view so they can't drift apart.
struct PersonBubble: View {
    let name: String
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
            Text(Books.initials(name))
                .font(size >= 56 ? .headline.weight(.bold) : .caption.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }
}

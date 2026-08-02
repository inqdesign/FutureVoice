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
///   3. Likely situations — a card grid of everyday territories; tapping a
///      card opens a step-by-step builder sheet (chip by chip, stoppable at
///      any depth).
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
    @State private var showingPeople = false
    @State private var showingNewVoice = false

    struct ComposerConfig: Identifiable {
        let id = UUID()
        var person: Counterpart?
        /// Pre-selected category (from a "Likely situations" card).
        var category: ScenarioComposerSheet.Category?
    }

    var body: some View {
        NavigationStack {
            List {
                peopleSection
                makeYourOwnSection
                scenariosSection
                likelySection
            }
            .listStyle(.insetGrouped)
            // The inset-grouped default top margin reads as a hole under the
            // inline-large title — pull the people row up close to the header.
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("Watch")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPeople = true } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Your people")
                }
            }
            .sheet(item: $composer) { cfg in
                // The ONE unified composer — same as Talk's "+", but its action
                // is Watch (play the scene). Saves the scenario, then plays it.
                ScenarioComposerSheet(person: cfg.person,
                                      initialCategory: cfg.category,
                                      ctaTitle: "Watch", ctaIcon: "play.fill") { scenario in
                    appState.saveScenario(scenario)
                    composer = nil
                    watchScene = WatchTarget(scenario: scenario, fresh: false)
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingPeople) {
                PeopleSheet(onNew: { showingPeople = false; showingNewVoice = true })
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView().environmentObject(appState)
            }
            .navigationDestination(item: $watchScene) { t in
                SceneWatchView(scenarioId: t.scenario.id, freshTake: t.fresh)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - 1. People (stories row)

    private var peopleSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(appState.counterparts) { c in
                        personBubble(c)
                    }
                    addPersonBubble
                }
                .padding(.vertical, 6)
            }
        } footer: {
            Text("Tap someone — situations with them, in their voice.")
                .padding(.horizontal, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func personBubble(_ c: Counterpart) -> some View {
        Button {
            composer = ComposerConfig(person: c)
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
                Text("New")
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
        appState.scenarios.filter { $0.isTopic != true }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    @ViewBuilder
    private var scenariosSection: some View {
        if !savedScenarios.isEmpty {
            Section {
                // Same 2-column card grid as "Likely situations" below.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(savedScenarios) { s in
                        scenarioCard(s)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Your scenarios")
            } footer: {
                Text("The situations you've built — every watch writes a fresh take. Past takes live in Practice.")
            }
        }
    }

    private func scenarioCard(_ s: Scenario) -> some View {
        let personaName = s.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }?.name
        }
        let partner = personaName
            ?? (s.role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.role)
        return Button {
            watchScene = WatchTarget(scenario: s, fresh: true)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if let personaName {
                    Text(Books.initials(personaName))
                        .font(.title3.weight(.bold)).foregroundStyle(.tint)
                } else {
                    Image(systemName: s.categoryIcon ?? Books.roleIcon(for: s.role))
                        .font(.title2).foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.cardTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let partner {
                        Text("with \(partner)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            // Fill the row's height so a short card matches its taller sibling
            // (LazyVGrid sizes the row to the tallest cell).
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        Section {
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
                        Text("The real thing coming up — an interview, a call, a visit. Describe it, watch it handled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. Likely situations (category cards → the unified composer)

    private var likelySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(prioritizedTree) { node in
                    categoryCard(node)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Likely situations")
        } footer: {
            Text("Tap a category — the composer suggests specific scenarios you can watch.")
        }
    }

    private func categoryCard(_ node: SituationBranch) -> some View {
        Button {
            // Jump into the unified composer pre-scoped to this category.
            composer = ComposerConfig(
                category: ScenarioComposerSheet.Category(title: node.label, icon: node.icon))
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: node.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(node.label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - Situation composer (bottom sheet)

/// The one place a situation gets made — reached from a persona bubble
/// (scoped to them, with relationship-grounded ideas), the "make your own"
/// button, or a drill-down leaf (prefilled, editable). Watch generates the
/// scene and plays it; the book lands in Practice.
struct SituationComposerSheet: View {
    let person: Counterpart?
    var initialText = ""
    /// Called with the freshly minted scenario after Watch is tapped.
    let onWatch: (Scenario) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var situation = ""
    @State private var ideas: [SuggestedTopic] = []
    @State private var loadingIdeas = false
    @State private var ideasError: String?
    // Who the scene's counterpart sounds like — always set when the sheet
    // isn't already scoped to a person. Defaults to the Me → Voice pick.
    @State private var selectedVoiceId: String = VoicePreset.sceneDefault.id
    @State private var pickedPersonId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                if let p = person { personHeader(p) }
                situationField
                if person == nil {
                    TalkingWithSection(selectedVoiceId: $selectedVoiceId,
                                       attachedPersonId: $pickedPersonId,
                                       counterparts: appState.counterparts)
                }
                if person != nil { ideasSection }
            }
            .navigationTitle(person.map { "With \($0.name)" } ?? "Your situation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                // Watch lives in the header, not a bottom bar — the sheet's
                // lower half stays free for the form and the keyboard.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startWatch() } label: {
                        Label("Watch", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Typing is OPTIONAL — the keyboard never pops on its own. The
            // sheet opens showing the ideas / the prefilled text; the field
            // activates only when the user taps it.
            .onAppear { situation = initialText }
            .task { await loadIdeasIfNeeded() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Pieces

    private func personHeader(_ p: Counterpart) -> some View {
        Section {
            HStack(spacing: 12) {
                PersonBubble(name: p.name, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.body.weight(.medium))
                    if !p.relationship.isEmpty {
                        Text(p.relationship).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var situationField: some View {
        Section {
            TextField(person == nil
                        ? "e.g. Lufthansa cabin-crew interview next week — I want to rehearse it"
                        : "e.g. Running into them at the wedding and catching up",
                      text: $situation, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("The situation")
        } footer: {
            Text("Be concrete — where, what's going on, what you want. Tap the keyboard mic to just say it.")
        }
    }

    /// Relationship-grounded situation ideas for THIS person — cached on the
    /// counterpart so reopening is free; refresh regenerates.
    @ViewBuilder
    private var ideasSection: some View {
        Section {
            if loadingIdeas && ideas.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Thinking of situations with them…").foregroundStyle(.secondary)
                }
            } else {
                ForEach(ideas) { idea in
                    Button {
                        situation = "\(idea.title). \(idea.blurb)"
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "text.insert")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.title).font(.subheadline).foregroundStyle(.primary)
                                if !idea.blurb.isEmpty {
                                    Text(idea.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let e = ideasError {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Ideas with \(person?.name ?? "")")
                Spacer()
                Button {
                    Task { await regenerateIdeas() }
                } label: {
                    if loadingIdeas {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(loadingIdeas)
            }
        }
    }

    // MARK: - Actions

    private func startWatch() {
        let description = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        let who = person ?? pickedPersonId.flatMap { id in
            appState.counterparts.first { $0.id == id }
        }
        var s = Scenario(
            environment: description,
            // No person → leave the role EMPTY: the scene infers the natural
            // counterpart from the situation itself (a landlord situation
            // casts a landlord, not a generic friend).
            role: who.map { $0.relationship.isEmpty ? $0.name : $0.relationship } ?? "",
            notes: ""
        )
        s.counterpartId = who?.id
        // No persona → the picked preset voice sticks to the scenario.
        s.voicePresetId = who == nil ? selectedVoiceId : nil
        appState.saveScenario(s)
        onWatch(s)
    }

    private func loadIdeasIfNeeded() async {
        guard let p = person, ideas.isEmpty else { return }
        if !p.savedScenarios(in: appState.targetLanguage).isEmpty {
            ideas = p.savedScenarios(in: appState.targetLanguage)
        } else {
            await regenerateIdeas()
        }
    }

    private func regenerateIdeas() async {
        guard let p = person else { return }
        loadingIdeas = true
        ideasError = nil
        defer { loadingIdeas = false }
        do {
            let fresh = try await TopicEngine.suggestForCounterpart(
                persona: appState.persona,
                counterpart: p,
                targetLanguage: appState.targetLanguage
            )
            ideas = fresh
            // Persist onto the counterpart so the next open is instant + free.
            var updated = p
            updated.setSavedScenarios(fresh, in: appState.targetLanguage)
            appState.saveCounterpart(updated)
        } catch {
            ideasError = error.localizedDescription
        }
    }
}

// MARK: - Step-by-step situation builder (bottom sheet)

/// Opened from a "Likely situations" card. The user sharpens the situation
/// chip by chip down the branch tree — and can stop at ANY depth: Watch is
/// always live in the header with whatever has been picked so far. Reaching
/// a leaf drops its full ready-made situation into the editable text.
struct SituationBuilderSheet: View {
    let root: WatchTab.SituationBranch
    /// Called with the freshly minted scenario after Watch is tapped.
    let onWatch: (Scenario) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Chips picked so far (below the root).
    @State private var path: [WatchTab.SituationBranch] = []
    /// The always-editable situation text — rewritten on every chip pick,
    /// free for the user to touch up before watching.
    @State private var situation = ""

    private var currentChildren: [WatchTab.SituationBranch] {
        path.last?.children ?? root.children
    }

    var body: some View {
        NavigationStack {
            Form {
                picksSection
                if !currentChildren.isEmpty { choicesSection }
                situationSection
            }
            .navigationTitle(root.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                // Header Watch — usable mid-chain, not just at a leaf.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startWatch() } label: {
                        Label("Watch", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if situation.isEmpty { situation = assembledText() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    /// The chosen chain so far, as chips — tap one to back up to that step.
    private var picksSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    stepChip(label: root.label, filled: path.isEmpty) {
                        backUp(to: 0)
                    }
                    ForEach(Array(path.enumerated()), id: \.element.id) { i, node in
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        stepChip(label: node.label, filled: i == path.count - 1) {
                            backUp(to: i + 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Your situation so far")
        }
    }

    private func stepChip(label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(filled ? Color.accentColor.opacity(0.15)
                                                  : Color(.tertiarySystemFill)))
                .foregroundStyle(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    /// The next refinement, as tappable chips.
    private var choicesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(currentChildren) { node in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { pick(node) }
                    } label: {
                        Text(node.label)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemFill)))
                            .foregroundStyle(.primary)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Sharpen it")
        } footer: {
            Text("Optional — pick a chip to go deeper, or hit Watch with what you have.")
        }
    }

    private var situationSection: some View {
        Section {
            TextField("Describe the situation", text: $situation, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("The situation")
        } footer: {
            Text("Watch uses this text — edit it freely.")
        }
    }

    // MARK: - Logic

    private func pick(_ node: WatchTab.SituationBranch) {
        path.append(node)
        situation = node.situation ?? assembledText()
    }

    private func backUp(to depth: Int) {
        guard depth < path.count else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            path.removeLast(path.count - depth)
            situation = path.last?.situation ?? assembledText()
        }
    }

    /// Situation text for a mid-chain stop — the picked labels, readable
    /// enough for the scene engine to cast and improvise the rest.
    private func assembledText() -> String {
        let labels = [root.label] + path.map(\.label)
        return labels.joined(separator: " — ") + ": a realistic everyday moment."
    }

    private func startWatch() {
        let description = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        // Role left empty — the scene infers the natural counterpart
        // (same policy as the free composer).
        let s = Scenario(environment: description, role: "", notes: "")
        appState.saveScenario(s)
        onWatch(s)
    }
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

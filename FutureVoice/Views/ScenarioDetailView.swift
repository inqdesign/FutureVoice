import SwiftUI

/// One scenario's "book" — the curriculum page. A scenario is not a replay
/// shortcut: it's a course with words, expressions, and shadow lines to
/// master. This page shows the syllabus with per-item mastery, the overall
/// progress, and the two study actions (Talk / Watch). Once everything is
/// mastered the book can be archived.
///
/// Items plug into the app's EXISTING learning surfaces rather than a
/// parallel system: a word opens its `WordCard` (dictionary, pronunciation,
/// your sentences, I-know-it) and is mastered through `VocabStore`; an
/// expression shadows its example sentence; shadow lines score in
/// `ShadowDrillView`. See `AppState.refreshScenarioMastery` for the rules.
/// Long-press any item to check it off manually.
struct ScenarioDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let scenarioId: UUID

    @State private var talkPresented = false
    @State private var watchPresented = false
    @State private var shadowTarget: Turn?
    @State private var wordSheet: WordRef?
    @State private var expressionSheet: WordRef?
    @State private var generating = false
    @State private var generationError: String?
    @State private var confirmDelete = false

    private struct WordRef: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Always read live from appState so saves (mastery, archive) reflect
    /// immediately without a local copy going stale.
    private var scenario: Scenario? {
        appState.scenarios.first { $0.id == scenarioId }
    }

    var body: some View {
        Group {
            if let s = scenario {
                content(s)
            } else {
                // Deleted while open — nothing to show.
                Color.clear
            }
        }
        .navigationTitle(scenario?.environment ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarMenu }
        .fullScreenCover(isPresented: $talkPresented, onDismiss: refreshMastery) {
            if let s = scenario {
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb)
                    .environmentObject(appState)
            }
        }
        .navigationDestination(isPresented: $watchPresented) {
            // Watch = replay THE scene the curriculum was extracted from —
            // never a fresh generation. Free after the first listen (the
            // audio content-cache holds every line).
            if let s = scenario, let c = s.curriculum {
                WatchView(counterpart: watchCounterpart(for: s),
                          savedDialogue: sceneDialogue(s, c),
                          // Already ON the book — pushing it again would
                          // stack the same page twice, so pop back to it.
                          handoff: .init(title: "Back to the book",
                                         action: { watchPresented = false }))
                    .environmentObject(appState)
            }
        }
        .sheet(item: $shadowTarget, onDismiss: refreshMastery) { turn in
            ShadowDrillView(turn: turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
        .sheet(item: $wordSheet, onDismiss: refreshMastery) { ref in
            // The app's ONE word surface — dictionary entry, pronunciation in
            // your voice, sentences from your talks, keep-studying / I-know-it.
            // Chevrons walk the scenario's word list.
            WordSheet(initialWord: ref.value,
                      words: scenario?.curriculum?.words
                          .map { VocabStore.lookupKey(for: $0.text) } ?? [])
                .environmentObject(appState)
        }
        .sheet(item: $expressionSheet, onDismiss: refreshMastery) { ref in
            // Same treatment as a word: the expression's card — meaning,
            // examples, pronunciation, shadow, I-know-it — with chevrons
            // walking the scenario's expression list.
            ExpressionSheet(initialPhrase: ref.value,
                            phrases: scenario?.curriculum?.expressions.map(\.text) ?? [])
                .environmentObject(appState)
        }
        .task { await ensureCurriculum() }
        .onAppear { refreshMastery() }
        .confirmationDialog("Delete this scenario?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appState.deleteScenario(id: scenarioId)
                dismiss()
            }
        } message: {
            Text(explain("The curriculum and its progress go with it."))
        }
    }

    // MARK: - Content

    private func content(_ s: Scenario) -> some View {
        List {
            headerSection(s)
            if s.isMastered && !s.isArchived { masteredBanner }
            if let c = s.curriculum {
                itemSection(title: "Words", icon: "textformat", items: c.words,
                            footer: "Tap a word for its card — meaning, pronunciation, your sentences. It's mastered once you use it in a talk or mark it known.",
                            showExample: false) { item in
                    // Same lemma key every other word surface uses, so the
                    // card's I-know-it lands on the record mastery reads.
                    wordSheet = WordRef(value: VocabStore.lookupKey(for: item.text))
                }
                itemSection(title: "Expressions", icon: "quote.opening", items: c.expressions,
                            footer: "Tap an expression for its card. It's mastered once you actually use it in a talk.",
                            showExample: true) { item in
                    expressionSheet = WordRef(value: item.text)
                }
                shadowSection(c)
            } else {
                curriculumLoadingSection
            }
            historySection(s)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Header (cover + progress + actions)

    private func headerSection(_ s: Scenario) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        if let name = linkedPersonaName(s) {
                            Text(Books.initials(name))
                                .font(.headline.weight(.bold)).foregroundStyle(.tint)
                        } else {
                            Image(systemName: Books.roleIcon(for: s.role))
                                .font(.title2).foregroundStyle(.tint)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.environment).font(.title3.weight(.semibold))
                        if let partner = linkedPersonaName(s)
                            ?? (s.role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.role) {
                            Text("with \(partner)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if s.isArchived {
                            Label("Archived", systemImage: "archivebox")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if !s.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(s.notes).font(.footnote).foregroundStyle(.secondary)
                }
                if let c = s.curriculum, c.totalCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: c.progress)
                            .tint(s.isMastered ? .green : .accentColor)
                        Text("\(c.masteredCount) of \(c.totalCount) mastered")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        appState.markScenarioUsed(id: s.id)
                        talkPresented = true
                    } label: {
                        Label("Talk", systemImage: "mic.fill")
                            // Inside a List the label's icon inherits the row
                            // tint (accent) — invisible on the prominent
                            // button's accent fill. Force the content white.
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    // Watch replays the book's ONE scene — the dialogue the
                    // checklist below was extracted from. Hidden until the
                    // scene has generated.
                    if !(s.curriculum?.dialogue ?? []).isEmpty {
                        Button {
                            watchPresented = true
                        } label: {
                            Label("Watch", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        } footer: {
            Text(explain("Watch the scene, study its words and expressions, shadow your lines, then Talk it live."))
        }
    }

    private var masteredBanner: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Book mastered").font(.subheadline.weight(.semibold))
                    Text(explain("Everything in this scenario is yours now."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Archive") {
                    appState.setScenarioArchived(id: scenarioId, true)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Curriculum sections

    private func itemSection(title: String, icon: String,
                             items: [ScenarioCurriculum.Item], footer: String,
                             showExample: Bool,
                             onTap: @escaping (ScenarioCurriculum.Item) -> Void) -> some View {
        Section {
            ForEach(items) { item in
                Button {
                    onTap(item)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        masteryMark(item.masteredAt != nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(.body)
                                .foregroundStyle(item.masteredAt != nil ? .secondary : .primary)
                            if !item.note.isEmpty {
                                Text(item.note).font(.caption).foregroundStyle(.secondary)
                            }
                            if showExample, let ex = item.example, !ex.isEmpty {
                                Text("\u{201C}\(ex)\u{201D}")
                                    .font(.caption).foregroundStyle(.tint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if item.masteredAt == nil {
                        Button {
                            appState.markCurriculumItemMastered(scenarioId: scenarioId, itemId: item.id)
                        } label: {
                            Label("Mark as mastered", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
        } header: {
            sectionHeader(title: title, icon: icon, items: items)
        } footer: {
            Text(footer)
        }
    }

    private func shadowSection(_ c: ScenarioCurriculum) -> some View {
        Section {
            ForEach(c.shadowLines) { line in
                Button {
                    // The line's id doubles as the synthetic Turn id, so
                    // attempts + cached TTS stay attached across opens.
                    shadowTarget = Turn(
                        id: line.id, role: .fluentSelf, audioURL: nil,
                        transcript: line.text, durationMs: 0,
                        timestamp: Date(), suggestion: nil
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        masteryMark(line.masteredAt != nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.body)
                                .foregroundStyle(line.masteredAt != nil ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !line.note.isEmpty {
                                Text(line.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if let best = bestShadowScore(for: line.id) {
                            Text("\(best)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(best >= ScenarioCurriculum.shadowMasteryScore ? .green : .secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if line.masteredAt == nil {
                        Button {
                            appState.markCurriculumItemMastered(scenarioId: scenarioId, itemId: line.id)
                        } label: {
                            Label("Mark as mastered", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
        } header: {
            sectionHeader(title: "Shadow these lines", icon: "waveform", items: c.shadowLines)
        } footer: {
            Text(explain("Tap a line to shadow it in your own voice. Score \(ScenarioCurriculum.shadowMasteryScore)+ and it's mastered."))
        }
    }

    private func sectionHeader(title: String, icon: String,
                               items: [ScenarioCurriculum.Item]) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            let done = items.filter { $0.masteredAt != nil }.count
            Text("\(done)/\(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(done == items.count && !items.isEmpty ? .green : .secondary)
        }
    }

    private func masteryMark(_ mastered: Bool) -> some View {
        Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(mastered ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
    }

    // MARK: - Curriculum generation

    @ViewBuilder
    private var curriculumLoadingSection: some View {
        Section {
            if generating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing this scenario's scene…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let e = generationError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(e).font(.caption).foregroundStyle(.red)
                    Button("Try again") {
                        Task { await ensureCurriculum(force: true) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        } footer: {
            if generating {
                Text(explain("One dialogue for exactly this situation — its words, expressions, and your lines become the checklist. Generated once, then it's your book."))
            }
        }
    }

    private func ensureCurriculum(force: Bool = false) async {
        // Regenerate when the scene is missing too — curricula from the
        // pre-scene schema have items but no dialogue to watch or shadow from.
        guard var s = scenario, (s.curriculum?.dialogue ?? []).isEmpty,
              force || !generating else { return }
        guard !generating else { return }
        generating = true
        generationError = nil
        defer { generating = false }
        do {
            let counterpart = s.counterpartId.flatMap { id in
                appState.counterparts.first { $0.id == id }
            }
            let curriculum = try await ScenarioCurriculumEngine.generate(
                scenario: s,
                persona: appState.persona,
                counterpart: counterpart,
                proficiency: appState.proficiency,
                targetLanguage: appState.targetLanguage,
                weakVocabAreas: appState.learnerProfile.weakVocabAreas,
                recurringMistakes: appState.learnerProfile.recurringMistakes
            )
            // Re-read: a Talk could have ended (marking lastUsedAt) meanwhile.
            guard var fresh = scenario else { return }
            fresh.curriculum = curriculum
            s = fresh
            appState.saveScenario(fresh)
            refreshMastery()
        } catch {
            generationError = error.localizedDescription
        }
    }

    // MARK: - History (study record under this book)

    @ViewBuilder
    private func historySection(_ s: Scenario) -> some View {
        let sessions = SessionStore.shared.load()
            .filter { $0.topic == s.displayTitle && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        if !sessions.isEmpty {
            Section("Study record") {
                ForEach(sessions.prefix(5), id: \.id) { session in
                    NavigationLink {
                        ConversationDetailView(session: session)
                            .environmentObject(appState)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.subheadline)
                                Text("\(session.turns.filter { $0.role == .user }.count) turns spoken")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The curriculum's stored scene wrapped as a replayable WatchDialogue.
    /// Nothing is persisted — the book already owns the turns; WatchView's
    /// savedDialogue path just hydrates and plays them.
    private func sceneDialogue(_ s: Scenario, _ c: ScenarioCurriculum) -> WatchDialogue {
        WatchDialogue(
            counterpartId: s.counterpartId ?? UUID(),
            scenarioTitle: s.displayTitle,
            scenarioBlurb: "",
            title: c.dialogueTitle,
            turns: c.dialogue ?? [],
            speakerName: linkedPersonaName(s) ?? s.role,
            voicePresetId: watchCounterpart(for: s).voicePresetId
        )
    }

    // MARK: - Toolbar

    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let s = scenario {
                    if s.isArchived {
                        Button {
                            appState.setScenarioArchived(id: scenarioId, false)
                        } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            appState.setScenarioArchived(id: scenarioId, true)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Helpers

    private func refreshMastery() {
        appState.refreshScenarioMastery(id: scenarioId)
    }

    private func bestShadowScore(for lineId: UUID) -> Int? {
        let scores = appState.shadowAttempts.filter { $0.turnId == lineId }.map(\.matchScore)
        return scores.max()
    }

    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    private func watchCounterpart(for s: Scenario) -> Counterpart {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id } }
            ?? Self.syntheticCounterpart(for: s)
    }

    /// Throwaway counterpart built from the scenario's role, so the scene can
    /// play with a preset voice when no real person is linked. Never saved.
    static func syntheticCounterpart(for s: Scenario) -> Counterpart {
        var c = Counterpart.empty
        c.name = s.role.trimmingCharacters(in: .whitespaces).isEmpty ? "the other person" : s.role
        c.location = s.environment
        c.background = s.notes
        c.voicePresetId = s.voicePresetId ?? VoicePreset.sceneDefault.id
        return c
    }
}

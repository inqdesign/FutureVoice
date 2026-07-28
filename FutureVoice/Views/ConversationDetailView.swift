import SwiftUI

/// One finished talk's "book" — the same page anatomy as a Watch book
/// (ScenarioDetailView): header with progress + the two actions
/// (Continue / Replay), then the checklist of review material, then the
/// score. The material is DERIVED from the session by `TalkCurriculum`
/// (pickup words + corrected lines), and mastery rides the app's existing
/// engines (VocabStore, shadow attempts) — nothing here keeps its own books.
///
/// The raw conversation lives behind Replay (`TalkTranscriptView`), exactly
/// like a Watch book's scene lives behind its Watch button.
struct ConversationDetailView: View {
    @EnvironmentObject private var appState: AppState
    /// State (not let) so misheard-turn exclusions — made in the grammar
    /// review sheet or the transcript — reflect immediately in the score.
    @State private var session: Session
    /// Set when this page is the wrap-up shown right after the talk ends —
    /// adds Done + start-new/practice actions and the fresh shadow material.
    /// Nil when opened from Practice: same page, browsing mode. ONE session
    /// detail page for both moments.
    var postTalk: PostTalkActions? = nil

    init(session: Session, postTalk: PostTalkActions? = nil) {
        _session = State(initialValue: session)
        self.postTalk = postTalk
    }
    // Observed so mastery rows restyle live when a word card marks a word
    // known / studying.
    @ObservedObject private var vocab = VocabStore.shared

    struct PostTalkActions {
        let onDone: () -> Void
        let onStartNew: () -> Void
    }

    @Environment(\.dismiss) private var dismiss
    @State private var curriculum = TalkCurriculum.Snapshot()
    @State private var archivedAt: Date?
    @State private var showingDeleteConfirm = false
    @State private var drillCount = 0
    @State private var showingContinue = false
    @State private var showingTranscript = false
    @State private var wordSheet: WordRef?
    @State private var shadowLine: ScenarioCurriculum.Item?
    /// Fluent-self line being shadowed from the post-talk "while it's fresh"
    /// list (distinct from `shadowLine`, which is a corrected user sentence).
    @State private var fluentShadowTurn: Turn?

    private struct WordRef: Identifiable {
        let value: String
        /// Sibling list the word was tapped from — the sheet's chevrons walk
        /// this order.
        var siblings: [String] = []
        var id: String { value }
    }

    private enum WordsTab { case you, futureSelf }
    @State private var wordsTab: WordsTab = .you

    var body: some View {
        List {
            // Same vertical story as the old analysis screen — score, note,
            // then the session highlights — wrapped in the book-page frame
            // (header with progress + Continue/Replay on top, mastery +
            // drills at the bottom).
            headerSection
            if curriculum.isMastered && archivedAt == nil { masteredBanner }
            if let sc = session.summary?.scorecard { scoreSection(sc) }
            if let note = session.summary?.overallNote, !note.isEmpty { noteSection(note) }
            freshShadowSection
            newWordsSection
            expressionsSection
            sayItBetterSection
            shadowSection
            drillNextSection
            drillsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarMenu }
        .onAppear(perform: refresh)
        .navigationDestination(isPresented: $showingTranscript) {
            TalkTranscriptView(session: session)
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showingContinue, onDismiss: refresh) {
            ConversationView(resumeSession: session)
                .environmentObject(appState)
        }
        .sheet(item: $wordSheet, onDismiss: refresh) { ref in
            // The app's ONE word surface — same card the scenario books open.
            // Chevrons walk the list the word was tapped from.
            WordSheet(initialWord: ref.value, words: ref.siblings)
                .environmentObject(appState)
        }
        .sheet(item: $shadowLine, onDismiss: refresh) { item in
            // The item id doubles as the synthetic Turn id (stable, derived
            // from the source turn), so attempts + cached TTS stay attached.
            ShadowDrillView(
                turn: Turn(id: item.id, role: .fluentSelf, audioURL: nil,
                           transcript: item.text, durationMs: 0,
                           timestamp: session.startedAt, suggestion: nil),
                targetLanguage: appState.targetLanguage
            )
            .environmentObject(appState)
        }
        .sheet(item: $fluentShadowTurn, onDismiss: refresh) { turn in
            ShadowDrillView(turn: turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
        .safeAreaInset(edge: .bottom) { postTalkBar }
        .confirmationDialog("Delete this talk?", isPresented: $showingDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete talk", role: .destructive) {
                appState.deleteSession(id: session.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The conversation, its score, review cards and audio are removed for good. To keep it but leave it out of your stats, archive it instead.")
        }
    }

    // MARK: - Header (cover + progress + actions)

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title2).foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayTitle)
                            .font(.title3.weight(.semibold)).lineLimit(2)
                        Text("\((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened)) · \(session.turns.filter { $0.role == .user }.count) turns spoken")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if archivedAt != nil {
                            Label("Archived", systemImage: "archivebox")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if curriculum.totalCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: curriculum.progress)
                            .tint(curriculum.isMastered ? .green : .accentColor)
                        Text("\(curriculum.masteredCount) of \(curriculum.totalCount) mastered")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    // Post-talk the bottom bar owns "start a new conversation";
                    // stacking a Continue full-screen cover over the just-torn-
                    // down call would double up the call UI.
                    if postTalk == nil {
                        Button {
                            showingContinue = true
                        } label: {
                            Label("Continue", systemImage: "bubble.left.and.bubble.right.fill")
                                // Row tint would swallow the icon on the prominent
                                // fill — force the content white (same fix as the
                                // scenario book's Talk button).
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        showingTranscript = true
                    } label: {
                        Label("Replay", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        } footer: {
            Text("Replay the talk, pick up its words, shadow the smoother versions of your own lines — then continue the conversation.")
        }
    }

    private var masteredBanner: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk mastered").font(.subheadline.weight(.semibold))
                    Text("Everything this conversation had to teach is yours.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Archive") { setArchived(true) }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Session highlights (the analysis screen's core content)

    /// "New words" — BOTH sides, exactly as the analysis screen always showed
    /// them: words YOU used for the first time this talk (the win), and words
    /// your future self used that you haven't yet (the next step — these are
    /// also the book's word-mastery items). Level-grouped chips; chip state =
    /// your relationship to the word (known / studying / untouched).
    @ViewBuilder
    private var newWordsSection: some View {
        let mine = session.summary?.newWordsUsed ?? []
        let theirs = curriculum.words.map(\.text)
        if !mine.isEmpty || !theirs.isEmpty {
            let tab: WordsTab = mine.isEmpty ? .futureSelf : (theirs.isEmpty ? .you : wordsTab)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if !mine.isEmpty, !theirs.isEmpty {
                        Picker("Source", selection: $wordsTab) {
                            Text("You · \(mine.count)").tag(WordsTab.you)
                            Text("Future self · \(theirs.count)").tag(WordsTab.futureSelf)
                        }
                        .pickerStyle(.segmented)
                    }
                    if tab == .you {
                        levelGroupedChips(mine)
                    } else {
                        Text("Your future self used these; you haven't yet. Tap one to study it — or mark it as known.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        levelGroupedChips(theirs)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Label("New words", systemImage: "text.book.closed")
            }
        }
    }

    @ViewBuilder
    private var expressionsSection: some View {
        if let sum = session.summary, !sum.expressionsUsed.isEmpty {
            Section {
                ForEach(sum.expressionsUsed, id: \.self) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.top, 3)
                        Text(e).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Label("Expressions you used", systemImage: "quote.bubble")
            }
        }
    }

    @ViewBuilder
    private var sayItBetterSection: some View {
        if let sum = session.summary, !sum.phrasesUsed.isEmpty {
            Section {
                ForEach(sum.phrasesUsed) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.userSaid)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(highlightedCorrection(p.fluentAlternative, original: p.userSaid, baseFont: .subheadline))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("Say it better", systemImage: "sparkles")
            }
        }
    }

    /// Word chips grouped by CEFR level (same grouping as the post-talk
    /// summary sheet) — each chip opens the word's dictionary card.
    private func levelGroupedChips(_ words: [String]) -> some View {
        let grouped = Dictionary(grouping: words) { CoreVocabulary.level(of: $0) }
        // Flattened display order — the word sheet's chevrons walk this same
        // order, so "next" in the sheet matches "next chip" on screen.
        let ordered = CEFRLevel.allCases.flatMap { grouped[$0] ?? [] } + (grouped[nil] ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(CEFRLevel.allCases, id: \.self) { lv in
                if let ws = grouped[lv], !ws.isEmpty {
                    levelChipRow(lv.rawValue.uppercased(), ws, ordered: ordered)
                }
            }
            if let other = grouped[nil], !other.isEmpty {
                levelChipRow("Other", other, ordered: ordered)
            }
        }
    }

    private func levelChipRow(_ label: String, _ words: [String], ordered: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(words, id: \.self) { w in wordChip(w, siblings: ordered) }
            }
        }
    }

    /// One word chip, styled by the user's relationship to the word so the
    /// three states read at a glance — the state lives in the ICON, on a calm
    /// neutral capsule (matching the word card's "I know it" button, where
    /// only the checkmark is green):
    /// green ✓ = known/used · accent bookmark = studying · outline = untouched.
    /// Tapping opens the word card, whose "I know it" / "Keep studying"
    /// actions restyle the chip live.
    private func wordChip(_ w: String, siblings: [String]) -> some View {
        let studying = vocab.isStudying(w)
        let known = !studying && vocab.state(of: w) != nil
        return Button { wordSheet = WordRef(value: w, siblings: siblings) } label: {
            HStack(spacing: 5) {
                if studying {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                } else if known {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text(w).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                if studying || known {
                    Capsule().fill(Color(.tertiarySystemFill))
                } else {
                    Capsule().strokeBorder(Color(.separator))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review material

    @ViewBuilder
    private var shadowSection: some View {
        if !curriculum.shadowLines.isEmpty {
            Section {
                ForEach(curriculum.shadowLines) { line in
                    Button {
                        shadowLine = line
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
                }
            } header: {
                sectionHeader(title: "Say it smoother", icon: "waveform", items: curriculum.shadowLines)
            } footer: {
                Text("The fluent versions of your own sentences from this talk. Shadow one in your voice — score \(ScenarioCurriculum.shadowMasteryScore)+ and it's mastered.")
            }
        }
    }

    /// This session's cards as a swipe deck — shared destination for the
    /// drills rows and the post-talk practice CTA.
    private var sessionDeck: some View {
        DrillView(source: .session(session.id))
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
    }

    /// The wrap-up's "shadow this conversation" list: the last substantial
    /// fluent-self lines of THIS talk, shadowable in one tap (the full
    /// per-line list lives in Replay).
    @ViewBuilder
    private var freshShadowSection: some View {
        let lines = Array(
            session.turns.filter { $0.role == .fluentSelf
                && $0.transcript.split(separator: " ").count >= 4 }
            .suffix(4)
        )
        if !lines.isEmpty {
            Section {
                ForEach(lines) { turn in
                    Button {
                        fluentShadowTurn = turn
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            Text(turn.transcript)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Shadow this conversation")
            } footer: {
                Text("Repeat your fluent self's lines from this talk.")
            }
        }
    }

    /// The wrap-up's "Drill next" list — phrases slightly above the user's
    /// level to practice NEXT (already ingested as cards; each row drops into
    /// this session's deck).
    @ViewBuilder
    private var drillNextSection: some View {
        if let drills = session.summary?.suggestedDrills, !drills.isEmpty {
            Section("Drill next") {
                ForEach(drills, id: \.self) { drill in
                    NavigationLink {
                        sessionDeck
                    } label: {
                        Text(drill)
                    }
                }
            }
        }
    }

    /// Practice-first close-out, unchanged from the old wrap-up sheet: the
    /// primary action reviews this talk's cards, the secondary starts a new
    /// conversation.
    @ViewBuilder
    private var postTalkBar: some View {
        if let postTalk {
            VStack(spacing: 10) {
                if drillCount > 0 {
                    NavigationLink {
                        sessionDeck
                    } label: {
                        Label(drillCount == 1
                              ? "Practice this card"
                              : "Practice these \(drillCount) cards",
                              systemImage: "rectangle.stack.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                // Secondary once there are cards (Practice stays the clear
                // primary); the sole prominent action otherwise.
                if drillCount > 0 {
                    startNewButton(postTalk).buttonStyle(.bordered)
                } else {
                    startNewButton(postTalk).buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func startNewButton(_ postTalk: PostTalkActions) -> some View {
        Button {
            postTalk.onStartNew()
        } label: {
            Label("Start a new conversation", systemImage: "arrow.uturn.left")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var drillsSection: some View {
        if drillCount > 0 {
            Section {
                NavigationLink {
                    sessionDeck
                } label: {
                    HStack {
                        Label("Cards from this talk", systemImage: "rectangle.stack")
                        Spacer()
                        Text("\(drillCount)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("A quick active-recall run through this talk's saved phrases.")
            }
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

    // MARK: - Score & note

    /// The full scorecard — the same component the wrap-up always used: axis
    /// notes, the tappable grammar row (review sheet with highlighted slips +
    /// the user's own recordings), and the pronunciation row. Replaces the old
    /// bars-only rendering so past talks keep every detail the wrap-up showed.
    private func scoreSection(_ sc: SessionScorecard) -> some View {
        Section("Score") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Overall").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(overall(sc))").font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle(color(overall(sc)))
                }
                // The scores are feedback on THIS talk, graded against the
                // user's LEVEL SETTING (Me tab) — say so precisely, or "your
                // C1 level" reads as a level claim that can contradict the
                // measured level.
                Text(scoreContextLine(sc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScorecardView(scorecard: sc,
                              grammarIssues: session.summary?.grammarIssues ?? [],
                              userTurns: session.turns.filter { $0.role == .user },
                              sessionId: session.id,
                              onSessionUpdated: {
                                  session = $0
                                  // Corrected evidence can void the latest
                                  // level assessment — re-run it if this talk
                                  // was part of its window.
                                  appState.reassessAfterEvidenceChange(in: $0)
                              })
            }
            .padding(.vertical, 6)
        }
    }

    private func noteSection(_ note: String) -> some View {
        Section("Coach's note") {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Toolbar

    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let postTalk {
                Button("Done") { postTalk.onDone() }
                    .fontWeight(.semibold)
            } else {
                Menu {
                    if archivedAt != nil {
                        Button { setArchived(false) } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button { setArchived(true) } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete talk", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Data

    private func refresh() {
        // Pick up store-side changes (misheard exclusions made from the
        // transcript, a continued conversation's new turns).
        if let fresh = SessionStore.shared.load().first(where: { $0.id == session.id }) {
            session = fresh
        }
        curriculum = TalkCurriculum.build(session: session,
                                          proficiency: appState.proficiency,
                                          shadowAttempts: appState.shadowAttempts)
        archivedAt = SessionStore.shared.load().first { $0.id == session.id }?.archivedAt
            ?? session.archivedAt
        drillCount = DrillStore.shared.load().filter { $0.sourceSessionId == session.id }.count
    }

    private func setArchived(_ flag: Bool) {
        // Via AppState: archiving pulls the talk out of the score/assessment
        // evidence, which may re-run the latest assessment.
        appState.setSessionArchived(id: session.id, flag)
        archivedAt = flag ? Date() : nil
    }

    private func bestShadowScore(for lineId: UUID) -> Int? {
        let scores = appState.shadowAttempts.filter { $0.turnId == lineId }.map(\.matchScore)
        return scores.max()
    }

    /// One caption explaining what the 0–100 scores are relative to. The
    /// grading anchor is the user's level SETTING; when the analyzer also
    /// took an independent read of this talk's level, show that too — it's
    /// the honest per-talk level signal.
    private func scoreContextLine(_ sc: SessionScorecard) -> String {
        let setting = appState.proficiency.rawValue.uppercased()
        if let read = sc.cefrLevel?.uppercased() {
            return "Scored against your \(setting) level setting — this talk itself read as ≈\(read)."
        }
        return "Scored against your \(setting) level setting — how this talk went, not a level rating."
    }

    private func overall(_ sc: SessionScorecard) -> Int {
        var s = [sc.vocabulary.score, sc.grammar.score, sc.expressiveness.score, sc.fluency.score]
        if let p = sc.pronunciation { s.append(p.score) }
        return s.isEmpty ? 0 : s.reduce(0, +) / s.count
    }

    private func color(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }
}

// MARK: - Replay (the raw conversation)

/// The talk's "scene": the full transcript (same `DialogueLine` rows as the
/// live call), a sequential audio replay of the whole conversation, and the
/// Continue action — mirroring how a Watch book replays its dialogue.
struct TalkTranscriptView: View {
    @EnvironmentObject private var appState: AppState
    /// State so misheard-turn exclusions restyle the row in place.
    @State private var session: Session
    @StateObject private var player = AudioPlayer()

    init(session: Session) {
        _session = State(initialValue: session)
    }
    @ObservedObject private var vocab = VocabStore.shared

    @State private var wordSheet: WordSheetItem?
    /// Core-list words the fluent self used that the user hasn't yet — their
    /// natural next words, computed on appear (drives inline highlights).
    @State private var fluentSelfNewWords: [String] = []
    /// Per-turn notebook lookup key for every transcript token (NLTagger is
    /// too slow to run inside row bodies), computed once on appear.
    @State private var turnTokenKeys: [UUID: [String]] = [:]
    @State private var showingContinue = false
    @State private var isPlaying = false
    @State private var currentIndex: Int?

    private struct WordSheetItem: Identifiable {
        let word: String
        var words: [String] = []
        var id: String { word }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Highlighted words are worth picking up — tap one to check it out.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(session.turns.enumerated()), id: \.element.id) { idx, turn in
                        VStack(alignment: .leading, spacing: 4) {
                            TranscriptRow(turn: turn,
                                          nativeLanguage: appState.nativeLanguage,
                                          targetLanguage: appState.targetLanguage,
                                          player: player,
                                          tokenKeys: turnTokenKeys[turn.id] ?? [],
                                          highlightedIndices: highlightIndices(for: turn),
                                          onWordTap: { key in
                                              wordSheet = WordSheetItem(
                                                  word: key,
                                                  words: fluentSelfNewWords.contains(key) ? fluentSelfNewWords : [])
                                          })
                                .opacity(turn.excludedFromScoring ? 0.45 : 1)
                            if turn.excludedFromScoring {
                                Label("Excluded from scoring — marked as misheard", systemImage: "mic.slash")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .id(idx)
                        .contextMenu {
                            if turn.role == .user && !turn.excludedFromScoring {
                                Button(role: .destructive) {
                                    if let updated = SessionStore.shared.excludeTurnFromScoring(
                                        sessionId: session.id, turnId: turn.id) {
                                        withAnimation { session = updated }
                                        appState.reassessAfterEvidenceChange(in: updated)
                                    }
                                } label: {
                                    Label("Misheard — exclude from scoring", systemImage: "mic.slash")
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: currentIndex) { _, idx in
                if let idx { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(idx, anchor: .center) } }
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { controls }
        .onAppear {
            fluentSelfNewWords = VocabStore.shared.pickupWords(
                fromFluentTexts: session.turns.filter { $0.role == .fluentSelf }.map(\.transcript),
                atOrAbove: appState.proficiency)
            var keys: [UUID: [String]] = [:]
            for turn in session.turns where turn.role == .fluentSelf {
                keys[turn.id] = turn.transcript.split(separator: " ")
                    .map { VocabStore.lookupKey(for: String($0)) }
            }
            turnTokenKeys = keys
        }
        .onDisappear {
            // Gate before stopping — stop() fires the current completion,
            // which would otherwise chain into the next turn after the view
            // is gone (same trap WatchView documents).
            isPlaying = false
            player.stop()
        }
        .fullScreenCover(isPresented: $showingContinue) {
            ConversationView(resumeSession: session)
                .environmentObject(appState)
        }
        .sheet(item: $wordSheet) { item in
            WordSheet(initialWord: item.word, words: item.words)
                .environmentObject(appState)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                if isPlaying {
                    isPlaying = false
                    player.stop()
                } else {
                    Task { await playFrom(index: currentIndex ?? 0) }
                }
            } label: {
                Label(isPlaying ? "Pause" : "Replay",
                      systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                isPlaying = false
                player.stop()
                showingContinue = true
            } label: {
                Label("Continue", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Sequential replay of the stored per-turn audio (user mic + synthesized
    /// fluent-self lines). Turns whose audio didn't survive are skipped, not
    /// re-synthesized — replay is always free.
    private func playFrom(index: Int) async {
        guard index < session.turns.count else { return }
        isPlaying = true
        var i = index
        while isPlaying && i < session.turns.count {
            let turn = session.turns[i]
            guard let data = TurnAudioStore.shared.data(for: turn.id)
                    ?? turn.audioURL.flatMap({ try? Data(contentsOf: $0) }) else {
                i += 1
                continue
            }
            currentIndex = i
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    do {
                        try player.play(data) { cont.resume(returning: ()) }
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            } catch {
                isPlaying = false
                return
            }
            i += 1
        }
        isPlaying = false
        currentIndex = nil
    }

    /// Token indices worth the user's attention in a fluent-self line: pickup
    /// words they haven't touched, plus words they're actively studying.
    private func highlightIndices(for turn: Turn) -> Set<Int> {
        guard let keys = turnTokenKeys[turn.id] else { return [] }
        let pickup = Set(fluentSelfNewWords)
        var out = Set<Int>()
        for (i, key) in keys.enumerated() where !key.isEmpty {
            if vocab.isStudying(key) || (pickup.contains(key) && vocab.state(of: key) == nil) {
                out.insert(i)
            }
        }
        return out
    }
}

/// Hosts the word card inside the detail page's sheet with its OWN
/// current-word state: the chevrons swap the word in place, and the sheet
/// item (the originally tapped word) never changes identity — changing it
/// would dismiss and re-present the sheet, exactly the close-and-reopen
/// this exists to avoid.
/// Word-detail sheet — the full `WordCard` (definition, pronunciation,
/// examples, shadow, mark-known) with header chevrons to walk siblings.
/// Reused wherever a word chip should "open and check out" rather than just
/// flip to its meaning (session words, home notebook grid).
struct WordSheet: View {
    let initialWord: String
    /// Sibling words in display order; empty → the card falls back to
    /// notebook navigation (transcript word taps).
    let words: [String]
    @State private var current: String?

    var body: some View {
        NavigationStack {
            WordCard(word: current ?? initialWord,
                     currentWord: Binding(
                        get: { current ?? initialWord },
                        set: { if let w = $0 { current = w } }
                     ),
                     navigationWords: words.isEmpty ? nil : words)
        }
    }
}

/// All past conversations → each opens its book page.
struct ConversationsListView: View {
    @State private var sessions: [Session] = []

    var body: some View {
        List(sessions) { s in
            NavigationLink {
                ConversationDetailView(session: s)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.displayTitle).font(.body).lineLimit(1)
                    Text((s.endedAt ?? s.startedAt).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            sessions = SessionStore.shared.load()
                .filter { $0.endedAt != nil }
                .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        }
    }
}

/// One transcript line — role, text, optional audio replay, "meaning" toggle,
/// and (for the user's lines) the more-natural suggestion.
private struct TranscriptRow: View {
    @EnvironmentObject private var appState: AppState
    let turn: Turn
    let nativeLanguage: String
    let targetLanguage: String
    @ObservedObject var player: AudioPlayer
    /// Notebook lookup key per transcript token (parent precomputes — NLTagger
    /// is too slow for row bodies), aligned with `transcript.split(" ")`.
    let tokenKeys: [String]
    /// Token indices highlighted as worth picking up; only these are tappable.
    let highlightedIndices: Set<Int>
    /// Called with the notebook lookup key when the user taps a highlighted
    /// word in a fluent-self line.
    let onWordTap: (String) -> Void

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false
    @State private var reasonNative: String?
    @State private var reasonShowing = false
    @State private var reasonLoading = false
    @State private var showingShadow = false
    @State private var showingSuggestionShadow = false

    /// The fluent-self line as one attributed string: normal text, except
    /// pickup-worthy words which are tinted, dot-underlined, and carry a
    /// `futurevoice://word/<tokenIndex>` link so they're tappable inline.
    private var highlightedTranscript: AttributedString {
        let tokens = turn.transcript.split(separator: " ")
        var out = AttributedString()
        for (index, token) in tokens.enumerated() {
            var piece = AttributedString(String(token))
            if highlightedIndices.contains(index) {
                piece.foregroundColor = .accentColor
                piece.font = .body.weight(.medium)
                piece.underlineStyle = Text.LineStyle(pattern: .dot)
                piece.link = URL(string: "futurevoice://word/\(index)")
            }
            out += piece
            if index < tokens.count - 1 { out += AttributedString(" ") }
        }
        return out
    }

    /// Speaker separation comes from `DialogueLine` — the same component the
    /// live call screen and Watch use — so all three stay in sync.
    private var speaker: DialogueSpeaker { turn.role == .user ? .user : .other }

    var body: some View {
        DialogueLine(speaker: speaker,
                     name: turn.role == .user ? "You" : "Future self") {
            if turn.role == .fluentSelf {
                // One Text with normal word spacing — only the few words worth
                // picking up are highlighted and tappable (as inline links) →
                // dictionary card. Highlighting every word carried no signal;
                // the highlight IS the signal. Per-word token views made the
                // line read as oddly justified text.
                Text(highlightedTranscript)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "futurevoice", url.host() == "word",
                              let index = Int(url.lastPathComponent),
                              index < tokenKeys.count, !tokenKeys[index].isEmpty
                        else { return .discarded }
                        HapticEngine.light()
                        onWordTap(tokenKeys[index])
                        return .handled
                    })
            } else {
                Text(turn.transcript)
            }
        } accessory: {
            VStack(alignment: speaker.alignment, spacing: 8) {
                // One action row per line. Listen works for the user's own turns
                // too (their mic audio is kept from the conversation); Shadow and
                // Meaning only make sense on the fluent self's lines — translating
                // the user's own words back at them says nothing.
                if hasAudio || turn.role == .fluentSelf {
                    HStack(spacing: 8) {
                        if hasAudio {
                            Button { playTurn() } label: {
                                Label("Listen", systemImage: "play.circle")
                            }
                        }
                        if turn.role == .fluentSelf, hasAudio {
                            Button { showingShadow = true } label: {
                                Label("Shadow", systemImage: "waveform.badge.mic")
                            }
                        }
                        if turn.role == .fluentSelf {
                            Button(action: toggleMeaning) {
                                HStack(spacing: 4) {
                                    if loading { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "character.bubble") }
                                    Text(showing ? "Hide meaning" : "Meaning")
                                }
                            }
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.accentColor)
                }

                if turn.role == .fluentSelf, showing, let t = translation {
                    Text(t).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if turn.role == .user, let s = turn.suggestion {
                    suggestionBox(s)
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingShadow) {
            ShadowDrillView(turn: turn, targetLanguage: targetLanguage)
                .environmentObject(appState)
        }
    }

    /// The correction — the part of the session that actually teaches. Changed
    /// words are emphasized, and it's shadowable like any fluent-self line
    /// (ShadowDrillView synthesizes the audio in the user's cloned voice).
    private func suggestionBox(_ s: TurnSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("More natural", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(highlightedCorrection(s.alternative, original: turn.transcript, baseFont: .callout))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.reason).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showingSuggestionShadow = true } label: {
                Label("Shadow", systemImage: "waveform.badge.mic")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            Button { toggleReason(s) } label: {
                HStack(spacing: 4) {
                    if reasonLoading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "character.bubble") }
                    Text(reasonShowing ? "Hide" : "Explain in my language")
                }
                .font(.caption2).foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            if reasonShowing, let r = reasonNative {
                Text(r).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
        .sheet(isPresented: $showingSuggestionShadow) {
            ShadowDrillView(turn: suggestionTurn(s), targetLanguage: targetLanguage)
                .environmentObject(appState)
        }
    }

    /// A synthetic fluent-self turn for shadowing the suggestion. The id is
    /// the talk-curriculum shadow-line id (derived from the real turn's id),
    /// so attempts recorded here master the book's line and cached audio is
    /// shared across both surfaces.
    private func suggestionTurn(_ s: TurnSuggestion) -> Turn {
        Turn(id: TalkCurriculum.shadowLineId(for: turn.id), role: .fluentSelf, audioURL: nil,
             transcript: s.alternative, durationMs: 0,
             timestamp: turn.timestamp, suggestion: nil)
    }

    /// Audio exists if TurnAudioStore still has it (resolved from the CURRENT
    /// Documents path by turnId — survives the app-container path changing on
    /// reinstall/update, which would have invalidated the stored absolute URL).
    private var hasAudio: Bool {
        TurnAudioStore.shared.url(for: turn.id) != nil || turn.audioURL != nil
    }

    private func playTurn() {
        let data = TurnAudioStore.shared.data(for: turn.id)
            ?? turn.audioURL.flatMap { try? Data(contentsOf: $0) }
        guard let data else { return }
        try? player.play(data, forceSessionReset: true)
    }

    private func toggleMeaning() {
        if showing { showing = false; return }
        showing = true
        guard translation == nil else { return }
        if let c = Translator.cached(turn.transcript, to: nativeLanguage) { translation = c; return }
        loading = true
        Task {
            let t = await Translator.translate(turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }

    /// "Explain in my language": a real native-language explanation of what
    /// changed between the user's line and the suggestion — not a translation
    /// of the generic English reason string, which explains nothing.
    private func toggleReason(_ s: TurnSuggestion) {
        if reasonShowing { reasonShowing = false; return }
        reasonShowing = true
        guard reasonNative == nil else { return }
        if let c = Translator.cachedExplanation(original: turn.transcript, alternative: s.alternative,
                                                to: nativeLanguage) {
            reasonNative = c
            return
        }
        reasonLoading = true
        Task {
            let t = await Translator.explainCorrection(original: turn.transcript, alternative: s.alternative,
                                                       to: nativeLanguage)
            reasonNative = t
            reasonLoading = false
            if t == nil { reasonShowing = false }
        }
    }
}

/// Word-level emphasis for a correction: returns the alternative with the
/// words that differ from what the user actually said in accent + semibold,
/// so the fixed parts are visible at a glance. LCS over normalized words —
/// case/punctuation differences alone don't count as changes.
func highlightedCorrection(_ alternative: String, original: String, baseFont: Font) -> AttributedString {
    func norm(_ s: Substring) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
    let altWords = alternative.split(separator: " ", omittingEmptySubsequences: true)
    let a = altWords.map(norm)
    let o = original.split(separator: " ", omittingEmptySubsequences: true).map(norm)
    let m = a.count, n = o.count

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in stride(from: m - 1, through: 0, by: -1) {
        for j in stride(from: n - 1, through: 0, by: -1) {
            dp[i][j] = a[i] == o[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
        }
    }
    var kept = Array(repeating: false, count: m)
    var i = 0, j = 0
    while i < m, j < n {
        if a[i] == o[j] { kept[i] = true; i += 1; j += 1 }
        else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 }
        else { j += 1 }
    }

    var out = AttributedString()
    for (idx, word) in altWords.enumerated() {
        var piece = AttributedString(String(word))
        // Punctuation-only tokens (a lone dash) normalize to "" — never worth
        // highlighting on their own.
        if !kept[idx], !a[idx].isEmpty {
            piece.foregroundColor = .accentColor
            piece.font = baseFont.weight(.semibold)
        }
        out += piece
        if idx < altWords.count - 1 { out += AttributedString(" ") }
    }
    return out
}

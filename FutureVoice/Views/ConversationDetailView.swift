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
    /// adds the Done close action and titles the page as the review book.
    /// Nil when opened from Practice: same page, browsing mode. ONE session
    /// detail page for both moments.
    var postTalk: PostTalkActions? = nil

    init(session: Session, postTalk: PostTalkActions? = nil,
         initialChapter: Chapter? = nil) {
        _session = State(initialValue: session)
        self.postTalk = postTalk
        self.initialChapter = initialChapter
    }
    // Observed so mastery rows restyle live when a word card marks a word
    // known / studying.
    @ObservedObject private var vocab = VocabStore.shared

    struct PostTalkActions {
        let onDone: () -> Void
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

    /// The book's chapters, switched in place by the ribbon bookmarks. The
    /// intro is the cover — title, progress, the Continue/Replay actions,
    /// the score and the coach's note. Internal so the DEBUG capture harness
    /// can open on a chapter.
    enum Chapter: Int, Hashable {
        case intro, words, expressions, lines, cards
    }

    /// Which bookmark tab to open the book on — nil opens on the intro.
    var initialChapter: Chapter? = nil
    @State private var selectedChapter: Chapter?

    /// Re-running the analysis for a talk whose summary never landed.
    @State private var isRegenerating = false
    @State private var regenerateError: String?
    @State private var showingPaywall = false
    /// The failure was the 402 credit gate — retrying can only fail again, so
    /// the alert leads to the paywall instead of a dead-end OK.
    @State private var regenerateOutOfCredits = false

    var body: some View {
        // The book's fixed layout: the page fills the screen, the ribbons
        // never move, and only the open chapter scrolls — inside the page.
        // The intro chapter is the cover AND the report (score, note,
        // carryover): the post-talk payoff in one place.
        BookmarkedPage(
            tabs: allTabs,
            selection: activeChapter,
            onSelect: { selectedChapter = $0 }
        ) {
            pageContent
        }
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // Post-talk the cover already carries the talk's title — the bar
        // names what this page IS instead. Browsing keeps the title: on a
        // study chapter it's the only place saying which book is open.
        .navigationTitle(postTalk == nil ? session.displayTitle : chrome("Review book"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarMenu }
        .onAppear {
            refresh()
            if selectedChapter == nil { selectedChapter = initialChapter }
        }
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
        .alert("Something went wrong",
               isPresented: Binding(get: { regenerateError != nil },
                                    set: { if !$0 { regenerateError = nil } })) {
            if regenerateOutOfCredits {
                Button("See plans") { regenerateError = nil; showingPaywall = true }
            }
            Button("OK") { regenerateError = nil }
        } message: {
            Text(regenerateError ?? "")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(offerTrial: false)   // out-of-credits entry
        }
        .confirmationDialog("Delete this talk?", isPresented: $showingDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete talk", role: .destructive) {
                appState.deleteSession(id: session.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(explain("The conversation, its score, review cards and audio are removed for good. To keep it but leave it out of your stats, archive it instead."))
        }
    }

    // MARK: - Intro (cover + report)

    /// The intro chapter: cover (title, progress, actions), then the talk's
    /// report — score, coach's note, what carried over from practice.
    @ViewBuilder
    private var introPage: some View {
        coverBlock
        missingSummaryBlock
        if curriculum.isMastered && archivedAt == nil { masteredBanner }
        if let sc = session.summary?.scorecard {
            Divider().padding(.leading, 20)
            scoreBlock(sc)
        }
        if let note = session.summary?.overallNote, !note.isEmpty {
            Divider().padding(.leading, 20).padding(.top, 8)
            groupLabel("Coach's note", icon: "text.bubble")
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        carryoverBlock
    }

    private var coverBlock: some View {
            VStack(alignment: .leading, spacing: 18) {
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
            .padding(20)
    }

    /// The talk is here but its review material never got made — the analysis
    /// call failed when the call ended (network, credits, a reply the token
    /// ceiling cut off) and the raw conversation was saved without it.
    ///
    /// Everything below derives from that summary, so the book is otherwise
    /// empty and the talk is stuck: no drills, no score, nothing folded into
    /// the learner profile. This is the only way back.
    @ViewBuilder
    private var missingSummaryBlock: some View {
        if SessionSummarizer.needsSummary(session) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Review material missing", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(explain("The conversation was saved, but the analysis that turns it into words, corrections and drill cards didn't finish. You can run it now."))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await regenerateSummary() }
                } label: {
                    HStack {
                        if isRegenerating {
                            ProgressView().controlSize(.small)
                            Text("Working…")
                        } else {
                            Label("Generate review material", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRegenerating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private var masteredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Talk mastered").font(.subheadline.weight(.semibold))
                Text(explain("Everything this conversation had to teach is yours."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Archive") { setArchived(true) }
                .buttonStyle(.borderedProminent).tint(.green)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - The bookmarked page

    private struct ChapterEntry {
        let chapter: Chapter
        let title: String
        let icon: String
        var done: Int? = nil
        var total: Int? = nil
        var count: Int? = nil
        var isComplete: Bool {
            guard let done, let total, total > 0 else { return false }
            return done == total
        }
    }

    /// The fluent-self lines the wrap-up offers for fresh shadowing — also
    /// what decides whether the lines chapter exists.
    private var freshShadowLines: [Turn] {
        Array(session.turns.filter { $0.role == .fluentSelf
            && $0.transcript.split(separator: " ").count >= 4 }
            .suffix(4))
    }

    /// Words the learner used for the first time this talk (the win), minus
    /// anything the carryover section already tells.
    private var mineWords: [String] {
        let credited = creditedItems
        return (session.summary?.newWordsUsed ?? [])
            .filter { !credited.contains(CarryoverDetector.normalized($0)) }
    }

    private var usedExpressions: [String] {
        let credited = creditedItems
        return (session.summary?.expressionsUsed ?? [])
            .filter { !credited.contains(CarryoverDetector.normalized($0)) }
    }

    private var studyChapters: [ChapterEntry] {
        // Shadow = repeat the fluent self's lines; Drill = everything about
        // fixing YOUR sentences (corrections to read, smoother versions to
        // score, the card run that locks them in).
        let hasShadow = !freshShadowLines.isEmpty
        let hasDrill = drillCount > 0
            || !(session.summary?.phrasesUsed.isEmpty ?? true)
            || !curriculum.shadowLines.isEmpty

        var entries: [ChapterEntry] = []

        if !mineWords.isEmpty || !curriculum.words.isEmpty {
            // Mastery tracks the future self's words; a talk with only your
            // own first-time words still shows how many there are to look at.
            entries.append(ChapterEntry(chapter: .words, title: chrome("Words"),
                                        icon: "textformat",
                                        done: curriculum.words.filter { $0.masteredAt != nil }.count,
                                        total: curriculum.words.count,
                                        count: mineWords.count))
        }
        if !usedExpressions.isEmpty {
            entries.append(ChapterEntry(chapter: .expressions, title: chrome("Expressions"),
                                        icon: "quote.opening",
                                        count: usedExpressions.count))
        }
        if hasShadow {
            entries.append(ChapterEntry(chapter: .lines, title: chrome("Shadow"),
                                        icon: "waveform.badge.mic",
                                        count: freshShadowLines.count))
        }
        if hasDrill {
            // The smoother-versions mastery is this chapter's progress; the
            // plain card count is the fallback when a talk minted no lines.
            entries.append(ChapterEntry(chapter: .cards, title: chrome("Drill"),
                                        icon: "rectangle.stack",
                                        done: curriculum.shadowLines.filter { $0.masteredAt != nil }.count,
                                        total: curriculum.shadowLines.count,
                                        count: drillCount))
        }
        return entries
    }

    private var allTabs: [BookmarkTab<Chapter>] {
        [BookmarkTab<Chapter>(id: .intro, icon: "book.closed", title: chrome("Overview"))]
            + studyChapters.map {
                BookmarkTab(id: $0.chapter, icon: $0.icon, title: $0.title,
                            done: $0.done, total: $0.total, count: $0.count)
            }
    }

    /// The open chapter: the learner's explicit pick when it still exists,
    /// otherwise the intro (the cover).
    private var activeChapter: Chapter {
        let ids = allTabs.map(\.id)
        if let selectedChapter, ids.contains(selectedChapter) {
            return selectedChapter
        }
        return .intro
    }

    /// The open chapter's page content, scrolled inside the fixed page.
    @ViewBuilder
    private var pageContent: some View {
        switch activeChapter {
        case .intro:
            introPage
        case .words:
            pageTitle(chrome("Words"))
            wordsPage
            pageFooter("Tap a word for its card — meaning, pronunciation, your sentences. It's mastered once you use it in a talk or mark it known.")
        case .expressions:
            pageTitle(chrome("Expressions"))
            expressionsPage
            pageFooter(explain("Expressions you actually used this talk."))
        case .lines:
            pageTitle(chrome("Shadow"))
            shadowPage
            pageFooter(explain("Repeat your fluent self's lines from this talk."))
        case .cards:
            pageTitle(chrome("Drill"))
            drillPage
        }
    }

    private func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func pageFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    /// A small group label inside a page that stacks more than one kind of
    /// material.
    private func groupLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: - Chapter pages

    /// One checklist, same anatomy as the Watch book's words: the future
    /// self's words to master, then the learner's own first-time words as
    /// chips underneath — the win stays visible without its own chapter.
    @ViewBuilder
    private var wordsPage: some View {
        let theirs = curriculum.words
        let keys = theirs.map { VocabStore.lookupKey(for: $0.text) }
        ForEach(theirs) { item in
            Button {
                wordSheet = WordRef(value: VocabStore.lookupKey(for: item.text), siblings: keys)
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
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if item.id != theirs.last?.id {
                Divider().padding(.leading, 44)
            }
        }
        if !mineWords.isEmpty {
            if !theirs.isEmpty { Divider().padding(.leading, 16) }
            Text("Words you used first")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(mineWords, id: \.self) { w in
                    wordChip(w, siblings: mineWords)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        Color.clear.frame(height: 6)
    }

    @ViewBuilder
    private var expressionsPage: some View {
        ForEach(usedExpressions, id: \.self) { e in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.top, 3)
                Text(e).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        Color.clear.frame(height: 8)
    }

    /// The shadow chapter: repeat the fluent self's whole lines from this
    /// talk. Everything about fixing the learner's OWN sentences lives in
    /// the Drill chapter.
    @ViewBuilder
    private var shadowPage: some View {
        ForEach(freshShadowLines) { turn in
            let best = bestShadowScore(for: turn.id)
            Button {
                fluentShadowTurn = turn
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // Same row grammar as every other study list: state up
                    // front, score at the end — not a decorative icon.
                    masteryMark((best ?? 0) >= ScenarioCurriculum.shadowMasteryScore)
                    Text(turn.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let best {
                        Text("\(best)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(best >= ScenarioCurriculum.shadowMasteryScore ? .green : .secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Color.clear.frame(height: 8)
    }

    /// One correction, whichever pipeline it came from (a live turn
    /// suggestion or the summary's phrase feedback): the learner's original,
    /// the fluent version to SAY, why, and where shadow attempts attach.
    private struct CorrectionItem: Identifiable {
        let id: UUID          // stable — shadow attempts + cached TTS attach here
        let original: String?
        let fluent: String
        let reason: String
        /// Curriculum-tracked mastery; summary-only corrections show their
        /// best score instead.
        let masteredAt: Date?
    }

    /// Turn-suggestion lines first (they carry the book's mastery), then any
    /// summary corrections that aren't already the same sentence.
    private var corrections: [CorrectionItem] {
        var items: [CorrectionItem] = []
        var seen = Set<String>()
        for line in curriculum.shadowLines {
            // The line id is its source turn's id with the first byte
            // flipped (`TalkCurriculum.shadowLineId`) — flip it back to find
            // the sentence the correction fixed.
            var bytes = line.id.uuid
            bytes.0 ^= 0xFF
            let turnId = UUID(uuid: bytes)
            let original = session.turns.first { $0.id == turnId }?.transcript
            items.append(CorrectionItem(id: line.id, original: original,
                                        fluent: line.text, reason: line.note,
                                        masteredAt: line.masteredAt))
            seen.insert(CarryoverDetector.normalized(line.text))
        }
        for p in session.summary?.phrasesUsed ?? [] {
            guard seen.insert(CarryoverDetector.normalized(p.fluentAlternative)).inserted
            else { continue }
            items.append(CorrectionItem(id: TalkCurriculum.shadowLineId(for: p.id),
                                        original: p.userSaid,
                                        fluent: p.fluentAlternative,
                                        reason: p.reason,
                                        masteredAt: nil))
        }
        return items
    }

    /// The drill chapter: fixing the learner's OWN sentences, one unit per
    /// correction — read the diff and its reason, TAP to say the fluent
    /// version aloud (scored, \(ScenarioCurriculum.shadowMasteryScore)+
    /// masters it), then run the short capped deck for active recall. The
    /// same fixes come back in future talks as carryover credit.
    @ViewBuilder
    private var drillPage: some View {
        let all = corrections
        if !all.isEmpty {
            groupLabel("Say it better", icon: "sparkles")
            ForEach(all) { item in
                correctionRow(item)
            }
            pageFooter(explain("Each line is the smoother version of something you actually said. Tap one to say the fix out loud — score \(ScenarioCurriculum.shadowMasteryScore)+ and it's yours. The same fixes come back as cards below."))
        }
        if drillCount > 0 {
            Divider().padding(.leading, 20).padding(.top, 12)
            NavigationLink {
                sessionDeck
            } label: {
                Label("Review this talk", systemImage: "rectangle.stack.fill")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            pageFooter(explain("A quick run through this talk's key phrases — anything left joins your review queue in Practice."))
        }
        Color.clear.frame(height: 4)
    }

    private func correctionRow(_ item: CorrectionItem) -> some View {
        let best = bestShadowScore(for: item.id)
        let mastered = item.masteredAt != nil
            || (best ?? 0) >= ScenarioCurriculum.shadowMasteryScore
        return Button {
            // The item id doubles as the synthetic Turn id, so attempts and
            // cached TTS stay attached across opens.
            shadowLine = ScenarioCurriculum.Item(id: item.id, text: item.fluent,
                                                 note: item.reason)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                masteryMark(mastered)
                VStack(alignment: .leading, spacing: 4) {
                    if let original = item.original, !original.isEmpty {
                        Text(original)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(highlightedCorrection(item.fluent,
                                               original: item.original ?? "",
                                               baseFont: .subheadline))
                        .font(.subheadline)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.reason.isEmpty {
                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let best {
                    Text("\(best)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(best >= ScenarioCurriculum.shadowMasteryScore ? .green : .secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session highlights (the analysis screen's core content)

    /// The one thing a learner cannot notice about themselves: material they'd
    /// already been given — a correction card from an earlier talk, a
    /// suggestion a few turns back — that they then produced unprompted.
    ///
    /// Shown as evidence, never as a claim: their own sentence is quoted, and
    /// their own recording is one tap away. Nothing is asserted that the
    /// transcript can't back up.
    /// Normalized text of everything the carryover section already claims —
    /// the sections below filter against it so one fact is told once, in the
    /// place where it means the most.
    private var creditedItems: Set<String> {
        Set((session.summary?.carryovers ?? []).map { CarryoverDetector.normalized($0.item) })
    }

    @ViewBuilder
    private var carryoverBlock: some View {
        let hits = session.summary?.carryovers ?? []
        if !hits.isEmpty {
            groupLabel("You used what you practiced", icon: "target")
            ForEach(hits) {
                CarryoverRow(carryover: $0)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            pageFooter(explain("No prompt, no card on screen — you reached for these yourself. Cards you produce live jump ahead in the review queue."))
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

    /// This session's cards as a swipe deck — shared destination for the
    /// drills rows and the post-talk practice CTA.
    private var sessionDeck: some View {
        DrillView(source: .session(session.id))
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
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
    @ViewBuilder
    private func scoreBlock(_ sc: SessionScorecard) -> some View {
        groupLabel("Score", icon: "chart.bar")
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
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
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

    /// Run the analysis this talk never got. Same engine, same idempotency
    /// key and same downstream ingestion as the end of a live call, so a
    /// rescued talk is indistinguishable from one that worked first time.
    private func regenerateSummary() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            let result = try await SessionSummarizer.summarize(session: session,
                                                              appState: appState)
            session = result.session
            refresh()
            Telemetry.log("talk_summary_regenerated", ["turns": String(session.turns.count)])
        } catch {
            regenerateOutOfCredits = error.isOutOfCredits
            regenerateError = error.localizedDescription
            Telemetry.log("talk_summary_error", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "turns": String(session.turns.count),
                "out_of_credits": error.isOutOfCredits ? "1" : "0",
                "retry": "1",
            ])
        }
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
            return explain("Scored against your \(setting) level setting — this talk itself read as ≈\(read).")
        }
        return explain("Scored against your \(setting) level setting — how this talk went, not a level rating.")
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
                    Text(explain("Highlighted words are worth picking up — tap one to check it out."))
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

// MARK: - Carryover row (studied material, produced live)

/// One "you actually said it" hit. The item on top, the learner's own words
/// underneath as proof, and — when the recording survived — a play button, so
/// the claim is auditable by ear and not just by transcript.
private struct CarryoverRow: View {
    let carryover: Carryover
    @StateObject private var player = AudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Text(carryover.item)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("“\(carryover.quote)”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
            HStack(spacing: 10) {
                // Plain Image+Text, NOT Label — inside a List row a Label
                // aligns to the form's icon column and leaves a wide gap.
                HStack(spacing: 4) {
                    Image(systemName: originIcon)
                    Text(originText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if hasAudio {
                    Spacer(minLength: 8)
                    // Icon only, pinned right. As a caption2 text button it
                    // sat inline with the source label — same size, same
                    // weight — so it read as one more piece of metadata
                    // rather than a control, with a tap target to match. The
                    // "Hear yourself" ↔ "Stop" swap also resized the row
                    // mid-playback.
                    Button {
                        player.isPlaying ? player.stop() : play()
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "Stop" : "Hear yourself")
                }
            }
            .padding(.leading, 26)
        }
        .padding(.vertical, 4)
    }

    private var originText: String { carryover.source.label }
    private var originIcon: String { carryover.source.icon }

    private var hasAudio: Bool {
        TurnAudioStore.shared.url(for: carryover.turnId) != nil
    }

    private func play() {
        guard let data = TurnAudioStore.shared.data(for: carryover.turnId) else { return }
        try? player.play(data, source: "carryover", forceSessionReset: true)
    }
}

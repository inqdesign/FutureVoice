import SwiftUI

/// Practice — "뭘 연습할 건데?"에 바로 답하는 화면. Same structure as
/// Progress: swipeable pages behind a chip tab bar.
///
///   1. Studying  — the FIRST page: every book currently in progress
///                  (started, not yet mastered) across all shelves, plus the
///                  three practice-type shortcuts (Words · Shadowing ·
///                  Expressions). Each shortcut opens its full surface
///                  (notebook / shadow browser / expression list); the user
///                  picks what to practice — nothing is pre-picked for them,
///                  and there is no "due" queue concept here.
///   2. Shelves   — the full review material, split by ACTIVITY: Talk (the
///                  calls you had) · Watch (the scenes you watched). Each
///                  card wears an origin tag (Free talk / News / Scenario)
///                  for its source. Every book is the same anatomy (scene +
///                  words + lines + mastery); master everything and it archives.
///
/// Doing lives on Home (Talk / Watch CTAs); measuring lives in Progress.
struct PracticeTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var vocab = VocabStore.shared

    /// Programmatic push of the vocabulary notebook, driven by the
    /// futurevoice://vocab deep link (study widget tap).
    @State private var showingVocabulary = false
    @State private var showingExpressions = false

    // Shelves — optional because it doubles as the pager's scrollPosition
    // binding (same pattern as Progress).
    @State private var shelf: Shelf? = .studying

    /// Default lands on Studying; the capture harness opens a specific shelf.
    init(initialShelf: Shelf? = .studying) {
        _shelf = State(initialValue: initialShelf)
    }
    @State private var openScenario: Scenario?
    /// Continue widget → a talk book's detail page (watch books use openScenario).
    /// Wrapped because `Session` isn't Hashable; identity/equality ride on the id.
    private struct OpenTalk: Identifiable, Hashable {
        let session: Session
        var id: UUID { session.id }
        static func == (l: OpenTalk, r: OpenTalk) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }
    @State private var openTalkSession: OpenTalk?
    @State private var talkLaunch: Scenario?
    @State private var talks: [Session] = []
    @State private var archivedTalks: [Session] = []
    /// Derived talk-book progress, filled in a follow-up pass (pickup-word
    /// extraction is too heavy for first paint).
    @State private var talkSnapshots: [UUID: TalkCurriculum.Snapshot] = [:]

    enum Shelf: String, CaseIterable, Hashable {
        // Split by ACTIVITY, not source: Talk = the calls you had, Watch = the
        // scenes you watched. Each card carries an origin tag (Free talk /
        // News / Scenario) for the orthogonal source.
        case studying, talk, watch
        var title: String {
            switch self {
            case .studying:  return "Studying"
            case .talk:      return "Talk"
            case .watch:     return "Watch"
            }
        }
        /// Category color for the selected-chip fill; nil = the cross-cutting
        /// Studying page, which keeps the monochrome label fill.
        var color: Color? {
            switch self {
            case .studying:  return nil
            case .talk:      return Books.talkChipColor
            case .watch:     return Books.watchChipColor
            }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            // Same pager as Progress: a native horizontal-paging ScrollView
            // whose pages are real vertical scroll views, so content slides
            // under the chip bar's material and the tab bar.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Shelf.allCases, id: \.self) { s in
                        ScrollView {
                            content(for: s)
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, 36)
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(s)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $shelf)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                shelfChips
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    // One continuous translucent panel from the status bar
                    // down to the chips, feathered at the bottom — identical
                    // to Progress's header treatment.
                    .background {
                        Rectangle().fill(.bar)
                            .mask {
                                LinearGradient(stops: [.init(color: .black, location: 0),
                                                       .init(color: .black, location: 0.82),
                                                       .init(color: .clear, location: 1)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                            .ignoresSafeArea(edges: .top)
                    }
            }
            .background(TransparentRoundedNavBar())
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Practice")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onAppear {
                reload()
                consumePendingRoute()
            }
            .onChange(of: appState.pendingPracticeRoute) { _, _ in
                consumePendingRoute()
            }
            .navigationDestination(isPresented: $showingVocabulary) {
                VocabularyView()
            }
            .navigationDestination(isPresented: $showingExpressions) {
                ExpressionsView()
                    .navigationTitle("Expressions")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $openScenario) { s in
                ScenarioDetailView(scenarioId: s.id)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $openTalkSession) { talk in
                ConversationDetailView(session: talk.session)
                    .environmentObject(appState)
            }
            .fullScreenCover(item: $talkLaunch, onDismiss: reload) { s in
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb)
                    .environmentObject(appState)
            }
        }
    }

    /// Deep link handoff (study widget → vocabulary notebook). The route is
    /// staged in AppState because on a cold launch the URL arrives before
    /// this tab exists — onAppear picks it up; onChange covers warm taps.
    private func consumePendingRoute() {
        // Route only pushes the page; the specific item comes via
        // appState.focusWord/focusPhrase (observed by the page even if it's
        // already on screen).
        switch appState.pendingPracticeRoute {
        case .studying:
            appState.pendingPracticeRoute = nil
            // Progress-widget tap: pop any pushed page and show the Studying shelf.
            showingVocabulary = false
            showingExpressions = false
            withAnimation { shelf = .studying }
        case .vocabulary:
            appState.pendingPracticeRoute = nil
            showingVocabulary = true
        case .expressions:
            appState.pendingPracticeRoute = nil
            showingExpressions = true
        case let .book(kind, id):
            appState.pendingPracticeRoute = nil
            // Land on Studying, then push the requested book's detail page.
            showingVocabulary = false
            showingExpressions = false
            shelf = .studying
            if kind == "watch" {
                openTalkSession = nil
                openScenario = appState.scenarios.first { $0.id == id }
            } else {
                openScenario = nil
                openTalkSession = SessionStore.shared.load()
                    .first { $0.id == id }.map(OpenTalk.init)
            }
        case nil:
            break
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func content(for s: Shelf) -> some View {
        switch s {
        case .studying:
            studyingPage
        case .talk:
            shelfPage { talksShelf }
        case .watch:
            shelfPage {
                scenarioShelf(watchBooks, archived: archivedWatchBooks,
                              emptyText: "Watch a situation or a news story on Home — it becomes a book here: a scene to watch, words and lines to master.")
            }
        }
    }

    private func shelfPage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sub-tab bar (same chip vocabulary as Progress)

    private var shelfChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Shelf.allCases, id: \.self) { s in
                        Button { withAnimation { shelf = s } } label: {
                            // Fitness+-style pills, but the active book chip
                            // fills with its category color (white text works
                            // on all three hues in both appearances);
                            // Studying keeps the monochrome label fill.
                            Text(s.title)
                                .font(.body.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(shelf == s ? (s.color ?? Color(.label)) : Color(.secondarySystemGroupedBackground)))
                                .foregroundStyle(shelf == s ? (s.color != nil ? Color.white : Color(.systemBackground)) : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(s)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            // Keep the active chip in view as you swipe pages or tap.
            .onChange(of: shelf) { _, new in
                if let new {
                    withAnimation { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Studying (first page: in-progress books + practice shortcuts)

    /// One in-progress book of either kind, unified for the studying grid.
    private enum StudyBook: Identifiable {
        case talk(Session)
        case scenario(Scenario)
        var id: UUID {
            switch self {
            case .talk(let s):     return s.id
            case .scenario(let s): return s.id
            }
        }
    }

    /// When this book was last actually studied — the most recent mastery
    /// event; falls back to the book's own creation/use date before any.
    private func lastStudied(_ book: StudyBook) -> Date {
        switch book {
        case .talk(let s):
            return talkSnapshots[s.id]?.lastStudiedAt ?? s.endedAt ?? s.startedAt
        case .scenario(let s):
            let masteryDate = s.curriculum
                .flatMap { ($0.words + $0.expressions + $0.shadowLines).compactMap(\.masteredAt).max() }
            return masteryDate ?? s.lastUsedAt ?? s.createdAt
        }
    }

    /// Started but not yet mastered, across every shelf. "Started" means the
    /// progress bar has actually moved — at least one item mastered. Books at
    /// zero progress stay on their shelf only; mastered and archived books
    /// drop out too. Talks whose snapshot hasn't computed yet are held back
    /// (their progress is unknown) and appear once the second pass fills in.
    private var studyingBooks: [StudyBook] {
        let talkBooks: [StudyBook] = talks
            .filter { s in
                guard let snap = talkSnapshots[s.id] else { return false }
                return snap.masteredCount > 0 && !snap.isMastered
            }
            .map { .talk($0) }
        let scenarioBooks: [StudyBook] = appState.scenarios
            .filter { !$0.isArchived && !$0.isMastered && ($0.curriculum?.masteredCount ?? 0) > 0 }
            .map { .scenario($0) }
        return (talkBooks + scenarioBooks)
            .sorted { lastStudied($0) > lastStudied($1) }
    }

    private var studyingPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            practiceShortcuts
            if studyingBooks.isEmpty {
                shelfHint("Nothing in progress yet. Open a book on a shelf and master your first word or line — it shows up here until the whole book is done.")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(studyingBooks) { book in
                        switch book {
                        case .talk(let session):     talkCard(session, showActivity: true)
                        case .scenario(let s):       scenarioCard(s, showActivity: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var practiceShortcuts: some View {
        HStack(spacing: 10) {
            shortcut(icon: "text.book.closed.fill", title: "Words",
                     count: vocab.studying.count) {
                VocabularyView()
            }
            shortcut(icon: "waveform.badge.mic", title: "Shadowing",
                     count: appState.savedLines.count) {
                ShadowBrowserView()
                    .navigationTitle("Shadowing")
                    .navigationBarTitleDisplayMode(.inline)
            }
            shortcut(icon: "quote.bubble.fill", title: "Expressions",
                     count: vocab.expressionEntries().count) {
                ExpressionsView()
                    .navigationTitle("Expressions")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func shortcut<D: View>(icon: String, title: String, count: Int,
                                   @ViewBuilder destination: () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Books (the shelves)

    /// Every watched book — news topics and built situations together, one
    /// flat shelf per the Talk/Watch split; the card's origin tag names which.
    /// Most-recently-touched first.
    private var watchBooks: [Scenario] {
        appState.scenarios.filter { !$0.isArchived }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }
    private var archivedWatchBooks: [Scenario] {
        appState.scenarios.filter { $0.isArchived }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    /// One talk book card + its navigation and management actions — shared by
    /// the Talks shelf and the Studying grid.
    private func talkCard(_ session: Session, showActivity: Bool = false) -> some View {
        NavigationLink {
            ConversationDetailView(session: session)
                .environmentObject(appState)
        } label: {
            TalkBookCard(session: session, snapshot: talkSnapshots[session.id],
                         showActivity: showActivity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { setTalkArchived(session, true) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                appState.deleteSession(id: session.id)
                reload()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// One scenario/topic book card + actions — shared by the Topics and
    /// Scenarios shelves and the Studying grid.
    private func scenarioCard(_ s: Scenario, showActivity: Bool = false) -> some View {
        ScenarioBookCard(scenario: s, personaName: linkedPersonaName(s), showActivity: showActivity)
            .onTapGesture { openScenario = s }
            .contextMenu {
                Button { openScenario = s } label: { Label("Open", systemImage: "book") }
                Button { talkLaunch = s } label: { Label("Talk now", systemImage: "mic.fill") }
                Button { appState.setScenarioArchived(id: s.id, true) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                Button(role: .destructive) { appState.deleteScenario(id: s.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private var talksShelf: some View {
        if talks.isEmpty && archivedTalks.isEmpty {
            shelfHint("Finish a talk and it lands here as a book — replay it, pick up its words, shadow the smoother versions of your own lines.")
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(talks) { session in
                    talkCard(session)
                }
            }
            if !archivedTalks.isEmpty {
                archiveList(archivedTalks.map { s in
                    ArchiveRowModel(id: s.id,
                                    title: s.displayTitle,
                                    subtitle: (s.endedAt ?? s.startedAt).formatted(date: .abbreviated, time: .omitted),
                                    mastered: talkSnapshots[s.id]?.isMastered == true,
                                    destination: .talk(s),
                                    unarchive: { setTalkArchived(s, false) },
                                    delete: { appState.deleteSession(id: s.id); reload() })
                })
            }
        }
    }

    @ViewBuilder
    private func scenarioShelf(_ books: [Scenario], archived: [Scenario], emptyText: String) -> some View {
        if books.isEmpty && archived.isEmpty {
            shelfHint(emptyText)
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(books) { s in
                    scenarioCard(s)
                }
            }
            if !archived.isEmpty {
                archiveList(archived.map { s in
                    ArchiveRowModel(id: s.id,
                                    title: s.environment,
                                    subtitle: (linkedPersonaName(s)
                                        ?? (s.role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.role))
                                        .map { "with \($0)" } ?? "",
                                    mastered: s.isMastered,
                                    destination: .scenario(s),
                                    unarchive: { appState.setScenarioArchived(id: s.id, false) },
                                    delete: { appState.deleteScenario(id: s.id) })
                })
            }
        }
    }

    private func shelfHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Archive (per shelf)

    private struct ArchiveRowModel: Identifiable {
        enum Destination {
            case talk(Session)
            case scenario(Scenario)
        }
        let id: UUID
        let title: String
        let subtitle: String
        let mastered: Bool
        let destination: Destination
        let unarchive: () -> Void
        let delete: () -> Void
    }

    private func archiveList(_ rows: [ArchiveRowModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archive")
                .font(.headline)
                .padding(.top, 10)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    archiveRow(row)
                    if row.id != rows.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            Text("Finished books. They keep their progress — unarchive anytime.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func archiveRow(_ row: ArchiveRowModel) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: row.mastered ? "checkmark.seal.fill" : "archivebox")
                .font(.body)
                .foregroundStyle(row.mastered ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        Group {
            switch row.destination {
            case .talk(let session):
                NavigationLink {
                    ConversationDetailView(session: session).environmentObject(appState)
                } label: { label }
            case .scenario(let scenario):
                Button { openScenario = scenario } label: { label }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: row.unarchive) {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            Button(role: .destructive, action: row.delete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Data

    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    private func setTalkArchived(_ session: Session, _ flag: Bool) {
        // Via AppState: archived talks leave the score/assessment evidence,
        // which may re-run the latest assessment.
        appState.setSessionArchived(id: session.id, flag)
        reload()
    }

    private func reload() {
        vocab.backfillFromSessions()

        let finished = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        talks = finished.filter { $0.archivedAt == nil }
        archivedTalks = finished.filter { $0.archivedAt != nil }

        // Second pass: derived talk-book progress (pickup-word extraction is
        // too heavy to block first paint with).
        let toSnapshot = finished
        Task { @MainActor in
            var out: [UUID: TalkCurriculum.Snapshot] = [:]
            for s in toSnapshot {
                out[s.id] = TalkCurriculum.build(session: s,
                                                 proficiency: appState.proficiency,
                                                 shadowAttempts: appState.shadowAttempts)
            }
            talkSnapshots = out
        }
    }
}

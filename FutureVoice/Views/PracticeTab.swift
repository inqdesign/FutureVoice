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
    @ObservedObject private var goals = GoalStore.shared
    /// Today's targets come from the routine, so a routine edit redraws the card.
    @ObservedObject private var planStore = StudyPlanStore.shared

    /// Programmatic push of the vocabulary notebook, driven by the
    /// futurevoice://vocab deep link (study widget tap).
    @State private var showingVocabulary = false
    @State private var showingExpressions = false
    @State private var showingShadowBrowser = false
    @State private var showingGoalsEditor = false
    /// The Words challenge session (a dealt hand of recommended words) —
    /// distinct from showingVocabulary, which is the explore cloud.
    @State private var showingDailyWords = false
    /// The Expressions challenge session — same dealt-hand shape.
    @State private var showingDailyExpressions = false
    /// The due-items review (what a review reminder opens), plus the count
    /// that makes it visible without one.
    @State private var showingDueReview = false
    @State private var dueReviewCount = 0
    /// This week's test, as the Today card reports it.
    @State private var showingWeeklyTest = false
    /// The week in progress, and the archive of closed weeks behind it.
    @State private var thisWeek: WeekInProgress?
    @State private var hasPastWeeks = false
    @State private var showingWeekArchive = false
    @State private var hasUnseenWeek = false
    @State private var weekRecapAction: WeekRecapSheet.Action?
    @State private var weeklyTestState: WeeklyTestSchedule.State = .ready
    /// A per-item callback was tapped — open exactly this card. Word/phrase
    /// items ride in a one-card review deck; a sentence opens its drill card.
    @State private var focusedReviewItem: StudyDeckItem?
    /// Wrapped because `sheet(item:)` needs Identifiable and a retroactive
    /// conformance on UUID would leak into every other file.
    private struct DrillCardRef: Identifiable { let id: UUID }
    @State private var focusedDrillCard: DrillCardRef?
    /// The Shadowing challenge session: today's picks, one guided line at a
    /// time (PracticeSessionView) — the full browser stays behind the
    /// shortcuts band.
    ///
    /// Carried by `sheet(item:)`, never by a Bool beside a separate picks
    /// array: an `isPresented` sheet presents the content the modifier was
    /// LAST BUILT with, so setting the picks and the flag in one tap showed a
    /// session with zero lines — which is the "nothing to do" screen — and
    /// only the second tap (after the dismissal re-rendered the modifier) saw
    /// them. The picks travel WITH the presentation.
    private struct ShadowSessionRequest: Identifiable {
        let id = UUID()
        let picks: [PracticeStats.ShadowPick]
    }
    @State private var shadowSession: ShadowSessionRequest?

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
    /// Raised in place of the call when the account can't pay for one.
    @State private var showingPaywall = false
    /// SRS review (rehomed from the home Today card): cards due now + the
    /// review sheet itself.
    @State private var dueDrillCount = 0
    /// Everything put off — the header's number, and the "put off" deck's size.
    @State private var putOffCount = 0
    @State private var libraryStats = LibraryStats()

    struct LibraryStat {
        var checked = 0
        /// Only the word list has a fixed whole; nil elsewhere.
        var total: Int? = nil
    }
    struct LibraryStats {
        var words = LibraryStat()
        var expressions = LibraryStat()
        var sentences = LibraryStat()
        var shadow = LibraryStat()
    }
    /// Sentence cards due now, by the talk they came from — a book's
    /// "to review" count.
    @State private var dueDrillBySession: [UUID: Int] = [:]
    /// A pinned book's chapter button was tapped — its deck, as a sheet.
    @State private var chapterStudy: ChapterStudy?

    private struct ChapterStudy: Identifiable {
        enum Deck {
            case items(title: LocalizedStringKey, [StudyDeckItem])
            case shadow([PracticeStats.ShadowPick])
            case grammar(UUID)
        }
        let id = UUID()
        let deck: Deck
        let scenarioId: UUID?
    }
    @State private var showingDrills = false
    @State private var talks: [Session] = []
    @State private var archivedTalks: [Session] = []
    /// Derived talk-book progress, filled in a follow-up pass (pickup-word
    /// extraction is too heavy for first paint).
    @State private var talkSnapshots: [UUID: TalkCurriculum.Snapshot] = [:]
    @State private var snapshotTask: Task<Void, Never>?

    enum Shelf: String, CaseIterable, Hashable {
        // Split by ACTIVITY, not source: Talk = the calls you had, Watch = the
        // scenes you watched. Each card carries an origin tag (Free talk /
        // News / Scenario) for the orthogonal source.
        case studying, talk, watch, finished
        var title: String {
            switch self {
            // A `String`, so it must go through explain() or it stays English
            // in every app language (see "UI text has ONE language").
            case .studying:  return explain("Studying")
            case .talk:      return explain("Talk")
            case .watch:     return explain("Watch")
            case .finished:  return explain("Finished")
            }
        }
        /// Category color for the selected-chip fill; nil = the cross-cutting
        /// Studying page, which keeps the monochrome label fill.
        var color: Color? {
            switch self {
            case .studying:  return nil
            case .talk:      return Books.talkChipColor
            case .watch:     return Books.watchChipColor
            case .finished:  return .green
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
            // …and the same panel mirrored at the bottom, so a page dissolves
            // into the tab bar the way Talk's and Watch's do. Nested scroll
            // views never get the system's own scroll edge effect.
            .tabBarScrollFeather()
            .background(TransparentRoundedNavBar())
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // The title holds its size (2026-10-03, user report: it shrank
            // to an inline title the moment the list scrolled, for nothing).
            // No system title at all — iOS 26 drew it beside ours whatever we
            // asked — so the bar carries only our own, pinned at the leading
            // edge; a pushed page's back button reads "Back".
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                fixedTitle
                weekToolbar
            }
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
            .navigationDestination(isPresented: $showingShadowBrowser) {
                ShadowBrowserView()
                    .navigationTitle("Shadowing")
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
            .sheet(isPresented: $showingPaywall) { PaywallView(source: "practice") }
            .fullScreenCover(item: $talkLaunch, onDismiss: reload) { s in
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb,
                                 initialOrigin: .scenario, initialScenarioId: s.id)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingDrills, onDismiss: reload) {
                DrillSheet().environmentObject(appState)
            }
            // Today's edit opens the ROUTINE (founder, 2026-10-02): what a
            // day asks for is set in one place.
            .fullScreenCover(isPresented: $showingGoalsEditor, onDismiss: reload) {
                WeeklyPlanEditor()
            }
            // Deck sessions write snoozes ("back in 10 minutes") — honor them
            // with the shared review reminder the moment the sheet closes.
            // This is a contextual foreground moment, so it may also ask for
            // notification permission the first time (same rule as
            // SessionSummarizer's post-session reschedule).
            .sheet(isPresented: $showingDailyWords, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
            }) {
                DailyWordsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingDailyExpressions, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
            }) {
                DailyExpressionsView()
                    .environmentObject(appState)
            }
            // The named card from a per-item callback, on its own.
            .sheet(item: $focusedReviewItem, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule() }
            }) { item in
                DueReviewView(focus: item)
                    .environmentObject(appState)
            }
            .sheet(item: $focusedDrillCard, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule() }
            }) { ref in
                NavigationStack {
                    DrillView(source: .card(ref.id))
                        .navigationTitle("Review")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { focusedDrillCard = nil }
                            }
                        }
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showingDueReview, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
            }) {
                DueReviewView()
                    .environmentObject(appState)
            }
            // A finished test writes snoozes and Leitner moves — same
            // reminder refresh as the decks on the way out.
            .sheet(isPresented: $showingWeeklyTest, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
            }) {
                WeeklyTestView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingWeekArchive, onDismiss: {
                reload()
                guard let action = weekRecapAction else { return }
                weekRecapAction = nil
                switch action {
                case .test: showingWeeklyTest = true
                case .talk: appState.pendingFreeTalk = true
                }
            }) {
                WeekRecapArchiveView { weekRecapAction = $0 }
                    .environmentObject(appState)
            }
            .sheet(item: $shadowSession, onDismiss: reload) { session in
                NavigationStack {
                    PracticeSessionView(shadowPicks: session.picks, includeCards: false)
                        .environmentObject(appState)
                }
            }
            .sheet(item: $chapterStudy, onDismiss: {
                reload()
                Task { await DrillReminder.reschedule() }
            }) { study in
                switch study.deck {
                case let .items(title, items):
                    DueReviewView(hand: items, title: title)
                        .environmentObject(appState)
                case let .shadow(picks):
                    NavigationStack {
                        PracticeSessionView(shadowPicks: picks, includeCards: false)
                            .environmentObject(appState)
                    }
                    .onDisappear {
                        if let id = study.scenarioId { appState.refreshScenarioMastery(id: id) }
                    }
                case let .grammar(sessionId):
                    NavigationStack {
                        DrillView(source: .session(sessionId))
                            .navigationTitle("Grammar")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { chapterStudy = nil }
                                }
                            }
                            .environmentObject(appState)
                    }
                }
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
        case let .reviewItem(kind, value):
            appState.pendingPracticeRoute = nil
            showingVocabulary = false
            showingExpressions = false
            shelf = .studying
            switch kind {
            case "word":       focusedReviewItem = .word(value)
            case "expression": focusedReviewItem = .expression(value)
            case "sentence":   focusedDrillCard = UUID(uuidString: value).map(DrillCardRef.init)
            default:           showingDueReview = true
            }
        case .review:
            // Review reminder tap → straight into the due items. If they were
            // already reviewed elsewhere the deck says so rather than dealing
            // unrelated material.
            appState.pendingPracticeRoute = nil
            showingVocabulary = false
            showingExpressions = false
            shelf = .studying
            showingDueReview = true
        case .weeklyTest:
            appState.pendingPracticeRoute = nil
            showingVocabulary = false
            showingExpressions = false
            shelf = .studying
            showingWeeklyTest = true
        case .weekArchive:
            appState.pendingPracticeRoute = nil
            showingVocabulary = false
            showingExpressions = false
            shelf = .studying
            showingWeekArchive = true
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
        case .finished:
            shelfPage { finishedShelf }
        }
    }

    /// Books with every item mastered, as a shelf of their own (2026-10-03,
    /// user decision — it was a sheet behind a header button). The same
    /// cards as every shelf, most recently finished first.
    @ViewBuilder
    private var finishedShelf: some View {
        let books = finishedBooks
        if books.isEmpty {
            shelfHint(explain("Master every word and line in a book — from a talk or a scene — and it lands here for good."))
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(books) { book in
                    if let session = book.session {
                        talkCard(session)
                    } else if let scenario = book.scenario {
                        scenarioCard(scenario)
                    }
                }
            }
        }
    }

    private func shelfPage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Active (non-archived) book count behind each chip; Studying counts
    /// what its page shows (in-progress + fresh unstarted).
    private func shelfCount(_ s: Shelf) -> Int? {
        switch s {
        case .studying:
            let n = studyingFeed.count
            return n > 0 ? n : nil
        case .talk:
            return talks.isEmpty ? nil : talks.count
        case .watch:
            let n = watchBooks.count
            return n > 0 ? n : nil
        case .finished:
            let n = finishedBooks.count
            return n > 0 ? n : nil
        }
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
                            // Superscript-style count: top-aligned and small,
                            // so the number reads as a badge on the title
                            // instead of a second word at title size.
                            HStack(alignment: .top, spacing: 4) {
                                Text(s.title)
                                    .font(.body.weight(.medium))
                                // How many books live behind this chip, so an
                                // empty-looking page still says the material
                                // exists ("Talk 1 · Watch 1" after a first watch).
                                if let n = shelfCount(s) {
                                    Text("\(n)")
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .opacity(0.55)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            // Neutral for every shelf (2026-10-03): the page keeps
                            // colour for its progress bars alone.
                            .background(Capsule().fill(shelf == s ? Color(.label) : Color(.secondarySystemGroupedBackground)))
                            .foregroundStyle(shelf == s ? Color(.systemBackground) : Color.primary)
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
        return byLastStudied(talkBooks + scenarioBooks)
    }

    /// Sorted newest-studied first, each key computed ONCE. Sorting with
    /// `lastStudied` in the comparator walked every book's items
    /// O(n log n) times per render — the tab-switch stutter.
    private func byLastStudied(_ books: [StudyBook]) -> [StudyBook] {
        books.map { ($0, lastStudied($0)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Fresh material at ZERO progress — the newest books an activity just
    /// minted. Without this a first-ever watch left Studying empty (its book
    /// sat on a shelf the user hadn't found yet), which read as "nothing
    /// happened". Most recent few only; the shelves keep the full list.
    private var unstartedBooks: [StudyBook] {
        let talkBooks: [StudyBook] = talks
            .filter { s in
                guard let snap = talkSnapshots[s.id] else { return false }
                return snap.masteredCount == 0 && snap.totalCount > 0
            }
            .map { .talk($0) }
        let scenarioBooks: [StudyBook] = appState.scenarios
            .filter { !$0.isArchived && ($0.curriculum?.masteredCount ?? 0) == 0 }
            .map { .scenario($0) }
        return Array(byLastStudied(talkBooks + scenarioBooks).prefix(4))
    }

    // MARK: - Finished books (the trophy shelf)

    /// Books where every single item is mastered — Talk and Watch together,
    /// archived or not. Archiving is tidying; THIS is the achievement, and
    /// until now the app computed it and then hid it inside a per-shelf
    /// archive list. Most recently finished first.
    private var finishedBooks: [FinishedBooksSheet.FinishedBook] {
        typealias Row = FinishedBooksSheet.FinishedBook
        let fromTalks: [Row] = (talks + archivedTalks).compactMap { session in
            guard let snap = talkSnapshots[session.id], snap.isMastered else { return nil }
            return Row(
                id: session.id,
                title: session.displayTitle,
                subtitle: explain("Talk"),
                icon: "bubble.left.and.bubble.right.fill",
                itemCount: snap.totalCount,
                finishedAt: snap.lastStudiedAt ?? session.endedAt ?? session.startedAt,
                session: session, scenario: nil)
        }
        let fromScenarios: [Row] = appState.scenarios.compactMap { scenario in
            guard scenario.isMastered, let c = scenario.curriculum else { return nil }
            let finished = (c.words + c.expressions + c.shadowLines).compactMap(\.masteredAt).max()
            return Row(
                id: scenario.id,
                title: scenario.environment,
                subtitle: linkedPersonaName(scenario).map { "Scene · with \($0)" } ?? "Scene",
                icon: "film.fill",
                itemCount: c.totalCount,
                finishedAt: finished ?? scenario.lastUsedAt ?? scenario.createdAt,
                session: nil, scenario: scenario)
        }
        return (fromTalks + fromScenarios).sorted { $0.finishedAt > $1.finishedAt }
    }

    // MARK: - The week (header)

    /// The week in progress and every closed week behind it — one door to
    /// the archive. Dot while a closed week hasn't been opened yet.
    private var showsWeekArchive: Bool {
        guard let week = thisWeek else { return false }
        return week.hasActivity || hasPastWeeks
    }

    /// A weekday in the APP language — `formatted()` alone follows the phone's.
    static func weekdayName(_ date: Date, _ width: Date.FormatStyle.Symbol.Weekday) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: UILanguage.chromeLanguage)).weekday(width))
    }

    @ToolbarContentBuilder
    private var fixedTitle: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { titleText }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { titleText }
        }
    }

    private var titleText: some View {
        Text("Review")
            .geistPixel(34)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    /// The week's things live in the page HEADER (2026-10-03, user decision):
    /// they are the week's, not today's, and the page below is the books.
    /// Each is an icon with at most a short value beside it.
    @ToolbarContentBuilder
    private var weekToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // No numbers in the header (user decision, 2026-10-03): they took
            // room and said little. A dot says "something here now".
            // Put off = a stack of cards; the week's report = a calendar.
            Button { showingDueReview = true } label: {
                headerIcon("rectangle.stack", dot: dueReviewCount > 0 ? .orange : nil)
            }
            .accessibilityLabel(Text("Back from earlier"))
            .accessibilityValue(Text("\(putOffCount)"))
            .accessibilityIdentifier("practice.dueReview")
            .tint(Color(.label))

            if showsWeekArchive {
                Button {
                    weekRecapAction = nil
                    showingWeekArchive = true
                } label: {
                    headerIcon("calendar", dot: hasUnseenWeek ? .accentColor : nil)
                }
                .accessibilityLabel(Text("Your week"))
                .accessibilityIdentifier("practice.weekRecap")
                .tint(Color(.label))
            }
        }
        // The test on its own, at the far right — a different kind of thing
        // from the two lists beside it.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            // The weekly test is its host's face — the same eyes the test
            // itself is run by, so the door looks like who is behind it.
            Button { showingWeeklyTest = true } label: {
                WeeklyTestCharacter(mood: .waiting, since: .distantPast, tile: Color(.tertiarySystemFill))
                    .scaleEffect(32 / WeeklyTestCharacter.size)
                    .frame(width: 32, height: 32)
                    .overlay(alignment: .topTrailing) {
                        if weeklyTestNeedsYou { headerDot(.accentColor) }
                    }
            }
            .accessibilityLabel(Text("Weekly test"))
            .accessibilityValue(Text(weeklyTestValue.text))
            .accessibilityIdentifier("practice.weeklyTest")
        }
    }

    /// The test is waiting on the learner: open and not started, or started
    /// and not finished.
    private var weeklyTestNeedsYou: Bool {
        switch weeklyTestState {
        case .ready, .inProgress: return true
        case .done, .thin: return false
        }
    }

    private func headerIcon(_ name: String, dot: Color?) -> some View {
        Image(systemName: name)
            .foregroundStyle(.primary)
            .overlay(alignment: .topTrailing) {
                if let dot { headerDot(dot) }
            }
    }

    private func headerDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7).offset(x: 3, y: -2)
    }

    private var weeklyTestValue: (text: String, tint: Color?) {
        switch weeklyTestState {
        case .ready: return (explain("Start"), .accentColor)
        case let .inProgress(test): return ("\(test.answers.count)/\(test.total)", .accentColor)
        case let .done(test, _): return ("\(test.score)/\(test.total)", .primary)
        case let .thin(next): return (explain("Next one \(Self.weekdayName(next, .abbreviated))"), nil)
        }
    }

    /// When a book came into existence. The one ordering the whole tab now
    /// uses — see `bookRows`.
    private func created(_ book: StudyBook) -> Date {
        switch book {
        case .talk(let s):     return s.startedAt
        case .scenario(let s): return s.createdAt
        }
    }

    /// The Studying page, book-first (2026-10-03, user decision): every
    /// unfinished book, newest first, each with its four chapter buttons; the
    /// four lists at the end as an index. (Pinning was tried the same day and
    /// dropped — "pinned book" read oddly, and newest-first already puts the
    /// book being studied on top.)
    /// What used to be the Today card is gone — its numbers belong to the
    /// routine, and its piles are chapters of these books.
    private var studyingPage: some View {
        let books = studyingFeed
        return LazyVStack(alignment: .leading, spacing: 12) {
            // The four lists FIRST, each saying how much of it is checked
            // off (2026-10-03, user decision: an index at the bottom of a
            // long feed was nowhere).
            libraryList
                .padding(.bottom, 8)
            ForEach(books) { book in
                // The shelf's own card, with its chapter buttons under it on
                // the same ground.
                VStack(spacing: 0) {
                    bookCard(book)
                    BookChapterButtons(book: book) { chapter in study(chapter, of: book) }
                }
                .background(RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground)))
            }
            if books.isEmpty {
                shelfHint("Nothing here yet. Have a talk or watch a scene on Home — the material it generates becomes books here; open one and master your first word or line.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bookCard(_ book: BookPreview) -> some View {
        switch book.source {
        case .talk(let s): talkCard(s, showActivity: true, showsProgress: false)
        case .scenario(let sc): scenarioCard(sc, showActivity: true, showsProgress: false)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 2)
    }

    /// Every unfinished, unarchived book, newest first by when it was MADE —
    /// the order never shifts as items are mastered.
    private var studyingFeed: [BookPreview] {
        let due = ReviewQueue.dueItems().reduce(into: Set<String>()) {
            $0.insert($1.text.lowercased())
        }
        let talkBooks: [BookPreview] = talks.compactMap { s in
            let snap = talkSnapshots[s.id]
            if snap?.isMastered == true { return nil }
            let chapters: [BookPreview.Chapter] = snap.map { [
                .init(kind: .words, title: "Words", icon: StudyIcon.words, items: $0.words),
                .init(kind: .expressions, title: "Expressions", icon: StudyIcon.expressions, items: $0.expressions),
                .init(kind: .grammar, title: "Grammar", icon: StudyIcon.grammar, items: $0.corrections),
                .init(kind: .shadow, title: "Shadowing", icon: StudyIcon.shadowing, items: $0.shadowLines),
            ] } ?? []
            let dueHere = (dueDrillBySession[s.id] ?? 0)
                + chapters.filter { $0.kind == .words || $0.kind == .expressions }
                    .flatMap(\.items).filter { due.contains($0.text.lowercased()) }.count
            return BookPreview(id: s.id, source: .talk(s), title: s.displayTitle,
                               created: s.startedAt,
                               tint: Books.talksColor, chapters: chapters, due: dueHere)
        }
        let sceneBooks: [BookPreview] = appState.scenarios.compactMap { sc in
            guard !sc.isArchived, !sc.isMastered else { return nil }
            let c = sc.curriculum
            let chapters: [BookPreview.Chapter] = c.map { [
                .init(kind: .words, title: "Words", icon: StudyIcon.words, items: $0.words),
                .init(kind: .expressions, title: "Expressions", icon: StudyIcon.expressions, items: $0.expressions),
                .init(kind: .grammar, title: "Grammar", icon: StudyIcon.grammar, items: []),
                .init(kind: .shadow, title: "Shadowing", icon: StudyIcon.shadowing, items: $0.shadowLines),
            ] } ?? []
            let dueHere = chapters.filter { $0.kind != .shadow }
                .flatMap(\.items).filter { due.contains($0.text.lowercased()) }.count
            return BookPreview(id: sc.id, source: .scenario(sc), title: sc.environment,
                               created: sc.createdAt,
                               tint: Books.color(for: sc), chapters: chapters, due: dueHere)
        }
        return (talkBooks + sceneBooks).sorted { $0.created > $1.created }
    }

    /// One chapter of one book, as its deck: words and expressions as the
    /// study deck (what's still open, else the whole chapter), shadow lines
    /// as a shadowing session, a talk's corrections as its sentence cards.
    private func study(_ chapter: BookPreview.Chapter, of book: BookPreview) {
        let open = chapter.items.filter { $0.masteredAt == nil }
        let items = open.isEmpty ? chapter.items : open
        var scenarioId: UUID?
        var session: Session?
        switch book.source {
        case .talk(let s): session = s
        case .scenario(let sc): scenarioId = sc.id
        }
        let deck: ChapterStudy.Deck
        switch chapter.kind {
        case .words:
            deck = .items(title: "Words", items.map { StudyDeckItem.word($0.text) })
        case .expressions:
            deck = .items(title: "Expressions", items.map { StudyDeckItem.expression($0.text) })
        case .shadow:
            // The talk's own turn where there is one (its audio and
            // attempts are attached to it); a scene line becomes a synthetic
            // turn under the item's id, the way the scene page does it.
            deck = .shadow(items.map { item in
                let turn = session?.turns.first { $0.id == item.id }
                    ?? Turn(id: item.id, role: .fluentSelf, audioURL: nil,
                            transcript: item.text, durationMs: 0,
                            timestamp: Date(), suggestion: nil)
                return PracticeStats.ShadowPick(turn: turn, reason: item.note)
            })
        case .grammar:
            guard let session else { return }
            deck = .grammar(session.id)
        }
        chapterStudy = ChapterStudy(deck: deck, scenarioId: scenarioId)
    }

    /// The four lists, as an index at the end of the page: the way to look
    /// something up, not the way to study.
    private var libraryList: some View {
        HStack(spacing: 0) {
            libraryTile(StudyIcon.words, "Words", libraryStats.words) {
                WordsView().environmentObject(appState)
            }
            libraryTile(StudyIcon.expressions, "Expressions", libraryStats.expressions) {
                ExpressionsView()
                    .navigationTitle("Expressions")
                    .navigationBarTitleDisplayMode(.inline)
                    .environmentObject(appState)
            }
            libraryTile(StudyIcon.grammar, "Sentences", libraryStats.sentences) {
                SentencesView()
                    .navigationTitle("Sentences")
                    .navigationBarTitleDisplayMode(.inline)
                    .environmentObject(appState)
            }
            libraryTile(StudyIcon.shadowing, "Shadowing", libraryStats.shadow) {
                ShadowBrowserView()
                    .navigationTitle("Shadowing")
                    .navigationBarTitleDisplayMode(.inline)
                    .environmentObject(appState)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// Grouped in the APP language — `formatted()` follows the phone's
    /// region, which printed "8.424" on a Korean screen.
    private static var appNumber: IntegerFormatStyle<Int> {
        .number.locale(Locale(identifier: UILanguage.chromeLanguage))
    }

    /// One list: icon, how much of it has been studied, its name (user
    /// layout, 2026-10-03). No bars: only words have a fixed whole.
    private func libraryTile<D: View>(_ icon: String, _ title: LocalizedStringKey,
                                      _ stat: LibraryStat,
                                      @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(height: 24)
                Text(stat.checked.formatted(Self.appNumber))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("practice.library.\(icon)")
    }

    // MARK: - Books (the shelves)

    /// Every watched book — news topics and built situations together, one
    /// flat shelf per the Talk/Watch split; the card's origin tag names which.
    /// Most-recently-touched first.
    /// Newest book first — by when it was MADE, not when it was last opened.
    /// Sorting by `lastUsedAt` meant replaying a months-old scene shuffled it
    /// back to the top, so the thing you just created wasn't where you left
    /// it. Recency-of-use is what the Studying page sorts by; a shelf is a
    /// shelf, and new things go on the front of it.
    private var watchBooks: [Scenario] {
        appState.scenarios.filter { !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var archivedWatchBooks: [Scenario] {
        appState.scenarios.filter { $0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// One talk book card + its navigation and management actions — shared by
    /// the Talks shelf and the Studying grid.
    private func talkCard(_ session: Session, showActivity: Bool = false,
                          showsProgress: Bool = true) -> some View {
        NavigationLink {
            ConversationDetailView(session: session)
                .environmentObject(appState)
        } label: {
            TalkBookCard(session: session, snapshot: talkSnapshots[session.id],
                         showActivity: showActivity, showsProgress: showsProgress)
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
    private func scenarioCard(_ s: Scenario, showActivity: Bool = false,
                              showsProgress: Bool = true) -> some View {
        ScenarioBookCard(scenario: s, personaName: linkedPersonaName(s), showActivity: showActivity,
                         showsProgress: showsProgress)
            .onTapGesture { openScenario = s }
            .contextMenu {
                Button { openScenario = s } label: { Label("Open", systemImage: "book") }
                Button {
                    BillingGate.start(orShow: $showingPaywall) { talkLaunch = s }
                } label: { Label("Talk now", systemImage: "mic.fill") }
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
            Text(explain("Finished books. They keep their progress — unarchive anytime."))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func archiveRow(_ row: ArchiveRowModel) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: row.mastered ? "checkmark.seal.fill" : "archivebox")
                .font(.body)
                .foregroundStyle(.secondary)
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
        let tests = WeeklyTestStore.shared.load()
        weeklyTestState = WeeklyTestSettings.shared.schedule.state(
            tests: tests, settings: WeeklyTestSettings.shared)
        _ = WeekRecapStore.shared.lastWeek()   // freezes the closed week
        thisWeek = WeekRecapBuilder.thisWeek()
        let pastWeeks = WeekRecapStore.shared.archive()
        hasPastWeeks = !pastWeeks.isEmpty
        hasUnseenWeek = pastWeeks.contains { $0.hasActivity && !WeekRecapStore.shared.wasShown($0) }
        vocab.backfillFromSessions()
        let cards = DrillStore.shared.load()
        dueDrillCount = cards.filter { $0.nextReviewAt <= Date() }.count
        dueDrillBySession = cards.reduce(into: [:]) { acc, card in
            guard card.nextReviewAt <= Date(), card.box < DrillStore.maxBox,
                  let id = card.sourceSessionId else { return }
            acc[id, default: 0] += 1
        }
        dueReviewCount = DueReviewView.dueDeck().count
            + DrillStore.putOffCards().filter { $0.nextReviewAt <= Date() }.count
        putOffCount = DueReviewView.putOffDeck().count
        // Same rule as the Watch shelf: newest talk first, by when it was
        // STARTED. `endedAt` moves when a talk is continued, which pushed old
        // conversations back to the top of the shelf.
        let finished = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        talks = finished.filter { $0.archivedAt == nil }
        archivedTalks = finished.filter { $0.archivedAt != nil }

        // How much has been STUDIED, per list (2026-10-03, user decision:
        // a bar only means something where there is a fixed whole, and only
        // the word list has one). Words: known or said, of the whole graded
        // list. Expressions: known or said. Sentences: cards reviewed at
        // least once. Shadowing: takes recorded.
        var stats = LibraryStats()
        let pool = CoreVocabulary.set
        stats.words = LibraryStat(checked: vocab.records.keys.filter { pool.contains($0.lowercased()) }.count,
                                  total: CoreVocabulary.total)
        let expressions = ExpressionCatalog.all(scenarios: appState.scenarios, store: vocab)
        stats.expressions = LibraryStat(checked: expressions.filter { vocab.hasUsedExpression($0.text) }.count)
        stats.sentences = LibraryStat(checked: cards.filter { $0.timesSeen > 0 }.count)
        stats.shadow = LibraryStat(checked: appState.shadowAttempts.count)
        libraryStats = stats

        // Second pass: derived talk-book progress (pickup-word extraction is
        // too heavy to block first paint with).
        // It hands the main thread back after every book: held in one piece
        // it was the stutter on the FIRST switch to this tab (the tagger is
        // cold then, ~17 ms a book), landing mid tab transition. A newer
        // reload cancels the pass it replaces.
        let toSnapshot = finished
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor in
            var out: [UUID: TalkCurriculum.Snapshot] = [:]
            let drillCards = DrillStore.shared.load()
            for s in toSnapshot {
                out[s.id] = TalkCurriculum.build(session: s,
                                                 proficiency: appState.proficiency,
                                                 shadowAttempts: appState.shadowAttempts,
                                                 drillCards: drillCards)
                await Task.yield()
                if Task.isCancelled { return }
            }
            talkSnapshots = out
        }
    }
}

// MARK: - Finished books shelf

/// Every book the learner took all the way to mastered — the app's only
/// surface that is purely a record of things completed.
///
/// Deliberately NOT the archive: archiving is filing something away, which
/// can mean "I gave up on this". A book lands here only when every word and
/// line in it is mastered, so the count can't be inflated by tidying.
struct FinishedBooksSheet: View {   // internal: DebugCaptureHarness renders it
    let books: [FinishedBook]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Mirrors `PracticeTab.FinishedBook` — the sheet takes prepared rows so
    /// it never has to know how Talk and Watch books compute mastery.
    struct FinishedBook: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let icon: String
        let itemCount: Int
        let finishedAt: Date
        let session: Session?
        let scenario: Scenario?
    }

    private var itemsMastered: Int { books.reduce(0) { $0 + $1.itemCount } }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(books.count)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(books.count == 1 ? "book finished" : "books finished")
                            .font(.headline)
                        Text("\(itemsMastered) words and lines mastered inside them")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                ForEach(books) { book in
                    NavigationLink {
                        destination(for: book)
                    } label: {
                        row(book)
                    }
                }
            } footer: {
                Text(explain("A book lands here once every word and line in it is mastered. Nothing you file away counts — only what you finished."))
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ book: FinishedBook) -> some View {
        HStack(spacing: 12) {
            Image(systemName: book.icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text("\(book.subtitle) · \(book.itemCount) mastered · \(book.finishedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func destination(for book: FinishedBook) -> some View {
        if let session = book.session {
            ConversationDetailView(session: session).environmentObject(appState)
        } else if let scenario = book.scenario {
            ScenarioDetailView(scenarioId: scenario.id).environmentObject(appState)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Nothing finished yet")
                .font(.headline)
            Text(explain("Master every word and line in a book — from a talk or a scene — and it lands here for good."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}


/// The weekly test's day, time, reminder and sounds — one Form section, in
/// the goals sheet because that is where the Practice tab's own settings
/// live. The day is the learner's: the default is Saturday, when a week can
/// be looked back on, and nothing here is synced (two devices must not ring).
struct WeeklyTestSettingsSection: View {
    @ObservedObject private var settings = WeeklyTestSettings.shared
    @Binding var notifications: ReviewNotifications.Status?

    private var weekdays: [(Int, String)] {
        var cal = Calendar.current
        cal.locale = Locale(identifier: UILanguage.chromeLanguage)   // the app language, not the phone's
        let symbols = cal.weekdaySymbols   // Sunday first
        return (1...7).map { ($0, symbols[$0 - 1]) }
    }

    var body: some View {
        Section {
            Picker(selection: $settings.weekday) {
                ForEach(weekdays, id: \.0) { day in
                    Text(day.1).tag(day.0)
                }
            } label: {
                Label("Test day", systemImage: "checklist")
            }
            DatePicker(selection: Binding(
                get: { settings.timeOfDay },
                set: { settings.timeOfDay = $0 }
            ), displayedComponents: .hourAndMinute) {
                Label("Opens at", systemImage: "clock")
            }
            Toggle(isOn: Binding(
                get: { settings.reminderOn },
                set: { on in Task { await setReminder(on) } }
            )) {
                Label("Remind me", systemImage: "bell")
            }
            Toggle(isOn: $settings.soundsOn) {
                Label("Sounds", systemImage: "speaker.wave.2")
            }
        } header: {
            Text("Weekly test")
        } footer: {
            Text(explain("One test a week from your talks, words and corrections. It opens on this day and waits until the next one."))
        }
        .onChange(of: settings.weekday) { _, _ in Task { await WeeklyTestReminder.reschedule() } }
        .onChange(of: settings.hour) { _, _ in Task { await WeeklyTestReminder.reschedule() } }
        .onChange(of: settings.minute) { _, _ in Task { await WeeklyTestReminder.reschedule() } }
    }

    /// Turning the reminder on asks for notification permission if it has
    /// never been asked; a denial leaves the toggle off rather than lying.
    private func setReminder(_ on: Bool) async {
        guard on else {
            settings.reminderOn = false
            await WeeklyTestReminder.reschedule()
            return
        }
        let status = await ReviewNotifications.request()
        notifications = status
        settings.reminderOn = status.canRing
        await WeeklyTestReminder.reschedule()
    }
}

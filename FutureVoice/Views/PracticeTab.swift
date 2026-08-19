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
    /// Expressions not yet marked known — same "to study" meaning as the
    /// other tiles.
    @State private var expressionsToStudy = 0
    /// Notebook words plus the words your Watch books are still asking for.
    /// The tile used to count `studying` alone, so a book could hand you eight
    /// words, the daily deck could deal them, and this number never moved.
    @State private var wordsToStudy = 0
    /// Fluent-self lines never shadowed yet. This is what the shadow browser
    /// actually lists under its default lens; the tile used to show
    /// `savedLines.count` — manual bookmarks, normally 0, whose only
    /// affordances live INSIDE that browser — so the number and the screen it
    /// opened were counting different things.
    @State private var shadowToStudy = 0
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
    /// Sentence cards not yet learned (box < maxBox) — the Sentences tile's
    /// "to study" count. The raw card total counted cards the learner has
    /// already retired, which is why 500+ showed up next to a goal of 20.
    @State private var sentencesToStudy = 0
    @State private var showingDrills = false
    @State private var showingFinished = false
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
    /// The Today card's 2×2 of category tiles.
    private let tileColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

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
            .navigationTitle("Practice")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { finishedShelfButton }
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
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .fullScreenCover(item: $talkLaunch, onDismiss: reload) { s in
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb,
                                 initialOrigin: .scenario, initialScenarioId: s.id)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingDrills, onDismiss: reload) {
                DrillSheet().environmentObject(appState)
            }
            .sheet(isPresented: $showingGoalsEditor) {
                StudyGoalsSheet()
                    .presentationDetents([.medium])
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
            .sheet(item: $shadowSession, onDismiss: reload) { session in
                NavigationStack {
                    PracticeSessionView(shadowPicks: session.picks, includeCards: false)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showingFinished, onDismiss: reload) {
                FinishedBooksSheet(books: finishedBooks)
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

    /// Active (non-archived) book count behind each chip; Studying counts
    /// what its page shows (in-progress + fresh unstarted).
    private func shelfCount(_ s: Shelf) -> Int? {
        switch s {
        case .studying:
            let n = studyingBooks.count + unstartedBooks.count
            return n > 0 ? n : nil
        case .talk:
            return talks.isEmpty ? nil : talks.count
        case .watch:
            let n = watchBooks.count
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
        return Array((talkBooks + scenarioBooks)
            .sorted { lastStudied($0) > lastStudied($1) }
            .prefix(4))
    }

    /// The count is the point — it's a running tally of books you finished, so
    /// it belongs in the chrome where it's visible from every shelf, not
    /// buried at the bottom of one. Shown even at zero: an empty trophy shelf
    /// that tells you how to earn the first one beats a button that only
    /// appears once you no longer need the explanation.
    @ToolbarContentBuilder
    private var finishedShelfButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let count = finishedBooks.count
            Button {
                showingFinished = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: count > 0 ? "checkmark.seal.fill" : "checkmark.seal")
                    if count > 0 {
                        Text("\(count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
                .foregroundStyle(count > 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            }
            .accessibilityLabel(count == 1 ? "1 book finished" : "\(count) books finished")
        }
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
                subtitle: "Talk",
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

    // MARK: - Today (daily challenges)

    /// Reps logged so far today, read fresh on every render — the log is a
    /// dictionary lookup, and each rep's write path already re-renders this
    /// view (vocab is observed, shadow attempts publish through appState, the
    /// drill sheet reloads on dismiss).
    private var todayLog: PracticeLog.Day {
        PracticeLog.shared.day(Date()) ?? PracticeLog.Day()
    }

    /// The daily challenges: a bounded plan for today instead of an unbounded
    /// pile. One row per enabled goal (words / expressions / shadowing, set in
    /// `GoalStore`) plus the due SRS deck, then the week strip that those
    /// finished days accumulate into. The books below stay the supply; this
    /// card is the ask.
    private var todayCard: some View {
        let today = todayLog
        let streak = goals.streak()
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Today").font(.headline)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)").monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(streak) day streak")
                }
                Button { showingGoalsEditor = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Edit daily goals")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Items whose snooze ran out — the same thing a review reminder
            // opens, visible without one. Above the goals because it's a
            // promise the learner already made ("show me this again"), not a
            // target the app set; hidden when nothing is waiting.
            if dueReviewCount > 0 {
                dueReviewRow
            }

            // The four categories as a 2×2 grid. Stacked full-width rows made
            // the card tall and gave each bar more room than a bar deserves;
            // a tile carries the same numbers in half the height, and its
            // second dimension is what lets "today" and "all" each have their
            // own tap target without an invented split control.
            LazyVGrid(columns: tileColumns, spacing: 10) {
                // Sentences is the only conditional one: it's a moving target
                // (clear today's deck, capped at DrillView.sessionCap so a
                // 400-card backlog asks for 20), and on a day with nothing due
                // and nothing done there's nothing to ask for.
                if goals.sentencesPerDay > 0, dueDrillCount > 0 || today.drillDone > 0 {
                    // The learner's goal, but never more than exists to do —
                    // asking for 20 when 3 cards are due makes the day
                    // unwinnable through no fault of theirs.
                    let cardsGoal = max(today.drillDone,
                                        min(today.drillDone + dueDrillCount, goals.sentencesPerDay))
                    challengeTile(icon: "rectangle.stack", title: "Sentences",
                                  done: today.drillDone, goal: cardsGoal,
                                  allCount: sentencesToStudy,
                                  all: {
                                      SentencesView()
                                          .navigationTitle("Sentences")
                                          .navigationBarTitleDisplayMode(.inline)
                                          .environmentObject(appState)
                                  }) {
                        showingDrills = true
                    }
                }
                if goals.wordsPerDay > 0 {
                    // Lands in the dealt-hand session, not the explore cloud —
                    // a challenge hands you today's ten, it doesn't open a map.
                    // "To study" lands in the LIST the number counts, not the
                    // CEFR cloud — the cloud is one row inside it now. See
                    // WordsView for why.
                    challengeTile(icon: "text.book.closed.fill", title: "Words",
                                  done: today.wordDone, goal: goals.wordsPerDay,
                                  allCount: wordsToStudy,
                                  all: { WordsView().environmentObject(appState) }) {
                        showingDailyWords = true
                    }
                }
                if goals.expressionsPerDay > 0 {
                    challengeTile(icon: "quote.bubble.fill", title: "Expressions",
                                  done: today.expressionDone, goal: goals.expressionsPerDay,
                                  allCount: expressionsToStudy,
                                  all: {
                                      ExpressionsView()
                                          .navigationTitle("Expressions")
                                          .navigationBarTitleDisplayMode(.inline)
                                          .environmentObject(appState)
                                  }) {
                        showingDailyExpressions = true
                    }
                }
                if goals.shadowsPerDay > 0 {
                    // Today's PICKS, not the full browser — the same dealt-hand
                    // rule as Words and Expressions. Falls back to the browser
                    // only when there's nothing to pick from yet.
                    challengeTile(icon: "waveform.badge.mic", title: "Shadowing",
                                  done: today.shadowDone, goal: goals.shadowsPerDay,
                                  allCount: shadowToStudy,
                                  all: {
                                      ShadowBrowserView()
                                          .navigationTitle("Shadowing")
                                          .navigationBarTitleDisplayMode(.inline)
                                          .environmentObject(appState)
                                  }) {
                        let picks = PracticeStats.shadowPicks(
                            sessions: talks + archivedTalks,
                            attempts: appState.shadowAttempts,
                            level: appState.proficiency,
                            limit: max(goals.shadowsPerDay, 1))
                        if picks.isEmpty {
                            showingShadowBrowser = true
                        } else {
                            shadowSession = ShadowSessionRequest(picks: picks)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if goals.anyEnabled {
                weekStrip
            } else {
                Button { showingGoalsEditor = true } label: {
                    Text(explain("No daily goals set — tap to pick how many words, expressions and shadow takes make a day."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// "You asked to see these again" — words and expressions whose snooze
    /// has run out. No progress bar: this isn't a goal with a target, it's a
    /// pile that empties as you clear it.
    private var dueReviewRow: some View {
        Button { showingDueReview = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back from earlier")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(explain("You asked to see these again"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(dueReviewCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One category as a TILE: today's ask on top, the whole collection at the
    /// bottom, each its own tap target.
    ///
    /// Rows didn't survive contact with two destinations — side by side in a
    /// 44pt row they needed an invented split control, and the inventory
    /// count ended up louder than the ask. A tile has a second dimension, so
    /// the two live in the natural places (what to do now above, what you
    /// have below) separated by the same hairline every card uses.
    private func challengeTile<D: View>(
        icon: String, title: LocalizedStringKey,
        done: Int, goal: Int,
        allCount: Int,
        @ViewBuilder all: () -> D,
        action: @escaping () -> Void
    ) -> some View {
        let complete = done >= goal
        return VStack(spacing: 0) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.footnote)
                            .foregroundStyle(complete ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(done)/\(goal)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        if complete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.green)
                        }
                        Spacer(minLength: 0)
                    }
                    // Slim by design: the fraction above already carries the
                    // number, so the bar only has to be glanceable.
                    ProgressView(value: Double(min(done, goal)), total: Double(max(goal, 1)))
                        .tint(complete ? .green : .accentColor)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                }
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            CardDivider(inset: 10)

            NavigationLink { all() } label: {
                HStack(spacing: 4) {
                    // Every tile's number means the SAME thing: how many are
                    // still to study. They used to be all-cards / bookmarked-
                    // words / all-expressions / saved-lines under one "All"
                    // label — four meanings, one word, no way to tell.
                    Text("To study")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(allCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(allCount == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.secondary))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("practice.all.\(icon)")
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill)))
    }

    /// The last seven days, today last — a filled check for each day every
    /// enabled challenge was met. What the streak is made of, made visible.
    private var weekStrip: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<7).reversed()
            .compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let met = goals.met(on: d)
                let isToday = cal.isDateInToday(d)
                VStack(spacing: 5) {
                    Text(d, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(isToday ? .primary : .secondary)
                    Image(systemName: met ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(met ? AnyShapeStyle(Color.green)
                                             : (isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// When a book came into existence. The one ordering the whole tab now
    /// uses — see `talkRow`.
    private func created(_ book: StudyBook) -> Date {
        switch book {
        case .talk(let s):     return s.startedAt
        case .scenario(let s): return s.createdAt
        }
    }

    /// The books this page carries, split BY ACTIVITY into one horizontal row
    /// each (a single flat mixed grid read as a pile).
    ///
    /// Ordered NEWEST FIRST, by when the book was made. These rows used to be
    /// `studyingBooks + unstartedBooks` — every in-progress book, then every
    /// untouched one — so the talk you just finished sat behind books you'd
    /// started weeks ago, and the row's order changed every time you mastered
    /// a word somewhere else. Progress belongs on the cards (each one wears
    /// its own bar); the row's job is just "here's your stuff, newest first".
    private var talkRow: [Session] {
        (studyingBooks + unstartedBooks)
            .sorted { created($0) > created($1) }
            .compactMap {
                if case .talk(let s) = $0 { return s } else { return nil }
            }
    }
    private var watchRow: [Scenario] {
        (studyingBooks + unstartedBooks)
            .sorted { created($0) > created($1) }
            .compactMap {
                if case .scenario(let s) = $0 { return s } else { return nil }
            }
    }

    private var studyingPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ONE card: today's work, the week it adds up to, and the way into
            // the library. Whole-library mastery moved to Progress — "how far
            // along am I" is that tab's question, and mixing it in here was
            // the other half of what made this page hard to read.
            todayCard
            if !talkRow.isEmpty {
                bookRow(title: "Talk", shelf: .talk, count: talkRow.count) {
                    ForEach(talkRow) { session in
                        talkCard(session).frame(width: Self.rowCardWidth)
                    }
                }
            }
            if !watchRow.isEmpty {
                bookRow(title: "Watch", shelf: .watch, count: watchRow.count) {
                    ForEach(watchRow) { s in
                        scenarioCard(s).frame(width: Self.rowCardWidth)
                    }
                }
            }
            if talkRow.isEmpty && watchRow.isEmpty {
                shelfHint("Nothing here yet. Have a talk or watch a scene on Home — the material it generates becomes books here; open one and master your first word or line.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wide enough that a second card and the edge of a third are visible, so
    /// the row reads as scrollable without an affordance.
    private static let rowCardWidth: CGFloat = 190

    /// One activity's in-progress shelf: a header naming the activity (tap to
    /// jump to its full shelf) over a horizontally scrolling row of books.
    /// The row bleeds to the screen edges — the negative inset cancels the
    /// page's 18pt gutter, which the LazyHStack re-applies to its content so
    /// the first card still lines up with everything above it.
    private func bookRow<C: View>(title: String, shelf target: Shelf, count: Int,
                                  @ViewBuilder _ cards: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { shelf = target } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    cards()
                }
                .padding(.horizontal, 18)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -18)
        }
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
        let cards = DrillStore.shared.load()
        dueDrillCount = cards.filter { $0.nextReviewAt <= Date() }.count
        sentencesToStudy = cards.filter { $0.box < DrillStore.maxBox }.count
        dueReviewCount = DueReviewView.dueDeck().count
        // The SAME list the Expressions page shows — said-it phrases, the ones
        // the fluent self used in a call, and the ones watched scenes handed
        // over. Counting only the store's rows meant the tile ignored every
        // expression a Watch book taught.
        expressionsToStudy = ExpressionCatalog.toStudy(scenarios: appState.scenarios,
                                                       store: vocab).count

        // Same union for words: the notebook plus unmastered book words the
        // learner hasn't retired yet. Computed by `WordCatalog` — the same
        // call `WordsView` lists row by row, so the number and the page it
        // opens can't drift.
        wordsToStudy = WordCatalog.toStudy(scenarios: appState.scenarios, store: vocab).count

        // Same rule as the Watch shelf: newest talk first, by when it was
        // STARTED. `endedAt` moves when a talk is continued, which pushed old
        // conversations back to the top of the shelf.
        let finished = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        talks = finished.filter { $0.archivedAt == nil }
        archivedTalks = finished.filter { $0.archivedAt != nil }

        // Exactly what ShadowBrowserView lists under its default lens: every
        // fluent-self line that has never been attempted.
        let practiced = Set(appState.shadowAttempts.map(\.turnId))
        let talkLines = finished
            .flatMap { $0.turns }
            .filter { $0.role == .fluentSelf && !practiced.contains($0.id) }
            .count
        // Scene lines from Watch books count too — the browser lists them now,
        // and the book asks for them. A curriculum item's id IS its shadow
        // turn id, so "practiced" means the same thing on both sides.
        let sceneLines = appState.scenarios
            .filter { !$0.isArchived }
            .flatMap { $0.curriculum?.shadowLines ?? [] }
            .filter { !practiced.contains($0.id) }
            .count
        shadowToStudy = talkLines + sceneLines

        // Second pass: derived talk-book progress (pickup-word extraction is
        // too heavy to block first paint with).
        let toSnapshot = finished
        Task { @MainActor in
            var out: [UUID: TalkCurriculum.Snapshot] = [:]
            let drillCards = DrillStore.shared.load()
            for s in toSnapshot {
                out[s.id] = TalkCurriculum.build(session: s,
                                                 proficiency: appState.proficiency,
                                                 shadowAttempts: appState.shadowAttempts,
                                                 drillCards: drillCards)
            }
            talkSnapshots = out
        }
    }
}

// MARK: - Daily goals editor

/// Steppers for the three daily challenge targets. 0 = challenge off. Writes
/// straight into `GoalStore`, so the Today card behind the sheet updates live.
struct StudyGoalsSheet: View {
    @ObservedObject private var goals = GoalStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: ReviewNotifications.Status?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goals.sentencesPerDay, in: 0...50) {
                        goalLabel("rectangle.stack", "Sentences", goals.sentencesPerDay)
                    }
                    Stepper(value: $goals.wordsPerDay, in: 0...50) {
                        goalLabel("text.book.closed.fill", "Words", goals.wordsPerDay)
                    }
                    Stepper(value: $goals.expressionsPerDay, in: 0...30) {
                        goalLabel("quote.bubble.fill", "Expressions", goals.expressionsPerDay)
                    }
                    Stepper(value: $goals.shadowsPerDay, in: 0...30) {
                        goalLabel("waveform.badge.mic", "Shadowing", goals.shadowsPerDay)
                    }
                } footer: {
                    Text(explain("A day counts once every goal here is met — and only FINISHED work counts: \u{201C}Got it\u{201D} on a sentence, \u{201C}I know\u{201D} on a word or phrase, a recorded shadow take. Sending something to 10 minutes or tomorrow is progress, but it isn\u{2019}t done. Set a goal to 0 to leave it out."))
                }
                // Whether the schedule can actually ring. Without this the
                // learner drops a card on "10 min", nothing comes back, and
                // the feature looks broken instead of unpermitted.
                Section {
                    remindersRow
                } footer: {
                    Text(explain("When you send a card to 10 minutes, tomorrow or 3 days, this is what brings it back. One reminder at a time, at the earliest thing waiting."))
                }
            }
            .task { notifications = await ReviewNotifications.status() }
            .navigationTitle("Daily goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var remindersRow: some View {
        switch notifications {
        case .allowed:
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)
                Text("Reminders on")
                Spacer()
                Image(systemName: "checkmark").foregroundStyle(.green)
            }
        case .notAsked:
            Button {
                Task { notifications = await ReviewNotifications.request() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell").foregroundStyle(.tint).frame(width: 24)
                    Text("Turn on reminders")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        case .denied:
            Button {
                ReviewNotifications.openSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash").foregroundStyle(.orange).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminders are off")
                        Text(explain("Turn them on in Settings"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.footnote).foregroundStyle(.tertiary)
                }
            }
        case nil:
            HStack(spacing: 10) {
                ProgressView().controlSize(.mini).frame(width: 24)
                Text("Reminders").foregroundStyle(.secondary)
            }
        }
    }

    private func goalLabel(_ icon: String, _ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value == 0 ? "Off" : "\(value)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
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

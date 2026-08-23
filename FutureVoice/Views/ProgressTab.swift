import SwiftUI
import Charts

/// Progress — expressed in CEFR (A1–C2) so it actually means something, not an
/// arbitrary 0–100. The overall level is ONE pooled AI judgment over all the
/// user's speech (weekly read); the per-skill pages lean on measured numbers
/// (CEFR-graded vocabulary, articulation WPM, the per-talk grammar score,
/// words/turn) plus the analyzer's qualitative "what to work on" notes. Shadowing and
/// drill reps are PRACTICE, not assessment — they appear as effort (Activity)
/// and never move the level.
struct ProgressTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var vocab = VocabStore.shared

    // Optional because it doubles as the pager's scrollPosition binding.
    @State private var selected: Dim? = .overall
    /// False until the first pass over the archive has landed. Every number
    /// below starts at zero, and zero is a CLAIM here ("nothing measured yet,
    /// 0/10 min") — so the pages must not be drawn from it before it's been
    /// read. Set once, never back: a later refresh redraws numbers, it doesn't
    /// re-open the question of whether there are any.
    @State private var loaded = false
    /// The in-flight pass, cancelled when a newer one starts (tab hops are
    /// cheap to trigger, the walk isn't).
    @State private var reloadTask: Task<Void, Never>?
    /// "How this is assessed" transparency sheet — the recipe with live numbers.
    @State private var showingHowAssessed = false
    @State private var dashboard = PracticeStats.snapshot()
    @State private var dueCount = 0

    // AI holistic CEFR read of the whole conversation (vocab + grammar + fluency + expression)
    @State private var aiLevel: CEFRLevel?
    // Vocabulary (objective CEFR)
    @State private var vocabLevel: CEFRLevel?
    @State private var perLevel: [CEFRLevel: Int] = [:]
    @State private var usedTotal = 0
    // Measured signals
    @State private var wpm = 0
    /// Words per minute of VOICED speech (pauses removed) — the honest pace
    /// signal. Wall-clock `wpm` includes think-time and the VAD wait, so it
    /// both underestimates AND shifts whenever VAD tuning changes; this one
    /// doesn't. Old sessions without mic-energy stats fall back to `wpm`.
    @State private var articulationWpm = 0
    @State private var pausesPerMin = 0.0
    @State private var talkMinutes = 0
    @State private var wordsPerTurn = 0
    /// Average of the recent talks' 0–100 grammar scores — the SAME number
    /// each talk's scorecard shows (anchored on verified grammar slips),
    /// higher is better. Replaces the old suggestion-rate proxy, which also
    /// counted style rephrases and STT noise and read in the wrong direction.
    @State private var grammarScore = 0
    /// Verified grammar slips per 100 spoken words across the recent talks —
    /// the SAME evidence family the assessment cites for grammatical
    /// control, normalized by words (per-turn density would punish long
    /// turns). Drives the ≈Grammar band so the sheet and the verdict tell
    /// one story; the 0–100 score stays as the Grammar page's "recent form".
    @State private var slipsPer100Words = 0.0
    // Qualitative coaching notes (LLM), per dimension
    @State private var notesByDim: [Dim: [String]] = [:]
    @State private var scoredCount = 0
    /// Total user speaking time accumulated across all analyzed sessions.
    /// The holistic level estimate stays provisional until this clears the bar.
    @State private var totalSpeakingMinutes = 0
    /// Minutes of conversation before the first weekly read (and with it the
    /// level estimate) unlocks — mirrors WeeklyReportEngine so the progress
    /// bar here and the report unlock never disagree.
    private static let levelMinMinutes = Int(WeeklyReportEngine.firstReportMinSeconds / 60)
    /// Window for the CURRENT vocabulary level — words last used within this
    /// many days. Lifetime words still feed the cumulative growth chart.
    private static let vocabWindowDays = 90
    /// A level assessed longer ago than this reads as stale — shown dimmed
    /// with a "talk again to refresh" note instead of as today's truth.
    private static let levelStaleDays = 28
    /// The REAL unlock state of the next weekly read — drives the building
    /// panel so it shows the actual conditions (days + new talk), never a
    /// full progress bar with nothing happening behind it.
    @State private var reportUnlock: WeeklyReportEngine.UnlockState =
        .lockedFirst(secondsAccumulated: 0,
                     secondsRequired: WeeklyReportEngine.firstReportMinSeconds)
    // Effort signals (moved here from Practice — measurement lives in
    // Progress; Practice is the review queue + library).
    /// Last 14 days of effort, oldest first — speaking minutes plus per-kind
    /// reps, so the charts can show both HOW MUCH and WHICH KIND.
    @State private var dailyEffort: [DayEffort] = []
    @State private var weekReps = 0
    @State private var daysActiveThisWeek = 0
    @State private var avgShadowScore = 0
    @State private var shadowTrend: PracticeStats.ShadowTrend?
    @State private var carryover = PracticeStats.CarryoverSummary()
    /// Whole-library mastery (moved here from Practice) — filled in the same
    /// second pass the Practice tab used, because deriving a talk book's
    /// material is too heavy to block first paint with.
    @State private var material: (mastered: Int, total: Int) = (0, 0)
    /// CEFR level of each weekly read, oldest first — the level's history.
    @State private var levelHistory: [LevelPoint] = []
    /// Same key Home's goal ring uses — the dashed line in the time chart.
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10

    struct DayEffort: Identifiable {
        let day: Date
        let talkTurns: Int
        let shadowReps: Int
        let drillReps: Int
        let talkMinutes: Double
        var id: Date { day }
        var totalReps: Int { talkTurns + shadowReps + drillReps }
    }

    struct LevelPoint: Identifiable {
        let date: Date
        let rank: Int
        let label: String
        var id: Date { date }
    }

    /// One measured value at one point in time — the per-skill trend series.
    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    // Per-skill trends, oldest first: one point per analyzed talk (vocab is
    // cumulative by day instead — words don't belong to a single session).
    @State private var fluencyTrend: [TrendPoint] = []
    @State private var grammarTrend: [TrendPoint] = []
    @State private var expressionTrend: [TrendPoint] = []
    @State private var vocabTrend: [TrendPoint] = []

    enum Dim: String, CaseIterable, Hashable {
        // Shadowing is deliberately NOT a dimension here: shadow scores
        // measure practice effort, not level. They live in the Activity
        // panel and in Practice — presenting them as an assessed "skill"
        // misread as part of the level estimate.
        case overall, vocabulary, grammar, fluency, expressiveness
        var title: String {
            switch self {
            case .overall: return "Overall"
            default:       return rawValue.capitalized
            }
        }
        var short: String { title }
    }

    var body: some View {
        NavigationStack {
            Group {
                // The paged scaffold shows from day one — before the first
                // scored talk each page renders its explainer (see
                // `explainer(for:)`) instead of hiding the whole tab behind
                // one blank ContentUnavailableView.
                    // A native horizontal-paging ScrollView instead of
                    // TabView(.page): the UIPageViewController behind the paged
                    // TabView clips its pages to the safe area, so content
                    // could never slide under the header or the tab bar. Real
                    // SwiftUI scroll views underlap the bars natively — pages
                    // show through the chip bar's material, the nav bar blurs
                    // on scroll, and content flows under the tab bar.
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(availableDims, id: \.self) { dim in
                                ScrollView {
                                    content(for: dim)
                                        .padding(.horizontal, 18)
                                        .padding(.top, 8)
                                        .padding(.bottom, 28)
                                }
                                .containerRelativeFrame(.horizontal)
                                .id(dim)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selected)
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        tabBar
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                            // One continuous translucent panel from the status
                            // bar down to the chips (the nav bar's own opaque
                            // background is suppressed below), so scrolled
                            // content genuinely shows through the header. `.bar`
                            // (the system nav-bar material), not
                            // `.ultraThinMaterial`, so the tone matches the
                            // plain tabs' nav bar. Its bottom edge is feathered
                            // with a gradient mask — a hard material edge reads
                            // as a visible seam against the background.
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
                    // …and the same panel mirrored at the bottom, so a page
                    // dissolves into the tab bar the way Talk's and Watch's do.
                    // Nested scroll views never get the system's own scroll
                    // edge effect.
                    .tabBarScrollFeather()
                    // NOT .toolbarBackground(.hidden): that drops the rounded
                    // title font (see TransparentRoundedNavBar). The shim hides
                    // the bar background the same way, fonts intact.
                    .background(TransparentRoundedNavBar())
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Progress")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onAppear(perform: reload)
            // When a weekly read finishes generating, pull in its pooled
            // level immediately — no tab-hop needed.
            .onChange(of: appState.weeklyReportGenerating) { _, generating in
                if !generating { reload() }
            }
        }
    }

    /// Content for one dimension page — same views the tab bar selected before,
    /// now also reachable by swiping the paged TabView.
    @ViewBuilder
    private func content(for dim: Dim) -> some View {
        if !loaded {
            // Deliberately NOT the first-run explainer: that page says there
            // is nothing measured yet, which is a lie for everyone with a
            // history, and it was what the tab showed on first entry until
            // the (then synchronous) pass finished.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else if scoredCount == 0 {
            explainer(for: dim)
        } else {
            switch dim {
            case .overall:        overallContent
            case .vocabulary:     vocabularyContent
            case .fluency:        fluencyContent
            case .grammar:        grammarContent
            case .expressiveness: expressivenessContent
            }
        }
    }

    // MARK: - First-run pages (no scored talk yet)

    /// Before the first scored talk, each page introduces its own sections —
    /// same panel shapes and titles the filled page will use, so day one
    /// teaches the map. Overall carries `buildingStatus`, the live unlock
    /// progress, so the thing to do right now is on screen too.
    @ViewBuilder
    private func explainer(for dim: Dim) -> some View {
        VStack(spacing: 16) {
            switch dim {
            case .overall:
                panel {
                    Text("Estimated level").font(.headline)
                    Text("Read from your real talks — vocabulary, grammar, fluency and expression together.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CardDivider(inset: 0)
                    buildingStatus
                }
                explainerChartPanel("Growth",
                                    "Every assessment adds a point — the line is your level over time.") {
                    sampleLevelChart
                }
                explainerPanel("Across skills",
                               "Vocabulary, fluency, grammar and expression each get their own page — swipe or tap the chips above.")
            case .vocabulary:
                explainerPanel("Vocabulary level",
                               "Every word you say in a talk is collected and graded by CEFR — the level reads what you use, not what you know.")
                explainerChartPanel("Words you use, by level",
                                    "Each talk fills these bars, A1 to C2.") {
                    sampleLevelBars
                }
                explainerPanel("Expressions you've used",
                               "Multi-word phrases you actually said, collected automatically.")
            case .fluency:
                explainerPanel("Pace",
                               "Words per minute of voiced speech — pauses and think-time don't drag it down.")
                explainerChartPanel("Trend",
                                    "One point per talk, with ≈CEFR pace bands behind the curve.") {
                    trendChart(sampleTrend([78, 88, 84, 96, 104, 112]),
                               unit: "words / min speaking",
                               bands: Self.fluencyBands,
                               line: Color(.systemGray2))
                }
            case .grammar:
                explainerPanel("Grammatical control",
                               "Read from verified grammar slips per 100 spoken words — fewer reads higher.")
                explainerChartPanel("Trend",
                                    "One point per talk — down is progress.") {
                    trendChart(sampleTrend([6.5, 5.4, 5.8, 4.2, 3.4, 2.8]),
                               unit: "slips / 100 words",
                               bands: Self.grammarBands,
                               line: Color(.systemGray2))
                }
            case .expressiveness:
                explainerPanel("Words per turn",
                               "How much you elaborate — longer, richer turns read higher.")
                explainerChartPanel("Trend",
                                    "One point per talk, with ≈CEFR bands behind the curve.") {
                    trendChart(sampleTrend([7, 9, 8, 12, 14, 17]),
                               unit: "words per turn",
                               bands: Self.expressionBands,
                               line: Color(.systemGray2))
                }
            }
            Label("Your first talk starts filling this page", systemImage: "mic.fill")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private func explainerPanel(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        panel {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// An explainer panel WITH the section's chart, drawn in gray over sample
    /// data and tagged "Sample" — the shape of what will appear, unmistakably
    /// not a measurement of someone the app hasn't heard speak yet.
    private func explainerChartPanel<C: View>(_ title: LocalizedStringKey,
                                              _ text: LocalizedStringKey,
                                              @ViewBuilder chart: () -> C) -> some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("Sample")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            chart()
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Evenly-spaced sample points ending today — the explainer trend curves.
    private func sampleTrend(_ values: [Double]) -> [TrendPoint] {
        let cal = Calendar.current
        return values.enumerated().compactMap { i, v in
            cal.date(byAdding: .day, value: (i - values.count + 1) * 3, to: Date())
                .map { TrendPoint(date: $0, value: v) }
        }
    }

    /// The Growth chart's shape (A2 → B1 over a few assessments), gray.
    private var sampleLevelChart: some View {
        let cal = Calendar.current
        let points: [LevelPoint] = [1, 1, 2, 2, 3].enumerated().compactMap { i, r in
            cal.date(byAdding: .weekOfYear, value: i - 4, to: Date())
                .map { LevelPoint(date: $0, rank: r, label: CEFRLevel.allCases[r].rawValue) }
        }
        return Chart(points) { p in
            LineMark(x: .value("Assessment", p.date), y: .value("Level", p.rank))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color(.systemGray2))
            PointMark(x: .value("Assessment", p.date), y: .value("Level", p.rank))
                .foregroundStyle(Color(.systemGray2))
        }
        .chartYScale(domain: -0.5...5.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(0...5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let i = value.as(Int.self) {
                        Text(CEFRLevel.allCases[i].rawValue.uppercased())
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 130)
    }

    /// The by-level bars' shape — no counts, just the silhouette they'll take.
    private var sampleLevelBars: some View {
        let counts: [CEFRLevel: Int] = [.a1: 120, .a2: 80, .b1: 40, .b2: 12, .c1: 3, .c2: 0]
        return ForEach(CEFRLevel.allCases, id: \.self) { lv in
            HStack(spacing: 10) {
                Text(lv.rawValue.uppercased())
                    .geistPixel(15)
                    .frame(width: 30, alignment: .leading)
                    .foregroundStyle(.secondary)
                GeometryReader { g in
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: max((counts[lv] ?? 0) == 0 ? 0 : 6,
                                          g.size.width * CGFloat(counts[lv] ?? 0) / 120))
                }
                .frame(height: 12)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Sub-tab bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableDims, id: \.self) { dim in
                        Button { withAnimation { selected = dim } } label: {
                            // Fitness+-style pills: monochrome selection — the
                            // active chip fills with the label color and inverts
                            // its text, instead of tinting with the accent.
                            Text(dim.short)
                                .font(.body.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(selected == dim ? Color(.label) : Color(.secondarySystemGroupedBackground)))
                                .foregroundStyle(selected == dim ? Color(.systemBackground) : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(dim)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            // Keep the active chip in view as you swipe pages or tap.
            .onChange(of: selected) { _, new in
                if let new {
                    withAnimation { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
    }

    private var availableDims: [Dim] { Dim.allCases }

    /// The latest report that carries a level — the assessment behind the
    /// big number, its date, its rationale and its evidence snapshot.
    private var latestAssessment: WeeklyReport? {
        appState.weeklyReports
            .filter { $0.cefrLevel != nil }
            .sorted { $0.generatedAt > $1.generatedAt }
            .first
    }

    /// When the level was last actually assessed (latest report's timestamp).
    private var latestAssessmentAt: Date? { latestAssessment?.generatedAt }

    /// True when the shown level is older than `levelStaleDays` — the display
    /// dims and says so rather than passing old evidence off as current.
    private var levelIsStale: Bool {
        guard let at = latestAssessmentAt else { return false }
        return Date().timeIntervalSince(at) > Double(Self.levelStaleDays) * 86_400
    }

    // MARK: - Overall

    private var overallContent: some View {
        VStack(spacing: 16) {
            panel {
                Text("Estimated level").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                // A level shows ONLY once a pooled weekly read exists. No
                // early guesses from single sessions — if the sample isn't
                // big enough, the honest display is "still collecting".
                if let lv = aiLevel {
                    // A stale level (no assessment in 4+ weeks) dims instead
                    // of posing as today's truth.
                    Text(lv.rawValue.uppercased())
                        .geistPixel(52)
                        .foregroundStyle(levelIsStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    // Korean target: learners orient by TOPIK, so show the
                    // official CEFR↔TOPIK equivalence under the big number.
                    if LanguageCatalog.levelLabel(lv, target: appState.targetLanguage)
                        != lv.rawValue.uppercased() {
                        Text(LanguageCatalog.levelLabel(lv, target: appState.targetLanguage))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(canDo(lv)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let at = latestAssessmentAt {
                        Text(levelIsStale
                             ? "Assessed \(at.formatted(.relative(presentation: .named))) — a while back. Your next talks feed a fresh assessment."
                             : "Assessed \(at.formatted(.relative(presentation: .named))) from your recent talk — vocabulary, grammar, fluency and expression together.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(explain("Assessed from \(totalSpeakingMinutes) min of conversation — vocabulary, grammar, fluency and expression together."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    nextAssessmentStatus
                } else {
                    // Before the first assessment there is NO level on this
                    // page — not even the self-reported one. It used to sit
                    // here in the same 52pt type as a measured level, and a
                    // "self-reported" chip is too quiet a distinction: from
                    // day one the app appeared to have graded someone it had
                    // never heard speak. What the user set in onboarding still
                    // drives the conversation prompts; it just isn't presented
                    // back to them as a result. `buildingStatus` below carries
                    // the honest state instead — what it takes and how far in
                    // they are, as a progress bar against `levelMinMinutes`.
                    //
                    // The recipe made visible, equalizer-style: one bar per
                    // measured ingredient, lit LED blocks = that axis's CEFR
                    // band. A weak axis is a visibly shorter column.
                    LevelEqualizer(bars: equalizerBars)
                        .padding(.top, 8)
                    Text(explain("Vocabulary is graded from the words you actually use; ≈ levels are read from your pace, grammar score and turn length."))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    CardDivider(inset: 0)
                    buildingStatus
                }
                Button { showingHowAssessed = true } label: {
                    Label("How this is assessed", systemImage: "info.circle")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            }
            .sheet(isPresented: $showingHowAssessed) { howAssessedSheet }

            // THE growth graph: your level, one point per assessment. Present
            // from the first assessment on — with one point it explains that
            // the curve starts at the second, instead of hiding entirely.
            if !levelHistory.isEmpty {
                levelHistoryPanel
            }

            // ONE unit on the level page: CEFR bands, same values as the
            // "How this is assessed" sheet and the pre-assessment equalizer.
            // The raw numbers (WPM, 0–100 score, words/turn) live on each
            // skill's own page behind the row.
            panel {
                Text("Across skills").font(.headline)
                skillRow(.vocabulary, value: vocabLevel.map { $0.rawValue.uppercased() } ?? "—")
                skillRow(.fluency, value: fluencyCEFR.map { "≈" + $0.rawValue.uppercased() } ?? "—")
                skillRow(.grammar, value: grammarCEFR.map { "≈" + $0.rawValue.uppercased() } ?? "—")
                skillRow(.expressiveness, value: expressionCEFR.map { "≈" + $0.rawValue.uppercased() } ?? "—")
                Text(explain("Same bands as \u{201C}How this is assessed\u{201D} — tap a skill for its measured numbers."))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let lv = aiLevel, let next = nextLevel(lv) {
                panel {
                    Text("To reach \(next.rawValue.uppercased())").font(.headline)
                    Text(canDo(next)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Focus = the axes that MEASURE below the target level,
                    // each with its live number — not a hardcoded "more
                    // words". Measurement tab stays measurement-only: the
                    // doing (vocabulary, drills, shadowing) lives in Practice.
                    // …and each one that has somewhere to be done carries the
                    // way there, so "use more C1 words" is one tap from the
                    // C1 words instead of a route the learner has to retrace.
                    ForEach(focusTips(toward: next), id: \.text) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: tip.icon)
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tip.text).font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let action = tip.action { tipLink(action) }
                            }
                        }
                    }
                }
            }

            if dailyEffort.contains(where: { $0.talkMinutes > 0 }) {
                studyTimePanel
            }

            carryoverPanel

            materialPanel

            if dailyEffort.contains(where: { $0.totalReps > 0 }) {
                activityPanel
            }

            consistencyPanel

            weeklyReadPanel
        }
    }

    // MARK: - This week's read (digest — the full report is a push away)

    /// The report, readable at a glance: the 1–2 sentence trend plus counts.
    /// The full item lists (every expression, every correction) moved to
    /// their own pushed page — a wall of text at the bottom of Overall was
    /// getting skipped, not read.
    private var weeklyReadPanel: some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Latest assessment").font(.headline)
                Spacer()
                if appState.weeklyReportGenerating {
                    ProgressView().controlSize(.small)
                } else if let r = appState.weeklyReports.first {
                    Text(readDateRange(r))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let r = appState.weeklyReports.first {
                Text(r.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                digestRow(icon: "sparkles", count: r.newExpressions.count,
                          text: "new expressions you used")
                digestRow(icon: "arrow.triangle.2.circlepath", count: r.repeatedMistakes.count,
                          text: "patterns to work on")
                digestRow(icon: "plus.bubble", count: r.suggestedExpressions.count,
                          text: "expressions worth adding")
                NavigationLink {
                    ScrollView {
                        WeeklyReportView()
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .navigationTitle("Latest assessment")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
                } label: {
                    HStack {
                        Text("Read the full report")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            } else {
                weeklyReadLockedState
            }
        }
    }

    @ViewBuilder
    private func digestRow(icon: String, count: Int, text: String) -> some View {
        if count > 0 {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                Text("\(count)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(text)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// No report yet — one calm line on what unlocks it, from the SAME
    /// unlock state the building panel uses, so they never disagree.
    @ViewBuilder
    private var weeklyReadLockedState: some View {
        switch reportUnlock {
        case .lockedFirst(let acc, let req):
            Text(explain("Your first assessment unlocks after \(Int(req / 60)) minutes of talk."))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView(value: min(acc, req), total: req)
                    .tint(.accentColor)
                Text("\(Int(acc / 60))/\(Int(req / 60)) min")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .lockedNext(let days, let secondsRemaining):
            let minsRem = max(1, Int((secondsRemaining / 60).rounded(.up)))
            Text(days > 0
                 ? "Next assessment in \(days) day\(days == 1 ? "" : "s")."
                 : "Next assessment after \(minsRem) more min of new talk.")
                .font(.subheadline).foregroundStyle(.secondary)
        case .ready:
            if appState.weeklyReportFailed && !appState.weeklyReportGenerating {
                assessmentFailedRow
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing your week…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func readDateRange(_ r: WeeklyReport) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: r.periodStart)) – \(fmt.string(from: r.periodEnd))"
    }

    // MARK: - Growth (level, one point per assessment)

    /// The headline growth graph: only assessments move this line, so it IS
    /// the honest "am I improving" answer — the 0–100 talk scores can't be
    /// (they're graded relative to the current level).
    private var levelHistoryPanel: some View {
        panel {
            Text("Growth").font(.headline)
            if levelHistory.count >= 2 {
                Chart(levelHistory) { p in
                    LineMark(x: .value("Assessment", p.date), y: .value("Level", p.rank))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.tint)
                    PointMark(x: .value("Assessment", p.date), y: .value("Level", p.rank))
                        .foregroundStyle(.tint)
                }
                .chartYScale(domain: -0.5...5.5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(0...5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let i = value.as(Int.self) {
                                Text(CEFRLevel.allCases[i].rawValue.uppercased())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
                Text(explain("Your level, one point per assessment — this line is what growing looks like."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(explain("Your growth curve starts at your second assessment — every assessment adds a point here, and only assessments move your level."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Study time (minutes actually spoken, per day)

    private var studyTimePanel: some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Time speaking").font(.headline)
                Spacer()
                let weekMin = Int(dailyEffort.suffix(7).reduce(0) { $0 + $1.talkMinutes })
                Text("\(weekMin) min this week")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Chart {
                ForEach(dailyEffort) { d in
                    BarMark(x: .value("Day", d.day, unit: .day),
                            y: .value("Minutes", d.talkMinutes))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", Double(dailyGoalMinutes)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .frame(height: 120)
            Text(explain("Minutes you actually spoke, per day. The dashed line is your \(dailyGoalMinutes)-minute daily goal."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Transfer (studied → said)

    /// Effort is the panel below; this one is whether the effort LANDED.
    /// Deliberately a count and not a percentage: a rate would need a
    /// denominator of "everything you were studying at the time", which
    /// changes every day and would quietly punish anyone who adds material
    /// faster than they use it. The count only ever goes up, and every entry
    /// is backed by a sentence the learner actually said.
    @ViewBuilder
    private var carryoverPanel: some View {
        if carryover.total > 0 {
            panel {
                HStack(alignment: .firstTextBaseline) {
                    Text("Studied, then said").font(.headline)
                    Spacer()
                    if carryover.thisWeek > 0 {
                        Label("+\(carryover.thisWeek) this week", systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(carryover.total)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(carryover.total == 1
                         ? "thing you studied has come out of your mouth in a real conversation"
                         : "things you studied have come out of your mouth in a real conversation")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CardDivider(inset: 0)
                FlowLayout(spacing: 8) {
                    ForEach(Carryover.Source.displayOrder, id: \.self) { source in
                        if let count = carryover.bySource[source], count > 0 {
                            Label("\(source.label) \(count)", systemImage: source.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                }
                if !carryover.recent.isEmpty {
                    CardDivider(inset: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(carryover.recent) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.item).font(.subheadline.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("“\(c.quote)”")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Material (whole-library mastery — moved from Practice)

    /// How much of everything your talks and watches generated is mastered.
    ///
    /// Lived on the Practice tab until it sat directly under the Today card's
    /// Words / Expressions / Shadowing rows — two cards deep in the same three
    /// nouns, one asking "what today", the other "how far overall". Measuring
    /// is this tab's job, so the question moved to where it's answered.
    ///
    /// Note what the percentage does: the denominator GROWS every time you
    /// talk or watch, so an active week can push it down. The count leads and
    /// the bar follows precisely because the count only ever goes up.
    @ViewBuilder
    private var materialPanel: some View {
        if material.total > 0 {
            panel {
                Text("Your material").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(material.mastered)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(material.mastered == 1
                         ? "word or line mastered, out of \(material.total) your talks and watches have made"
                         : "words and lines mastered, out of \(material.total) your talks and watches have made")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ProgressView(value: Double(material.mastered), total: Double(material.total))
                    .tint(material.mastered == material.total ? .green : .accentColor)
            }
            // Identifier, not the title: the chrome follows the TARGET
            // language, so a test matching "Your material" passes only until
            // that string gets translated.
            .accessibilityIdentifier("progress.materialPanel")
        }
    }

    // MARK: - Activity (effort made visible — moved from Practice)

    /// One (day, kind) slice for the stacked mix chart. Fixed kind order —
    /// Talk · Shadowing · Drills — so colors never reshuffle between days.
    private struct MixEntry: Identifiable {
        let day: Date
        let kind: String
        let count: Int
        var id: String { "\(kind)\(day.timeIntervalSinceReferenceDate)" }
    }

    private var mixEntries: [MixEntry] {
        dailyEffort.flatMap { d in
            [MixEntry(day: d.day, kind: "Talk", count: d.talkTurns),
             MixEntry(day: d.day, kind: "Shadowing", count: d.shadowReps),
             MixEntry(day: d.day, kind: "Sentences", count: d.drillReps)]
        }
        .filter { $0.count > 0 }
    }

    private var activityPanel: some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.headline)
                Spacer()
                if let delta = shadowTrend?.delta {
                    Label(delta >= 0 ? "shadow +\(delta)" : "shadow \(delta)",
                          systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? Color.green : Color.orange)
                }
            }
            // Stacked by KIND, not just totals — a column that's always one
            // color is the "I only ever do the comfortable thing" signal.
            Chart(mixEntries) { e in
                BarMark(x: .value("Day", e.day, unit: .day),
                        y: .value("Reps", e.count))
                    .foregroundStyle(by: .value("Kind", e.kind))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale([
                "Talk": Color(.systemBlue),
                "Shadowing": Color(.systemGreen),
                "Sentences": Color(.systemOrange),
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .frame(height: 130)
            Text(explain("What each day was made of — talk turns, shadow takes, drill reviews."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CardDivider(inset: 0)
            HStack(spacing: 16) {
                activityStat(value: "\(weekReps)", label: weekReps == 1 ? "rep this week" : "reps this week")
                activityStat(value: "\(daysActiveThisWeek)", label: daysActiveThisWeek == 1 ? "day active" : "days active")
                if avgShadowScore > 0 {
                    activityStat(value: "\(avgShadowScore)", label: "avg shadow score")
                }
            }
        }
    }

    private func activityStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Per-axis CEFR estimates for the ring
    //
    // ONE rule for every arc: fill = the axis's CEFR position, full = C2.
    // Vocabulary is graded directly (word-list lookup). The other three are
    // deterministic proxies mapped to CEFR bands — real measurements, but
    // heuristic mappings, so the UI marks them "≈".
    //
    // Band edges live in ONE table per skill, used BOTH by the ≈level
    // mapping and by the trend charts' background zones — the chart can
    // never show a different band than the mapping assigns.

    typealias BandSpec = (level: CEFRLevel, range: ClosedRange<Double>)

    private static let fluencyBands: [BandSpec] = [
        (.a1, 0...60), (.a2, 60...85), (.b1, 85...105),
        (.b2, 105...125), (.c1, 125...145), (.c2, 145...200)
    ]
    /// Verified slips per 100 words — ordered best-first (fewer is higher).
    private static let grammarBands: [BandSpec] = [
        (.c2, 0...0.5), (.c1, 0.5...1), (.b2, 1...2),
        (.b1, 2...4), (.a2, 4...7), (.a1, 7...15)
    ]
    private static let expressionBands: [BandSpec] = [
        (.a1, 0...6), (.a2, 6...10), (.b1, 10...16),
        (.b2, 16...24), (.c1, 24...34), (.c2, 34...60)
    ]

    /// Half-open lookup ([lower, upper)); values past the table's end take
    /// the LAST entry's level, so an off-scale measurement doesn't go unbanded.
    private static func band(for value: Double, in specs: [BandSpec]) -> CEFRLevel? {
        specs.first { value >= $0.range.lowerBound && value < $0.range.upperBound }?.level
            ?? specs.last?.level
    }

    /// Articulation pace → CEFR band. Speech-rate bands are a recognized
    /// (if rough) proficiency proxy; boundaries follow typical learner
    /// articulation rates (natives ~150+). Sessions without mic-energy stats
    /// fall back to wall-clock WPM, which runs ~20 WPM lower (think-time and
    /// VAD wait included) — shift it up before banding, same correction
    /// `fluencyBand` applies, so old data doesn't read 1–2 levels too low.
    private var fluencyCEFR: CEFRLevel? {
        guard effectivePace > 0 else { return nil }
        let adjusted = articulationWpm > 0 ? effectivePace : effectivePace + 20
        return Self.band(for: Double(adjusted), in: Self.fluencyBands)
    }

    /// Grammar → CEFR band from verified slip DENSITY — the same evidence
    /// the assessment cites for grammatical control, so this row and the
    /// verdict's rationale always tell one story. (The 0–100 score can't do
    /// that: it's calibrated to the user's level setting, so a high-slip
    /// speaker can still score 70+.) Falls back to the score only when no
    /// slip data exists, so absent data doesn't read as perfect grammar.
    private var grammarCEFR: CEFRLevel? {
        guard scoredCount > 0 else { return nil }
        if slipsPer100Words > 0 {
            return Self.band(for: slipsPer100Words, in: Self.grammarBands)
        }
        guard grammarScore > 0 else { return nil }
        switch grammarScore {
        case ..<40:     return .a1
        case 40..<55:   return .a2
        case 55..<70:   return .b1
        case 70..<82:   return .b2
        case 82..<92:   return .c1
        default:        return .c2
        }
    }

    /// Words per turn → CEFR band. The WEAKEST proxy of the four — it
    /// measures turn LENGTH, not expressive quality, and chatty speakers
    /// inflate it. Thresholds sit deliberately high so a long-winded B1
    /// doesn't read as C2.
    private var expressionCEFR: CEFRLevel? {
        guard wordsPerTurn > 0 else { return nil }
        return Self.band(for: Double(wordsPerTurn), in: Self.expressionBands)
    }

    private var equalizerBars: [LevelEqualizer.Bar] {
        func lit(_ lv: CEFRLevel?) -> Int {
            lv.map { CoreVocabulary.levelRank($0) + 1 } ?? 0
        }
        func label(_ lv: CEFRLevel?, approx: Bool) -> String {
            lv.map { (approx ? "≈" : "") + $0.rawValue.uppercased() } ?? "—"
        }
        return [
            .init(name: "Vocab", level: label(vocabLevel, approx: false),
                  lit: lit(vocabLevel), color: Color(.systemBlue)),
            .init(name: "Fluency", level: label(fluencyCEFR, approx: true),
                  lit: lit(fluencyCEFR), color: Color(.systemGreen)),
            .init(name: "Grammar", level: label(grammarCEFR, approx: true),
                  lit: lit(grammarCEFR), color: Color(.systemOrange)),
            .init(name: "Express", level: label(expressionCEFR, approx: true),
                  lit: lit(expressionCEFR), color: Color(.systemPurple)),
        ]
    }

    /// When and how the level actually gets assessed — mirrors the weekly
    /// read's REAL unlock rules instead of a vague progress bar.
    @ViewBuilder
    private var buildingStatus: some View {
        if appState.weeklyReportGenerating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Assessing your level from everything you've said…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            switch reportUnlock {
            case .lockedFirst(let acc, let req):
                Text(explain("Your level is graded at your first assessment — one pooled judgment over ALL your talk, not a guess from one session."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ProgressView(value: min(acc, req), total: req)
                        .tint(.accentColor)
                    Text("\(Int(acc / 60))/\(Int(req / 60)) min")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            case .lockedNext(let daysRemaining, let secondsRemaining):
                Text(explain("Your level is re-assessed regularly. The next assessment needs both:"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                unlockConditionRow(
                    icon: "calendar",
                    met: daysRemaining == 0,
                    text: daysRemaining == 0
                        ? "A week since the last assessment"
                        : (daysRemaining == 1 ? "1 more day" : "\(daysRemaining) more days"))
                unlockConditionRow(
                    icon: "mic.fill",
                    met: secondsRemaining == 0,
                    text: secondsRemaining == 0
                        ? "Enough new conversation"
                        : "\(max(1, Int((secondsRemaining / 60).rounded(.up)))) more min of new talk")
            case .ready:
                if appState.weeklyReportFailed {
                    assessmentFailedRow
                } else {
                    // reload() already kicked off generation — this shows only
                    // in the brief gap before `weeklyReportGenerating` flips
                    // true.
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ready — assessing your level now…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Shown UNDER an existing level: when the next re-assessment happens and
    /// exactly how much more talk gets you there — the "keep going" hook.
    @ViewBuilder
    private var nextAssessmentStatus: some View {
        CardDivider(inset: 0)
        if appState.weeklyReportGenerating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Re-assessing your level now…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            switch reportUnlock {
            case .lockedNext(let daysRemaining, let secondsRemaining):
                Text("Next assessment")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                // The talk requirement as a live bar — filling it is the part
                // the user can actually go do right now.
                let required = WeeklyReportEngine.recurringMinSeconds
                let done = max(0, min(required, required - secondsRemaining))
                HStack(spacing: 10) {
                    ProgressView(value: done, total: required)
                        .tint(.accentColor)
                    Text("\(Int(done / 60))/\(Int(required / 60)) min new talk")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .layoutPriority(1)
                }
                unlockConditionRow(
                    icon: "calendar",
                    met: daysRemaining == 0,
                    text: daysRemaining == 0
                        ? "A week since the last assessment"
                        : (daysRemaining == 1 ? "1 more day" : "\(daysRemaining) more days"))
                if secondsRemaining > 0 {
                    Text(explain("Talk \(max(1, Int((secondsRemaining / 60).rounded(.up)))) more minutes and this level gets re-read from everything new you've said."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .ready:
                if appState.weeklyReportFailed {
                    assessmentFailedRow
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ready — re-assessing your level now…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            case .lockedFirst:
                // Can't happen once a level exists; nothing to show.
                EmptyView()
            }
        }
    }

    /// The assessment is due but the last attempt threw. Drawn INSTEAD of the
    /// `.ready` spinner: the unlock state stays `.ready` after a failure, so
    /// without this the panel claims a read is running when nothing is, and
    /// flips back to the spinner on every automatic retry.
    private var assessmentFailedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(explain("Couldn't finish the assessment — it'll try again shortly."),
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try now") { appState.retryWeeklyReport() }
                .font(.callout)
        }
    }

    private func unlockConditionRow(icon: String, met: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : icon)
                .font(.subheadline)
                .foregroundStyle(met ? Color.green : Color.secondary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(met ? .secondary : .primary)
        }
    }

    // MARK: - How the level is assessed (transparency sheet)

    /// The assessment recipe, shown with the user's LIVE numbers — every
    /// ingredient names its measurement and how it maps to a band, so the
    /// level never reads as a black box (or as "just vocabulary").
    private var howAssessedSheet: some View {
        NavigationStack {
            List {
                Section {
                    if let lv = aiLevel {
                        HStack {
                            Text("Assessed level").font(.subheadline.weight(.medium))
                            Spacer()
                            Text(lv.rawValue.uppercased())
                                .font(.headline).foregroundStyle(.tint)
                        }
                    }
                    // The judge's own justification, citing the evidence
                    // numbers — the verdict must never be unexplainable.
                    if let why = latestAssessment?.levelRationale, !why.isEmpty {
                        Text(why).font(.callout)
                    }
                    Text(explain("Your level comes from periodic assessments — each one pools everything you've said since the previous assessment and judges it against the official CEFR speaking descriptors: range and precision of vocabulary, grammatical control across the errors you make, and how far you develop ideas. The first assessment unlocks after \(Self.levelMinMinutes) minutes of talk; after that you're re-assessed each week you keep talking, and only assessments move your level."))
                        .font(.callout)
                        .foregroundStyle(latestAssessment?.levelRationale == nil ? .primary : .secondary)
                } header: {
                    Text(latestAssessment?.levelRationale == nil
                         ? "The estimated level" : "Why this level")
                }
                // `latestAssessment.levelEvidence` is deliberately NOT drawn
                // here. It is the prompt block handed to the judge — English
                // snake_case field names and band tables written FOR a model —
                // so on a Korean phone it read as leftover debug output, and
                // the "What's measured" section below already states every one
                // of those numbers in the learner's own language. It stays on
                // the report so a surprising verdict is still reproducible.
                Section {
                    assessedRow(name: "Vocabulary",
                                level: vocabLevel.map { $0.rawValue.uppercased() },
                                detail: usedTotal > 0
                                    ? "\(usedTotal) distinct words you've used in the last \(Self.vocabWindowDays) days, each graded against the CEFR word list. Fully objective."
                                    : "Graded from the words you've used in the last \(Self.vocabWindowDays) days, against the CEFR word list. Fully objective.")
                    assessedRow(name: "Fluency",
                                level: fluencyCEFR.map { "≈" + $0.rawValue.uppercased() },
                                detail: effectivePace > 0
                                    ? "\(effectivePace) words per minute of voiced speech — pauses and think-time removed."
                                    : "Words per minute of voiced speech — pauses and think-time removed.")
                    assessedRow(name: "Grammar",
                                level: grammarCEFR.map { "≈" + $0.rawValue.uppercased() },
                                detail: slipsPer100Words > 0
                                    ? String(format: "%.1f verified grammar slips per 100 spoken words — the same density the assessment weighs.", slipsPer100Words)
                                    : (grammarScore > 0
                                        ? "Scoring \(grammarScore)/100 across recent talks — each talk graded from the verified grammar slips in what you said."
                                        : "Verified grammar slips per 100 spoken words — fewer reads higher."))
                    assessedRow(name: "Expression",
                                level: expressionCEFR.map { "≈" + $0.rawValue.uppercased() },
                                detail: wordsPerTurn > 0
                                    ? "\(wordsPerTurn) words per turn — how far ideas get developed."
                                    : "Words per turn — how far ideas get developed.")
                } header: {
                    Text("What's measured")
                } footer: {
                    Text(explain("≈ marks a deterministic proxy — a real measurement mapped to a CEFR band by fixed thresholds, not an AI opinion. Each band is a CEILING from one measurement (fast pace or long turns alone don't make a level), so the assessed level normally sits at or below the strongest bands here: the assessment also weighs error density and how far ideas actually get developed."))
                }
                Section {
                    Text(explain("Shadowing scores and review reps measure practice, not level. They live under Activity and in the Practice tab — doing them makes you better, and the level moves only when your speech does."))
                        .font(.callout)
                } header: {
                    Text("What never moves the level")
                }
            }
            .navigationTitle("How it's assessed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingHowAssessed = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func assessedRow(name: String, level: String?, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(level ?? "—").font(.headline).monospacedDigit().foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }

    private func skillRow(_ dim: Dim, value: String) -> some View {
        Button { selected = dim } label: {
            HStack {
                Text(dim.short).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var consistencyPanel: some View {
        panel {
            NavigationLink { ActivityView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill").font(.title3)
                        .foregroundStyle(dashboard.streakDays > 0 ? .orange : .secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboard.streakDays == 0 ? "No streak yet" : "\(dashboard.streakDays)-day streak")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text("\(dashboard.totalSessions) talks · tap for calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Vocabulary (objective CEFR breakdown)

    private var vocabularyContent: some View {
        VStack(spacing: 16) {
            panel {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(vocabLevel?.rawValue.uppercased() ?? "—")
                        .geistPixel(44).foregroundStyle(.tint)
                    Text("vocabulary level").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(explain("Estimated from \(usedTotal) distinct words you've used in the last \(Self.vocabWindowDays) days, each graded by CEFR level — your current speaking vocabulary, not everything ever."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if vocabTrend.count >= 2 {
                panel {
                    Text("Vocabulary growth").font(.headline)
                    Chart(vocabTrend) { p in
                        AreaMark(x: .value("Day", p.date), y: .value("Words", p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.accentColor.opacity(0.15))
                        LineMark(x: .value("Day", p.date), y: .value("Words", p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.tint)
                    }
                    .frame(height: 130)
                    Text(explain("Distinct graded words you've used, accumulating from the day each was first said."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            panel {
                Text("Words you use, by level").font(.headline)
                Text(explain("Distinct words from your talks in the last \(Self.vocabWindowDays) days."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(CEFRLevel.allCases, id: \.self) { lv in
                    levelBar(lv)
                }
            }
            panel {
                Text("How to level up").font(.headline)
                Text(explain("Discover and use words you don't reach for yet — the ones at and above your level."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                // The band right above the measured one: the words that would
                // actually move this number, already filtered.
                actionButton(seeWordsAction(at: vocabNextBand))
            }
            panel {
                HStack(alignment: .firstTextBaseline) {
                    Text("Expressions you've used").font(.headline)
                    Spacer()
                    Text("\(vocab.expressionCount)")
                        .font(.headline).foregroundStyle(.tint).monospacedDigit()
                }
                Text(explain("Multi-word phrases you actually said in your talks, collected automatically."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if vocab.expressionCount > 0 {
                    tipLink(TipAction(title: chrome("Browse expressions"),
                                      icon: "text.quote") {
                        appState.pendingPracticeRoute = .expressions(phrase: nil)
                    })
                }
            }
        }
    }

    private func levelBar(_ lv: CEFRLevel) -> some View {
        let count = perLevel[lv] ?? 0
        let maxC = max(1, perLevel.values.max() ?? 1)
        return HStack(spacing: 10) {
            Text(lv.rawValue.uppercased())
                .geistPixel(15)
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(lv == vocabLevel ? Color.accentColor : .secondary)
            GeometryReader { g in
                Capsule()
                    .fill(lv == vocabLevel ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(width: max(count == 0 ? 0 : 6, g.size.width * CGFloat(count) / CGFloat(maxC)))
            }
            .frame(height: 12)
            Text("\(count)").font(.caption).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Fluency / Pronunciation / Grammar / Expressiveness (measured + coaching)

    private var fluencyContent: some View {
        measuredContent(
            dim: .fluency,
            big: effectivePace > 0 ? "\(effectivePace)" : "—",
            bigUnit: articulationWpm > 0 ? "words / min speaking" : "words / min",
            band: fluencyBand,
            measuredLine: effectivePace > 0
                ? String(format: "%.1f pauses/min · ", pausesPerMin) + "\(talkMinutes)m per talk · \(wordsPerTurn) words/turn"
                : nil,
            measures: "Pace measured from voiced speech only — pauses and think-time don't drag it down.",
            improve: "Talk more often and a little longer. Aim past your daily speaking goal; longer turns build flow.",
            action: startTalkAction,
            trend: fluencyTrend,
            trendCaption: "Words per minute of voiced speech — one point per talk. Background zones are the ≈CEFR pace bands.",
            trendBands: Self.fluencyBands
        )
    }

    /// ONE currency on this page: verified slip density → the same ≈band the
    /// assessment cites. The 0–100 talk score was shown here before and kept
    /// reading as a level ("71 = B?") — it lives on talk cards only now.
    private var grammarContent: some View {
        measuredContent(
            dim: .grammar,
            big: grammarCEFR.map { "≈" + $0.rawValue.uppercased() } ?? "—",
            bigUnit: "grammatical control",
            band: nil,
            measuredLine: slipsPer100Words > 0
                ? String(format: "%.1f verified grammar slips per 100 spoken words across your assessed talks%@.",
                         slipsPer100Words, grammarTargetHint)
                : "Verified grammar slips per 100 spoken words — fewer reads higher.",
            measures: "Counted from transcript-verified slips only — STT artifacts and style suggestions are excluded. This is the exact number your level assessment weighs.",
            improve: "Run your review cards — they're built from your own slips and target exactly these.",
            action: reviewSlipsAction,
            trend: grammarTrend,
            trendCaption: "Verified slips per 100 words, one point per talk — DOWN is progress. Background zones are the ≈CEFR bands; the dashed line is the next one.",
            trendTarget: grammarNextBandThreshold,
            trendBands: Self.grammarBands
        )
    }

    /// "— get under 2.0 and this reads ≈B2" — the concrete next-band goal.
    private var grammarTargetHint: String {
        guard let t = grammarNextBandThreshold, let lv = grammarCEFR,
              let next = nextLevel(lv) else { return "" }
        return String(format: explain(" — get under %.1f and this reads ≈%@"), t, next.rawValue.uppercased())
    }

    /// Upper density bound of the NEXT band up (nil at ≈C2 / no data) —
    /// derived from the same band table as the mapping and the chart zones.
    private var grammarNextBandThreshold: Double? {
        guard slipsPer100Words > 0, let lv = grammarCEFR,
              let idx = Self.grammarBands.firstIndex(where: { $0.level == lv }),
              idx > 0 else { return nil }
        return Self.grammarBands[idx - 1].range.upperBound
    }

    private var expressivenessContent: some View {
        measuredContent(
            dim: .expressiveness,
            big: wordsPerTurn > 0 ? "\(wordsPerTurn)" : "—",
            bigUnit: "words per turn",
            band: nil,
            measuredLine: "Longer, richer turns usually mean you're elaborating more.",
            measures: "How vividly and naturally you get your meaning across.",
            improve: "Tell stories, react, and add detail — describe how things felt, not just what happened.",
            action: startTalkAction,
            trend: expressionTrend,
            trendCaption: "Average words per turn — one point per talk. Background zones are the ≈CEFR bands.",
            trendBands: Self.expressionBands
        )
    }

    /// A dimension's trend over time — the same measurement as the page's
    /// headline number, one point per analyzed talk.
    @ViewBuilder
    private func trendPanel(_ trend: [TrendPoint], unit: String, caption: String,
                            target: Double? = nil,
                            bands: [BandSpec] = []) -> some View {
        if trend.count >= 2 {
            panel {
                Text("Trend").font(.headline)
                trendChart(trend, unit: unit, target: target, bands: bands)
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The trend chart itself — shared between the real per-skill pages and
    /// the first-run explainers (which draw it in gray over sample data).
    private func trendChart(_ trend: [TrendPoint], unit: String,
                            target: Double? = nil,
                            bands: [BandSpec] = [],
                            line: Color = .accentColor) -> some View {
        // Y-domain from the data (plus the goal line), padded — bands are
        // then CLIPPED to it, so the zones label the visible range instead
        // of squashing the curve to fit every band.
        let values = trend.map(\.value) + (target.map { [$0] } ?? [])
        let span = max((values.max() ?? 1) - (values.min() ?? 0), 1)
        let lo = max(0, (values.min() ?? 0) - span * 0.25)
        let hi = (values.max() ?? 1) + span * 0.25
        // Zones clipped to the visible domain. Labels sit on the LEADING
        // edge (the numeric y-axis owns the trailing edge) and are
        // dropped for slivers too thin to hold a caption without
        // colliding with the neighbor's.
        let visibleBands: [(label: String, lo: Double, hi: Double, labeled: Bool)] =
            bands.compactMap { band in
                let bLo = max(band.range.lowerBound, lo)
                let bHi = min(band.range.upperBound, hi)
                guard bLo < bHi else { return nil }
                return (band.level.rawValue.uppercased(), bLo, bHi,
                        (bHi - bLo) / (hi - lo) >= 0.14)
            }
        return Chart {
            // CEFR zones behind the curve — same edges as the ≈band
            // mapping (one shared table per skill).
            ForEach(Array(visibleBands.enumerated()), id: \.offset) { i, band in
                RectangleMark(
                    yStart: .value(unit, band.lo),
                    yEnd: .value(unit, band.hi)
                )
                .foregroundStyle(Color(.secondarySystemFill)
                    .opacity(i.isMultiple(of: 2) ? 0.55 : 0.25))
                .annotation(position: .overlay, alignment: .topLeading) {
                    if band.labeled {
                        Text(band.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                            .padding(.top, 1)
                    }
                }
            }
            ForEach(trend) { p in
                LineMark(x: .value("Talk", p.date), y: .value(unit, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(line)
                PointMark(x: .value("Talk", p.date), y: .value(unit, p.value))
                    .foregroundStyle(line)
                    .symbolSize(30)
            }
            // The next-band goal line — gives the curve a finish line.
            if let target {
                RuleMark(y: .value(unit, target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: lo...hi)
        .frame(height: 130)
    }

    private func measuredContent(dim: Dim, big: String, bigUnit: String, band: String?,
                                 measuredLine: String?, measures: String, improve: String,
                                 action: TipAction?, trend: [TrendPoint] = [],
                                 trendCaption: String = "",
                                 trendTarget: Double? = nil,
                                 trendBands: [BandSpec] = []) -> some View {
        VStack(spacing: 16) {
            panel {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(big).geistPixel(44).foregroundStyle(.tint)
                    Text(bigUnit).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let band { Text(band).font(.subheadline.weight(.semibold)) }
                }
                if let measuredLine {
                    Text(measuredLine).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(measures).font(.footnote).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }

            trendPanel(trend, unit: bigUnit, caption: trendCaption,
                       target: trendTarget, bands: trendBands)

            if let notes = notesByDim[dim], !notes.isEmpty {
                panel {
                    Text("What I noticed lately").font(.headline)
                    Text("From your recent sessions").font(.caption).foregroundStyle(.secondary)
                    Text(notes[0]).font(.callout).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(notes.dropFirst().prefix(2)), id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(note).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            panel {
                Text("How to improve").font(.headline)
                Text(improve).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let action { actionButton(action) }
            }
        }
    }

    // MARK: - CEFR copy

    private func canDo(_ l: CEFRLevel) -> String {
        switch l {
        case .a1: return explain("Simple words and phrases about immediate, familiar things.")
        case .a2: return explain("Everyday topics in simple terms — routines, plans, basic needs.")
        case .b1: return explain("Familiar topics fluently enough to get by, and tell a simple story.")
        case .b2: return explain("Clear, detailed talk on many topics, including some abstract ones.")
        case .c1: return explain("Fluent, flexible, and precise — even on complex topics.")
        case .c2: return explain("Effortless and nuanced, close to native.")
        }
    }

    /// Where a tip's advice is actually carried out. Progress MEASURES; the
    /// doing lives in Practice and Talk — so an action always leaves this tab
    /// (staged route, the same handoff Home's Practice row uses) instead of
    /// pushing a second copy of a Practice page underneath Progress.
    private struct TipAction {
        let title: String
        let icon: String
        let run: () -> Void
    }

    private struct FocusTip {
        let icon: String
        let text: String
        let action: TipAction?
    }

    /// The words of that band, in the notebook — the tip names a level, this
    /// opens exactly that level rather than wherever the filter was left.
    private func seeWordsAction(at level: CEFRLevel) -> TipAction {
        TipAction(title: chrome("See \(level.rawValue.uppercased()) words"),
                  icon: "text.book.closed") {
            appState.focusVocabLevel = level
            appState.pendingPracticeRoute = .vocabulary(word: nil)
        }
    }

    /// The due deck — the cards are built from the learner's own slips.
    private var reviewSlipsAction: TipAction {
        TipAction(title: chrome("Review your slips"), icon: "checkmark.seal") {
            appState.pendingPracticeRoute = .review
        }
    }

    /// Pace and turn length only move by speaking, so the door is a call.
    /// Staging it brings the Talk tab along and passes the billing gate there.
    private var startTalkAction: TipAction {
        TipAction(title: chrome("Start a talk"), icon: "waveform") {
            appState.pendingFreeTalk = true
        }
    }

    /// Compact link under a tip line — small so the measurement stays the
    /// panel's subject and the way out is an offer, not a call to action.
    private func tipLink(_ action: TipAction) -> some View {
        Button(action: action.run) {
            Label(action.title, systemImage: action.icon)
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Full-width version, for a panel whose whole subject IS the advice
    /// ("How to improve", "How to level up") — there the way out is the point.
    private func actionButton(_ action: TipAction) -> some View {
        Button(action: action.run) {
            Label(action.title, systemImage: action.icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 2)
    }

    /// The band just above the measured vocabulary level — where the words
    /// that would actually move this number live. Before anything is measured
    /// it follows the learner's own level, and it stops at the top band.
    private var vocabNextBand: CEFRLevel {
        let base = vocabLevel ?? appState.proficiency
        return nextLevel(base) ?? base
    }

    /// Concrete next-step focuses, derived from the SAME per-axis measurements
    /// the assessment sheet shows: only axes currently measuring below the
    /// target level appear, each anchored to its live number. Unmeasured axes
    /// stay silent — no guessing. Capped at 3 so it reads as focus, not a
    /// checklist.
    private func focusTips(toward next: CEFRLevel) -> [FocusTip] {
        let targetRank = CoreVocabulary.levelRank(next)
        func lags(_ lv: CEFRLevel?) -> Bool {
            guard let lv else { return false }
            return CoreVocabulary.levelRank(lv) < targetRank
        }
        var tips: [FocusTip] = []
        if lags(vocabLevel) {
            tips.append(FocusTip(icon: "text.book.closed",
                                 text: explain("Use more \(next.rawValue.uppercased())-level words in your talks."),
                                 action: seeWordsAction(at: next)))
        }
        if lags(grammarCEFR) {
            tips.append(FocusTip(icon: "checkmark.seal",
                                 text: String(format: explain("You're at %.1f verified slips per 100 words%@."),
                                              slipsPer100Words, grammarTargetHint),
                                 action: reviewSlipsAction))
        }
        if lags(fluencyCEFR) {
            tips.append(FocusTip(icon: "gauge.with.needle",
                                 text: explain("Your pace is \(effectivePace) words/min — talk more often and a little longer; longer turns build flow."),
                                 action: startTalkAction))
        }
        if lags(expressionCEFR) {
            tips.append(FocusTip(icon: "text.bubble",
                                 text: explain("Your turns average \(wordsPerTurn) words — add detail: how things felt, not just what happened."),
                                 action: startTalkAction))
        }
        if tips.isEmpty {
            tips.append(FocusTip(icon: "checkmark.circle",
                                 text: explain("Every measured skill already reads at \(next.rawValue.uppercased()) or above — keep talking and the pooled read will catch up."),
                                 action: nil))
        }
        // Two lagging axes can want the same destination (pace and turn length
        // are both fixed by talking) — the second one keeps its line and drops
        // the duplicate button rather than showing the same door twice.
        var offered = Set<String>()
        let deduped = tips.map { tip -> FocusTip in
            guard let a = tip.action else { return tip }
            return offered.insert(a.title).inserted ? tip
                 : FocusTip(icon: tip.icon, text: tip.text, action: nil)
        }
        return Array(deduped.prefix(3))
    }

    private func nextLevel(_ l: CEFRLevel) -> CEFRLevel? {
        let all = CEFRLevel.allCases
        guard let i = all.firstIndex(of: l), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    /// Preferred pace signal: articulation rate (voiced speech only); falls
    /// back to wall-clock wpm for old sessions without mic-energy stats.
    private var effectivePace: Int { articulationWpm > 0 ? articulationWpm : wpm }

    private var fluencyBand: String {
        guard effectivePace > 0 else { return "—" }
        // Articulation rate runs ~20-40% higher than wall-clock wpm (pauses
        // removed), so the bands shift up when it's available.
        let (low, mid, high) = articulationWpm > 0 ? (90, 130, 170) : (70, 110, 150)
        switch effectivePace {
        case ..<low:      return "Finding your flow"
        case low..<mid:   return "Conversational"
        case mid..<high:  return "Fluent"
        default:          return "Very fluent"
        }
    }

    // MARK: - Building blocks

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Data

    /// The main-actor-only reads the pass can't do for itself: `VocabStore`
    /// and `PracticeLog` keep their state on this actor, and AppState's
    /// arrays are the view's own truth for the moment the pass started.
    private struct ReloadInput {
        var now: Date
        /// The last 14 days, oldest first, each with its effort-log row.
        var days: [(day: Date, log: PracticeLog.Day?)]
        var drillCards: [DrillCard]
        var shadowAttempts: [ShadowAttempt]
        var weeklyReports: [WeeklyReport]
        /// Words used inside `vocabWindowDays` — the CURRENT vocabulary.
        var usedWordsRecent: [String]
        /// First-use date of every graded word ever said — the growth curve.
        var vocabFirstUses: [Date]
    }

    /// One finished pass, in one value, so it lands in a single update
    /// instead of thirty separate ones.
    private struct Loaded {
        var dashboard: PracticeStats.Snapshot
        var dueCount = 0
        var carryover = PracticeStats.CarryoverSummary()
        var dailyEffort: [DayEffort] = []
        var weekReps = 0
        var daysActiveThisWeek = 0
        var shadowTrend: PracticeStats.ShadowTrend?
        var avgShadowScore = 0
        var perLevel: [CEFRLevel: Int] = [:]
        var usedTotal = 0
        var vocabLevel: CEFRLevel?
        var scoredCount = 0
        var totalSpeakingMinutes = 0
        var wpm = 0
        var articulationWpm = 0
        var pausesPerMin = 0.0
        var talkMinutes = 0
        var wordsPerTurn = 0
        var grammarScore = 0
        var slipsPer100Words = 0.0
        var fluencyTrend: [TrendPoint] = []
        var grammarTrend: [TrendPoint] = []
        var expressionTrend: [TrendPoint] = []
        var vocabTrend: [TrendPoint] = []
        var aiLevel: CEFRLevel?
        var levelHistory: [LevelPoint] = []
        var reportUnlock: WeeklyReportEngine.UnlockState
        var notesByDim: [Dim: [String]] = [:]
    }

    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task { await runReload() }
    }

    /// One refresh: read what only this actor can read, walk the archive OFF
    /// it, apply.
    ///
    /// The walk is heavy — several passes over every ended session, plus a
    /// scorecard recomputation per talk — and it used to run synchronously
    /// inside `onAppear`. onAppear fires after the first frame, so the tab
    /// opened on the still-empty initial state and a learner with a year of
    /// talks read "no assessment yet · 0/10 min" until the walk finished;
    /// leaving for another tab and coming back was the only thing that looked
    /// like a fix, because by then the state was filled.
    @MainActor
    private func runReload() async {
        // The notebook first: it ingests any turns it hasn't seen (a no-op
        // once a talk has been counted), and the vocabulary level below is
        // read off it.
        vocab.backfillFromSessions()

        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let input = ReloadInput(
            now: now,
            days: (0..<14).reversed().compactMap { offset in
                cal.date(byAdding: .day, value: -offset, to: todayStart)
                    .map { ($0, PracticeLog.shared.day($0)) }
            },
            drillCards: DrillStore.shared.load(),
            shadowAttempts: appState.shadowAttempts,
            weeklyReports: appState.weeklyReports,
            usedWordsRecent: vocab.usedWords(withinDays: Self.vocabWindowDays),
            vocabFirstUses: vocab.records
                .filter { $0.value.state == .used && CoreVocabulary.level(of: $0.key) != nil }
                .map(\.value.firstAt))

        let result = await Task.detached(priority: .userInitiated) {
            Self.compute(input)
        }.value
        guard !Task.isCancelled else { return }

        dashboard = result.dashboard
        dueCount = result.dueCount
        carryover = result.carryover
        dailyEffort = result.dailyEffort
        weekReps = result.weekReps
        daysActiveThisWeek = result.daysActiveThisWeek
        shadowTrend = result.shadowTrend
        avgShadowScore = result.avgShadowScore
        perLevel = result.perLevel
        usedTotal = result.usedTotal
        vocabLevel = result.vocabLevel
        scoredCount = result.scoredCount
        totalSpeakingMinutes = result.totalSpeakingMinutes
        wpm = result.wpm
        articulationWpm = result.articulationWpm
        pausesPerMin = result.pausesPerMin
        talkMinutes = result.talkMinutes
        wordsPerTurn = result.wordsPerTurn
        grammarScore = result.grammarScore
        slipsPer100Words = result.slipsPer100Words
        fluencyTrend = result.fluencyTrend
        grammarTrend = result.grammarTrend
        expressionTrend = result.expressionTrend
        vocabTrend = result.vocabTrend
        aiLevel = result.aiLevel
        levelHistory = result.levelHistory
        reportUnlock = result.reportUnlock
        notesByDim = result.notesByDim
        loaded = true

        // If a read is due, kick it off right here — for the FIRST level and
        // for re-assessments alike. Otherwise "ready" would sit as a spinner
        // until the next conversation happened to end.
        if case .ready = result.reportUnlock {
            appState.maybeGenerateWeeklyReport()
        }

        await loadMaterial()
    }

    /// Whole-library mastery. Talk books DERIVE their material (nothing is
    /// persisted), so this walks `TalkCurriculum` for every finished talk —
    /// and `TalkCurriculum` reads the notebook, so it's stuck on this actor.
    /// It yields every few books instead of holding the frame for the length
    /// of the archive, and it runs after the pages are already drawn.
    @MainActor
    private func loadMaterial() async {
        let proficiency = appState.proficiency
        let attempts = appState.shadowAttempts
        let drillCards = DrillStore.shared.load()
        var mastered = 0, total = 0
        let ended = SessionStore.shared.load().filter { $0.endedAt != nil }
        for (index, session) in ended.enumerated() {
            if index > 0, index.isMultiple(of: 8) {
                await Task.yield()
                if Task.isCancelled { return }
            }
            let snap = TalkCurriculum.build(session: session,
                                            proficiency: proficiency,
                                            shadowAttempts: attempts,
                                            drillCards: drillCards)
            mastered += snap.masteredCount
            total += snap.totalCount
        }
        for sc in appState.scenarios {
            if let c = sc.curriculum {
                mastered += c.masteredCount
                total += c.totalCount
            }
        }
        material = (mastered, total)
    }

    /// Every number on every page, computed from `input` and the thread-safe
    /// stores. Nothing here may touch main-actor state — that's what
    /// `ReloadInput` is for.
    private static func compute(_ input: ReloadInput) -> Loaded {
        let effortCal = Calendar.current
        let effortNow = input.now
        let drillCards = input.drillCards

        var out = Loaded(dashboard: PracticeStats.snapshot(),
                         reportUnlock: .lockedFirst(secondsAccumulated: 0,
                                                    secondsRequired: WeeklyReportEngine.firstReportMinSeconds))
        out.dueCount = drillCards.filter { $0.nextReviewAt <= effortNow }.count

        // --- Effort: PracticeLog going forward; shadow-attempt history and
        // card review dates backfill the days before the log existed. ---
        let allEnded = SessionStore.shared.load().filter { $0.endedAt != nil }
        out.carryover = PracticeStats.carryoverSummary(sessions: allEnded)

        var effort: [DayEffort] = []
        for (d, log) in input.days {
            // Log going forward; attempt history / card review dates backfill
            // the days before the log existed (same policy as before).
            let shadowed = input.shadowAttempts.filter { effortCal.isDate($0.createdAt, inSameDayAs: d) }.count
            let reviewed = drillCards.filter { c in
                c.lastReviewedAt.map { effortCal.isDate($0, inSameDayAs: d) } ?? false
            }.count
            let daySessions = allEnded.filter { effortCal.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: d) }
            let userTurns = daySessions.reduce(0) { acc, s in
                acc + s.turns.filter { $0.role == .user }.count
            }
            let speakMs = daySessions.reduce(0) { acc, s in
                acc + s.turns.filter { $0.role == .user }.reduce(0) { $0 + $1.durationMs }
            }
            effort.append(DayEffort(day: d,
                                    talkTurns: userTurns,
                                    shadowReps: max(log?.shadowReps ?? 0, shadowed),
                                    drillReps: max(log?.drillReps ?? 0, reviewed),
                                    talkMinutes: Double(speakMs) / 60000.0))
        }
        out.dailyEffort = effort
        // "Reps" stays what it always meant — review work (shadow + drill),
        // talk time is counted in minutes, not reps.
        out.weekReps = effort.suffix(7).reduce(0) { $0 + $1.shadowReps + $1.drillReps }
        out.daysActiveThisWeek = effort.suffix(7).filter { $0.shadowReps + $0.drillReps > 0 }.count
        out.shadowTrend = PracticeStats.shadowTrend(attempts: input.shadowAttempts, now: effortNow)
        let recentScores = input.shadowAttempts
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10).map(\.matchScore)
        out.avgShadowScore = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / recentScores.count

        // --- Objective vocabulary CEFR estimate (from words actually used) ---
        // CURRENT level = words used in the recent window, not lifetime — a
        // C1 word said once a year ago isn't evidence of today's vocabulary.
        // The cumulative growth chart below still uses every word ever.
        var counts: [CEFRLevel: Int] = [:]
        var total = 0
        for word in input.usedWordsRecent {
            if let lv = CoreVocabulary.level(of: word) {
                counts[lv, default: 0] += 1
                total += 1
            }
        }
        out.perLevel = counts
        out.usedTotal = total
        // Estimated level = highest band where the user productively uses
        // enough distinct words. The bar RISES with the level — six A2 words
        // are decent evidence, but six lucky C1 words (song lyrics, one topic)
        // shouldn't mint a C1 vocabulary. Needs a baseline of words first.
        func threshold(for lv: CEFRLevel) -> Int {
            switch lv {
            case .a1, .a2: return 6
            case .b1:      return 8
            case .b2:      return 10
            case .c1:      return 12
            case .c2:      return 15
            }
        }
        if total >= 15 {
            var est: CEFRLevel?
            for lv in CEFRLevel.allCases where (counts[lv] ?? 0) >= threshold(for: lv) { est = lv }
            out.vocabLevel = est ?? .a1
        } else {
            out.vocabLevel = nil
        }

        // --- Measured signals from recent sessions' turns ---
        // Archived talks are out: the user shelved them, so they stop counting
        // as score/assessment evidence (unarchiving brings them back). The
        // activity/effort panels above still count them — time spoken is real.
        let scoredSessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil && $0.summary?.scorecard != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        out.scoredCount = scoredSessions.count

        // Accumulated speaking time across every analyzed session — gates the
        // overall level so it's grounded in ~10 min of talk, not one session.
        let totalSpeakSecs = scoredSessions.reduce(0.0) { acc, sess in
            acc + sess.turns.filter { $0.role == .user }
                .reduce(0.0) { $0 + Double($1.durationMs) / 1000.0 }
        }
        out.totalSpeakingMinutes = Int(totalSpeakSecs / 60.0)

        let recent = Array(scoredSessions.prefix(5))
        let mets = recent.map { ScorecardMetrics.compute(turns: $0.turns) }
        func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
        out.wpm = Int(mean(mets.map(\.wordsPerMinute).filter { $0 > 0 }).rounded())
        out.articulationWpm = Int(mean(mets.map(\.articulationRate).filter { $0 > 0 }).rounded())
        out.pausesPerMin = mean(mets.map(\.pausesPerMinute).filter { $0 > 0 })
        out.talkMinutes = Int((mean(mets.map(\.totalUserSpeakingSeconds)) / 60).rounded())
        out.wordsPerTurn = Int(mean(mets.map(\.avgWordsPerUserTurn)).rounded())
        // Grammar = the per-talk scorecard score (anchored on verified slips),
        // NOT suggestionRate — that also counts style rephrases and STT noise,
        // so it saturates and contradicts the score each talk shows.
        let recentGrammar = recent
            .compactMap { $0.summary?.scorecard?.grammar.score }
            .filter { (0...100).contains($0) }
            .map(Double.init)
        out.grammarScore = Int(mean(recentGrammar).rounded())
        // Slip density over the SAME window the latest assessment judged —
        // the ≈Grammar band must cite the same number as the verdict's
        // rationale. A recent-5 window can straddle a different set of talks
        // and flip the band one panel below the rationale that contradicts
        // it. No assessment yet → the recent talks.
        let assessments = input.weeklyReports
            .filter { $0.cefrLevel != nil }
            .sorted { $0.generatedAt > $1.generatedAt }
        let densitySessions: [Session]
        if let latest = assessments.first {
            let windowStart = assessments.dropFirst().first?.periodEnd ?? .distantPast
            let window = scoredSessions.filter {
                let d = $0.endedAt ?? $0.startedAt
                return d > windowStart && d <= latest.periodEnd
            }
            densitySessions = window.isEmpty ? Array(recent) : window
        } else {
            densitySessions = Array(recent)
        }
        let densityMets = densitySessions.map { ScorecardMetrics.compute(turns: $0.turns) }
        let slips = densitySessions.reduce(0) { $0 + ($1.summary?.grammarIssues.count ?? 0) }
        let words = densityMets.reduce(0) { $0 + $1.userWordCount }
        out.slipsPer100Words = words > 0 ? Double(slips) / Double(words) * 100 : 0

        // --- Per-skill trends: one point per analyzed talk, oldest first.
        // The SAME deterministic measurements as the headline numbers above,
        // just not averaged away. ---
        var fT: [TrendPoint] = [], gT: [TrendPoint] = [], eT: [TrendPoint] = []
        for s in scoredSessions.prefix(30).reversed() {
            let m = ScorecardMetrics.compute(turns: s.turns)
            let date = s.endedAt ?? s.startedAt
            let pace = m.articulationRate > 0 ? m.articulationRate : m.wordsPerMinute
            if pace > 0 { fT.append(TrendPoint(date: date, value: pace)) }
            // One point per talk: verified slip density — the same currency
            // as the page's ≈band and the assessment's rationale. Legacy
            // sessions predating slip capture decode as zero slips; a zero
            // with a mediocre grammar score is missing data, not clean
            // speech — skip those, keep genuinely clean talks.
            if let summary = s.summary, m.userWordCount > 0 {
                let slips = summary.grammarIssues.count
                if slips > 0 || (summary.scorecard?.grammar.score ?? 0) >= 90 {
                    gT.append(TrendPoint(date: date,
                                         value: Double(slips) / Double(m.userWordCount) * 100))
                }
            }
            if m.avgWordsPerUserTurn > 0 {
                eT.append(TrendPoint(date: date, value: m.avgWordsPerUserTurn))
            }
        }
        out.fluencyTrend = fT
        out.grammarTrend = gT
        out.expressionTrend = eT

        // Vocabulary growth: cumulative distinct graded words, bucketed by
        // the day each word was FIRST used (VocabStore keeps firstAt).
        var cumulative = 0
        out.vocabTrend = Dictionary(grouping: input.vocabFirstUses,
                                    by: { effortCal.startOfDay(for: $0) })
            .sorted { $0.key < $1.key }
            .map { day, firsts in
                cumulative += firsts.count
                return TrendPoint(date: day, value: Double(cumulative))
            }

        let cards = scoredSessions.compactMap { $0.summary?.scorecard }

        // --- Overall level ---
        // ONLY the weekly report's pooled read (one judgment over a whole
        // window's speech). Per-session reads are too noisy to publish — if
        // the sample isn't big enough yet, we show "building", not a number.
        out.aiLevel = input.weeklyReports
            .sorted { $0.generatedAt > $1.generatedAt }
            .compactMap { $0.cefrLevel.flatMap { CEFRLevel(rawValue: $0) } }
            .first

        // Every read's level, oldest first — the level-over-time chart.
        out.levelHistory = input.weeklyReports
            .compactMap { r in
                r.cefrLevel.flatMap { CEFRLevel(rawValue: $0) }.map { lv in
                    LevelPoint(date: r.generatedAt,
                               rank: CoreVocabulary.levelRank(lv),
                               label: lv.rawValue.uppercased())
                }
            }
            .sorted { $0.date < $1.date }

        // Real unlock state for the building panel. Same archived-out filter
        // as AppState.maybeGenerateWeeklyReport, so the unlock bar and the
        // actual generation never disagree. (The caller kicks generation off
        // when this comes back `.ready` — waiting for the next conversation
        // to end would leave the user staring at a full progress bar with
        // nothing happening.)
        let endedSessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil }
        out.reportUnlock = WeeklyReportEngine.unlockState(
            endedSessions: endedSessions,
            lastReport: input.weeklyReports.first
        )

        // --- Qualitative coaching notes (LLM) per dimension ---
        func dimNotes(_ get: (SessionScorecard) -> String) -> [String] {
            Array(cards.prefix(3).map(get).filter { !$0.isEmpty })
        }
        out.notesByDim = [
            .grammar:        dimNotes { $0.grammar.note },
            .fluency:        dimNotes { $0.fluency.note },
            .expressiveness: dimNotes { $0.expressiveness.note }
        ]
        return out
    }
}

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
                if scoredCount == 0 {
                    ScrollView {
                        emptyState
                            .padding(.top, 4)
                            .padding(.bottom, 28)
                    }
                } else {
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
        switch dim {
        case .overall:        overallContent
        case .vocabulary:     vocabularyContent
        case .fluency:        fluencyContent
        case .grammar:        grammarContent
        case .expressiveness: expressivenessContent
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
                    ForEach(focusTips(toward: next), id: \.text) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: tip.icon)
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            Text(tip.text).font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Analyzing your week…")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                // reload() already kicked off generation — this shows only in
                // the brief gap before `weeklyReportGenerating` flips true.
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ready — assessing your level now…")
                        .font(.callout).foregroundStyle(.secondary)
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
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ready — re-assessing your level now…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .lockedFirst:
                // Can't happen once a level exists; nothing to show.
                EmptyView()
            }
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
                } footer: {
                    // Accountability: the exact measured evidence the judge
                    // received, verbatim — a surprising verdict can be checked.
                    if let ev = latestAssessment?.levelEvidence, !ev.isEmpty {
                        Text("Evidence the assessment received:\n" + ev)
                            .font(.caption2.monospaced())
                    }
                }
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
                Text(explain("Discover and use words you don't reach for yet — Practice → Vocabulary highlights the ones at and above your level."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            panel {
                HStack(alignment: .firstTextBaseline) {
                    Text("Expressions you've used").font(.headline)
                    Spacer()
                    Text("\(vocab.expressionCount)")
                        .font(.headline).foregroundStyle(.tint).monospacedDigit()
                }
                Text(explain("Multi-word phrases you actually said in your talks, collected automatically — browse them under Practice → Expressions."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            action: nil,
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
            improve: "Run your review cards under Practice — they're built from your own slips and target exactly these.",
            action: nil,
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
        return String(format: " — get under %.1f and this reads ≈%@", t, next.rawValue.uppercased())
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
            action: nil,
            trend: expressionTrend,
            trendCaption: "Average words per turn — one point per talk. Background zones are the ≈CEFR bands.",
            trendBands: Self.expressionBands
        )
    }

    private struct DimAction { let title: String; let icon: String; let destination: AnyView }

    /// A dimension's trend over time — the same measurement as the page's
    /// headline number, one point per analyzed talk.
    @ViewBuilder
    private func trendPanel(_ trend: [TrendPoint], unit: String, caption: String,
                            target: Double? = nil,
                            bands: [BandSpec] = []) -> some View {
        if trend.count >= 2 {
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
            panel {
                Text("Trend").font(.headline)
                Chart {
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
                            .foregroundStyle(.tint)
                        PointMark(x: .value("Talk", p.date), y: .value(unit, p.value))
                            .foregroundStyle(.tint)
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
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func measuredContent(dim: Dim, big: String, bigUnit: String, band: String?,
                                 measuredLine: String?, measures: String, improve: String,
                                 action: DimAction?, trend: [TrendPoint] = [],
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
                if let action {
                    NavigationLink(destination: action.destination) {
                        Label(action.title, systemImage: action.icon)
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 2)
                }
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

    /// Concrete next-step focuses, derived from the SAME per-axis measurements
    /// the assessment sheet shows: only axes currently measuring below the
    /// target level appear, each anchored to its live number. Unmeasured axes
    /// stay silent — no guessing. Capped at 3 so it reads as focus, not a
    /// checklist.
    private func focusTips(toward next: CEFRLevel) -> [(icon: String, text: String)] {
        let targetRank = CoreVocabulary.levelRank(next)
        func lags(_ lv: CEFRLevel?) -> Bool {
            guard let lv else { return false }
            return CoreVocabulary.levelRank(lv) < targetRank
        }
        var tips: [(icon: String, text: String)] = []
        if lags(vocabLevel) {
            tips.append((icon: "text.book.closed",
                         text: "Use more \(next.rawValue.uppercased())-level words in your talks — Practice → Vocabulary highlights them."))
        }
        if lags(grammarCEFR) {
            tips.append((icon: "checkmark.seal",
                         text: String(format: "You're at %.1f verified slips per 100 words%@ — your review cards under Practice target exactly these.",
                                      slipsPer100Words, grammarTargetHint)))
        }
        if lags(fluencyCEFR) {
            tips.append((icon: "gauge.with.needle",
                         text: "Your pace is \(effectivePace) words/min — talk more often and a little longer; longer turns build flow."))
        }
        if lags(expressionCEFR) {
            tips.append((icon: "text.bubble",
                         text: "Your turns average \(wordsPerTurn) words — add detail: how things felt, not just what happened."))
        }
        if tips.isEmpty {
            tips.append((icon: "checkmark.circle",
                         text: "Every measured skill already reads at \(next.rawValue.uppercased()) or above — keep talking and the pooled read will catch up."))
        }
        return Array(tips.prefix(3))
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No progress yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text(explain("Have a few conversations and I'll estimate your level and break down how your \(LanguageCatalog.englishName(appState.targetLanguage)) is developing."))
        }
    }

    // MARK: - Data

    private func reload() {
        dashboard = PracticeStats.snapshot()
        let drillCards = DrillStore.shared.load()
        dueCount = drillCards.filter { $0.nextReviewAt <= Date() }.count
        vocab.backfillFromSessions()

        // --- Effort: PracticeLog going forward; shadow-attempt history and
        // card review dates backfill the days before the log existed. ---
        let effortCal = Calendar.current
        let effortNow = Date()
        let todayStart = effortCal.startOfDay(for: effortNow)
        let allEnded = SessionStore.shared.load().filter { $0.endedAt != nil }
        carryover = PracticeStats.carryoverSummary(sessions: allEnded)

        // Whole-library mastery. Talk books DERIVE their material (nothing is
        // persisted), so this walks TalkCurriculum for every finished talk —
        // off the first-paint path for that reason.
        let scenarios = appState.scenarios
        let proficiency = appState.proficiency
        let attempts = appState.shadowAttempts
        Task { @MainActor in
            var mastered = 0, total = 0
            for session in allEnded {
                let snap = TalkCurriculum.build(session: session,
                                                proficiency: proficiency,
                                                shadowAttempts: attempts)
                mastered += snap.masteredCount
                total += snap.totalCount
            }
            for sc in scenarios {
                if let c = sc.curriculum {
                    mastered += c.masteredCount
                    total += c.totalCount
                }
            }
            material = (mastered, total)
        }
        var effort: [DayEffort] = []
        for offset in (0..<14).reversed() {
            guard let d = effortCal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let log = PracticeLog.shared.day(d)
            // Log going forward; attempt history / card review dates backfill
            // the days before the log existed (same policy as before).
            let shadowed = appState.shadowAttempts.filter { effortCal.isDate($0.createdAt, inSameDayAs: d) }.count
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
        dailyEffort = effort
        // "Reps" stays what it always meant — review work (shadow + drill),
        // talk time is counted in minutes, not reps.
        weekReps = effort.suffix(7).reduce(0) { $0 + $1.shadowReps + $1.drillReps }
        daysActiveThisWeek = effort.suffix(7).filter { $0.shadowReps + $0.drillReps > 0 }.count
        shadowTrend = PracticeStats.shadowTrend(attempts: appState.shadowAttempts, now: effortNow)
        let recentScores = appState.shadowAttempts
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10).map(\.matchScore)
        avgShadowScore = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / recentScores.count

        // --- Objective vocabulary CEFR estimate (from words actually used) ---
        // CURRENT level = words used in the recent window, not lifetime — a
        // C1 word said once a year ago isn't evidence of today's vocabulary.
        // The cumulative growth chart below still uses every word ever.
        var counts: [CEFRLevel: Int] = [:]
        var total = 0
        for word in vocab.usedWords(withinDays: Self.vocabWindowDays) {
            if let lv = CoreVocabulary.level(of: word) {
                counts[lv, default: 0] += 1
                total += 1
            }
        }
        perLevel = counts
        usedTotal = total
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
            vocabLevel = est ?? .a1
        } else {
            vocabLevel = nil
        }

        // --- Measured signals from recent sessions' turns ---
        // Archived talks are out: the user shelved them, so they stop counting
        // as score/assessment evidence (unarchiving brings them back). The
        // activity/effort panels above still count them — time spoken is real.
        let scoredSessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil && $0.summary?.scorecard != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        scoredCount = scoredSessions.count

        // Accumulated speaking time across every analyzed session — gates the
        // overall level so it's grounded in ~10 min of talk, not one session.
        let totalSpeakSecs = scoredSessions.reduce(0.0) { acc, sess in
            acc + sess.turns.filter { $0.role == .user }
                .reduce(0.0) { $0 + Double($1.durationMs) / 1000.0 }
        }
        totalSpeakingMinutes = Int(totalSpeakSecs / 60.0)

        let recent = Array(scoredSessions.prefix(5))
        let mets = recent.map { ScorecardMetrics.compute(turns: $0.turns) }
        func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
        wpm = Int(mean(mets.map(\.wordsPerMinute).filter { $0 > 0 }).rounded())
        articulationWpm = Int(mean(mets.map(\.articulationRate).filter { $0 > 0 }).rounded())
        pausesPerMin = mean(mets.map(\.pausesPerMinute).filter { $0 > 0 })
        talkMinutes = Int((mean(mets.map(\.totalUserSpeakingSeconds)) / 60).rounded())
        wordsPerTurn = Int(mean(mets.map(\.avgWordsPerUserTurn)).rounded())
        // Grammar = the per-talk scorecard score (anchored on verified slips),
        // NOT suggestionRate — that also counts style rephrases and STT noise,
        // so it saturates and contradicts the score each talk shows.
        let recentGrammar = recent
            .compactMap { $0.summary?.scorecard?.grammar.score }
            .filter { (0...100).contains($0) }
            .map(Double.init)
        grammarScore = Int(mean(recentGrammar).rounded())
        // Slip density over the SAME window the latest assessment judged —
        // the ≈Grammar band must cite the same number as the verdict's
        // rationale. A recent-5 window can straddle a different set of talks
        // and flip the band one panel below the rationale that contradicts
        // it. No assessment yet → the recent talks.
        let assessments = appState.weeklyReports
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
        slipsPer100Words = words > 0 ? Double(slips) / Double(words) * 100 : 0

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
        fluencyTrend = fT
        grammarTrend = gT
        expressionTrend = eT

        // Vocabulary growth: cumulative distinct graded words, bucketed by
        // the day each word was FIRST used (VocabStore keeps firstAt).
        var cumulative = 0
        vocabTrend = Dictionary(
            grouping: vocab.records
                .filter { $0.value.state == .used && CoreVocabulary.level(of: $0.key) != nil }
                .map(\.value.firstAt),
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
        aiLevel = appState.weeklyReports
            .sorted { $0.generatedAt > $1.generatedAt }
            .compactMap { $0.cefrLevel.flatMap { CEFRLevel(rawValue: $0) } }
            .first

        // Every read's level, oldest first — the level-over-time chart.
        levelHistory = appState.weeklyReports
            .compactMap { r in
                r.cefrLevel.flatMap { CEFRLevel(rawValue: $0) }.map { lv in
                    LevelPoint(date: r.generatedAt,
                               rank: CoreVocabulary.levelRank(lv),
                               label: lv.rawValue.uppercased())
                }
            }
            .sorted { $0.date < $1.date }

        // Real unlock state for the building panel — and if the next read is
        // already unlocked, kick it off RIGHT HERE. Waiting for the next
        // conversation to end (the only other trigger) would leave the user
        // staring at a full progress bar with nothing happening.
        // Same archived-out filter as AppState.maybeGenerateWeeklyReport, so
        // the unlock bar and the actual generation never disagree.
        let endedSessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil }
        reportUnlock = WeeklyReportEngine.unlockState(
            endedSessions: endedSessions,
            lastReport: appState.weeklyReports.first
        )
        // If a read is due, kick it off right here — for the FIRST level and
        // for re-assessments alike. Otherwise "ready" would sit as a spinner
        // until the next conversation happened to end.
        if case .ready = reportUnlock {
            appState.maybeGenerateWeeklyReport()
        }

        // --- Qualitative coaching notes (LLM) per dimension ---
        func dimNotes(_ get: (SessionScorecard) -> String) -> [String] {
            Array(cards.prefix(3).map(get).filter { !$0.isEmpty })
        }
        notesByDim = [
            .grammar:        dimNotes { $0.grammar.note },
            .fluency:        dimNotes { $0.fluency.note },
            .expressiveness: dimNotes { $0.expressiveness.note }
        ]
    }
}

import SwiftUI

/// Progress — expressed in CEFR (A1–C2) so it actually means something, not an
/// arbitrary 0–100. Your level is ESTIMATED from the words you actually use
/// (each word is CEFR-graded), which is a real measurement, not an LLM opinion.
/// The other skills lean on measured numbers (WPM, shadow accuracy, error rate)
/// plus the analyzer's qualitative "what to work on" notes.
struct ProgressTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var vocab = VocabStore.shared

    // Optional because it doubles as the pager's scrollPosition binding.
    @State private var selected: Dim? = .overall
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
    @State private var corrPer10 = 0.0
    @State private var shadowAccuracy = 0
    @State private var shadowAttempts = 0
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
    /// The REAL unlock state of the next weekly read — drives the building
    /// panel so it shows the actual conditions (days + new talk), never a
    /// full progress bar with nothing happening behind it.
    @State private var reportUnlock: WeeklyReportEngine.UnlockState =
        .lockedFirst(secondsAccumulated: 0,
                     secondsRequired: WeeklyReportEngine.firstReportMinSeconds)

    enum Dim: String, CaseIterable, Hashable {
        case overall, vocabulary, grammar, fluency, expressiveness, pronunciation
        // "Pronunciation" oversold what's measured (STT text match from
        // shadow reps) — label it what it is.
        var title: String {
            switch self {
            case .overall:       return "Overall"
            case .pronunciation: return "Shadowing"
            default:             return rawValue.capitalized
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
                    .toolbarBackground(.hidden, for: .navigationBar)
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
        case .pronunciation:  pronunciationContent
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

    /// Minimum shadow attempts before the Shadowing page/row shows a number —
    /// an average of one or two reps isn't a statistic, it's an anecdote.
    private static let minShadowAttempts = 5

    private var availableDims: [Dim] {
        var out: [Dim] = [.overall, .vocabulary, .grammar, .fluency, .expressiveness]
        if shadowAttempts >= Self.minShadowAttempts { out.append(.pronunciation) }
        return out
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
                    Text(lv.rawValue.uppercased())
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.tint)
                    // Korean target: learners orient by TOPIK, so show the
                    // official CEFR↔TOPIK equivalence under the big number.
                    if LanguageCatalog.levelLabel(lv, target: appState.targetLanguage)
                        != lv.rawValue.uppercased() {
                        Text(LanguageCatalog.levelLabel(lv, target: appState.targetLanguage))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(canDo(lv)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("Assessed from \(totalSpeakingMinutes) min of conversation, pooled in your weekly read — vocabulary, grammar, fluency and expression together.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Building your level").font(.title.bold())
                    // The recipe made visible, equalizer-style: one bar per
                    // measured ingredient, lit LED blocks = that axis's CEFR
                    // band. A weak axis is a visibly shorter column.
                    LevelEqualizer(bars: equalizerBars)
                        .padding(.top, 8)
                    Text("Vocabulary is graded from the words you actually use; ≈ levels are read from your pace, corrections and turn length.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    buildingStatus
                }
            }

            panel {
                Text("Across skills").font(.headline)
                skillRow(.vocabulary, value: vocabLevel.map { $0.rawValue.uppercased() } ?? "—")
                skillRow(.fluency, value: fluencyBand)
                if shadowAttempts >= Self.minShadowAttempts {
                    skillRow(.pronunciation, value: accuracyBand)
                }
                skillRow(.grammar, value: corrPer10 > 0 ? String(format: "%.1f/10 turns", corrPer10) : "—")
            }

            if let lv = aiLevel, let next = nextLevel(lv) {
                panel {
                    Text("To reach \(next.rawValue.uppercased())").font(.headline)
                    Text(canDo(next)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Measurement tab stays measurement-only: the doing
                    // (vocabulary, drills, shadowing) lives in Practice.
                    Text("Start using more \(next.rawValue.uppercased())-level words in your talks — Practice → Vocabulary highlights them.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }

            consistencyPanel

            panel {
                Text("This week's read").font(.headline)
                WeeklyReportView()
            }
        }
    }

    // MARK: - Per-axis CEFR estimates for the ring
    //
    // ONE rule for every arc: fill = the axis's CEFR position, full = C2.
    // Vocabulary is graded directly (word-list lookup). The other three are
    // deterministic proxies mapped to CEFR bands — real measurements, but
    // heuristic mappings, so the UI marks them "≈".

    /// Articulation pace → CEFR band. Speech-rate bands are a recognized
    /// (if rough) proficiency proxy; boundaries follow typical learner
    /// articulation rates (natives ~150+).
    private var fluencyCEFR: CEFRLevel? {
        guard effectivePace > 0 else { return nil }
        switch effectivePace {
        case ..<60:    return .a1
        case 60..<85:  return .a2
        case 85..<105: return .b1
        case 105..<125: return .b2
        case 125..<145: return .c1
        default:        return .c2
        }
    }

    /// Correction rate → CEFR band (fewer flagged rephrasings = higher).
    private var grammarCEFR: CEFRLevel? {
        guard scoredCount > 0 else { return nil }
        switch corrPer10 {
        case 4...:      return .a1
        case 3..<4:     return .a2
        case 2..<3:     return .b1
        case 1..<2:     return .b2
        case 0.5..<1:   return .c1
        default:        return .c2
        }
    }

    /// Words per turn → CEFR band (how far ideas get developed per turn).
    private var expressionCEFR: CEFRLevel? {
        guard wordsPerTurn > 0 else { return nil }
        switch wordsPerTurn {
        case ..<5:    return .a1
        case 5..<8:   return .a2
        case 8..<12:  return .b1
        case 12..<16: return .b2
        case 16..<20: return .c1
        default:      return .c2
        }
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
                Text("Your level is graded by your first weekly read — one pooled assessment over ALL your talk, not a guess from one session.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ProgressView(value: min(acc, req), total: req)
                        .tint(.accentColor)
                    Text("\(Int(acc / 60))/\(Int(req / 60)) min")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            case .lockedNext(let daysRemaining, let secondsRemaining):
                Text("Your level is re-assessed with each weekly read. The next one needs both:")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                unlockConditionRow(
                    icon: "calendar",
                    met: daysRemaining == 0,
                    text: daysRemaining == 0
                        ? "A week since the last read"
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
                        .font(.system(size: 44, weight: .bold)).foregroundStyle(.tint)
                    Text("vocabulary level").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Estimated from \(usedTotal) distinct words you've actually used, each graded by CEFR level.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            panel {
                Text("Words you use, by level").font(.headline)
                ForEach(CEFRLevel.allCases, id: \.self) { lv in
                    levelBar(lv)
                }
            }
            panel {
                Text("How to level up").font(.headline)
                Text("Discover and use words you don't reach for yet — Practice → Vocabulary highlights the ones at and above your level.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            panel {
                HStack(alignment: .firstTextBaseline) {
                    Text("Expressions you've used").font(.headline)
                    Spacer()
                    Text("\(vocab.expressionCount)")
                        .font(.headline).foregroundStyle(.tint).monospacedDigit()
                }
                Text("Multi-word phrases you actually said in your talks, collected automatically — browse them under Practice → Expressions.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func levelBar(_ lv: CEFRLevel) -> some View {
        let count = perLevel[lv] ?? 0
        let maxC = max(1, perLevel.values.max() ?? 1)
        return HStack(spacing: 10) {
            Text(lv.rawValue.uppercased())
                .font(.caption.weight(.semibold).monospaced())
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
            action: nil
        )
    }

    private var pronunciationContent: some View {
        measuredContent(
            dim: .pronunciation,
            big: "\(shadowAccuracy)",
            bigUnit: "shadow accuracy",
            band: accuracyBand,
            measuredLine: "\(shadowAttempts) shadow attempt\(shadowAttempts == 1 ? "" : "s") — measured against your fluent self",
            measures: "How closely your sounds match the target, measured from shadow practice.",
            improve: "Shadow your fluent self's lines under Practice — listen, then match the rhythm and sounds.",
            action: nil
        )
    }

    private var grammarContent: some View {
        measuredContent(
            dim: .grammar,
            big: corrPer10 > 0 ? String(format: "%.1f", corrPer10) : "—",
            bigUnit: "corrections / 10 turns",
            band: nil,
            measuredLine: "How often a more natural rephrase was suggested — lower is better.",
            measures: "How correctly you build sentences — tenses, articles, agreement.",
            improve: "Run your review cards under Practice — they're built from your own slips and target exactly these.",
            action: nil
        )
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
            action: nil
        )
    }

    private struct DimAction { let title: String; let icon: String; let destination: AnyView }

    private func measuredContent(dim: Dim, big: String, bigUnit: String, band: String?,
                                 measuredLine: String?, measures: String, improve: String,
                                 action: DimAction?) -> some View {
        VStack(spacing: 16) {
            panel {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(big).font(.system(size: 44, weight: .bold)).monospacedDigit().foregroundStyle(.tint)
                    Text(bigUnit).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let band { Text(band).font(.subheadline.weight(.semibold)) }
                }
                if let measuredLine {
                    Text(measuredLine).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(measures).font(.footnote).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }

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
        case .a1: return "Simple words and phrases about immediate, familiar things."
        case .a2: return "Everyday topics in simple terms — routines, plans, basic needs."
        case .b1: return "Familiar topics fluently enough to get by, and tell a simple story."
        case .b2: return "Clear, detailed talk on many topics, including some abstract ones."
        case .c1: return "Fluent, flexible, and precise — even on complex topics."
        case .c2: return "Effortless and nuanced, close to native."
        }
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

    private var accuracyBand: String {
        switch shadowAccuracy {
        case ..<1:    return "—"
        case 1..<60:  return "Developing"
        case 60..<80: return "Solid"
        default:      return "Strong"
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
            Text("Have a few conversations and I'll estimate your level and break down how your \(LanguageCatalog.englishName(appState.targetLanguage)) is developing.")
        }
    }

    // MARK: - Data

    private func reload() {
        dashboard = PracticeStats.snapshot()
        dueCount = DrillStore.shared.load().filter { $0.nextReviewAt <= Date() }.count
        vocab.backfillFromSessions()

        // --- Objective vocabulary CEFR estimate (from words actually used) ---
        var counts: [CEFRLevel: Int] = [:]
        var total = 0
        for word in vocab.usedWords() {
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
        let scoredSessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.summary?.scorecard != nil }
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
        corrPer10 = mean(mets.map(\.suggestionRate)) * 10

        // --- Pronunciation from measured shadow accuracy ---
        let attempts = appState.shadowAttempts
        shadowAttempts = attempts.count
        let recentAtt = attempts.sorted { $0.createdAt > $1.createdAt }.prefix(10).map { $0.matchScore }
        shadowAccuracy = recentAtt.isEmpty ? 0 : recentAtt.reduce(0, +) / recentAtt.count

        let cards = scoredSessions.compactMap { $0.summary?.scorecard }

        // --- Overall level ---
        // ONLY the weekly report's pooled read (one judgment over a whole
        // window's speech). Per-session reads are too noisy to publish — if
        // the sample isn't big enough yet, we show "building", not a number.
        aiLevel = appState.weeklyReports
            .sorted { $0.generatedAt > $1.generatedAt }
            .compactMap { $0.cefrLevel.flatMap { CEFRLevel(rawValue: $0) } }
            .first

        // Real unlock state for the building panel — and if the next read is
        // already unlocked, kick it off RIGHT HERE. Waiting for the next
        // conversation to end (the only other trigger) would leave the user
        // staring at a full progress bar with nothing happening.
        let endedSessions = SessionStore.shared.load().filter { $0.endedAt != nil }
        reportUnlock = WeeklyReportEngine.unlockState(
            endedSessions: endedSessions,
            lastReport: appState.weeklyReports.first
        )
        if aiLevel == nil, case .ready = reportUnlock {
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

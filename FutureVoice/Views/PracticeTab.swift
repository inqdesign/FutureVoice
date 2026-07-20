import SwiftUI

/// Practice home — three layers in the order a person actually needs them:
///
///   1. Today    — ONE composed action ("5 cards · 2 lines — 4 min → Start"),
///                 not a menu of equal-weight sections.
///   2. Activity — effort made visible: 14-day rep bars + weekly stats +
///                 the shadow-score trend. Powered by `PracticeLog`.
///   3. Library  — words / expressions / lines / per-session post-mortems.
///
/// Card layout matches Home and Progress (grouped background + rounded
/// panels) so the three dashboards read as one design system.
struct PracticeTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var vocab = VocabStore.shared

    @State private var dueCount = 0
    @State private var totalCards = 0
    @State private var nextDueAt: Date?
    @State private var picks: [PracticeStats.ShadowPick] = []
    @State private var recentSessions: [SessionRow] = []
    @State private var moreSessionsExist = false
    @State private var shadowPick: PracticeStats.ShadowPick?
    /// Programmatic pushes driven by the study-widget deep links
    /// (futurevoice://vocab and futurevoice://expressions).
    @State private var showingVocabulary = false
    @State private var showingExpressions = false
    // Effort signals (PracticeLog + shadow attempt history).
    @State private var todayReps = 0
    @State private var weekReps = 0
    @State private var daysActiveThisWeek = 0
    @State private var avgShadowScore = 0
    /// Reps per day, index 0 = today … 13 = two weeks ago.
    @State private var repsByOffset: [Int] = Array(repeating: 0, count: 14)
    @State private var shadowTrend: PracticeStats.ShadowTrend?

    struct SessionRow: Identifiable {
        let session: Session
        let cardCount: Int
        let dueCount: Int
        var id: UUID { session.id }
    }

    private static let recentSessionLimit = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if weekReps > 0 || repsByOffset.contains(where: { $0 > 0 }) {
                        activityCard
                    }
                    todayCard
                    libraryCard
                    if !recentSessions.isEmpty {
                        sessionsCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
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
            .sheet(item: $shadowPick, onDismiss: reload) { pick in
                ShadowDrillView(turn: pick.turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
        }
    }

    /// Deep link handoff (study widget → vocabulary notebook). The route is
    /// staged in AppState because on a cold launch the URL arrives before
    /// this tab exists — onAppear picks it up; onChange covers warm taps.
    private func consumePendingRoute() {
        switch appState.pendingPracticeRoute {
        case .vocabulary:
            appState.pendingPracticeRoute = nil
            showingVocabulary = true
        case .expressions:
            appState.pendingPracticeRoute = nil
            showingExpressions = true
        case nil:
            break
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayCard: some View {
        card {
            if dueCount > 0 || (!picks.isEmpty && todayShadowReps == 0) {
                Text("Today").font(.title3.weight(.semibold))
                // Cards and shadowing are INDEPENDENT actions — with a big
                // due backlog, chaining them would mean never shadowing.
                HStack(spacing: 10) {
                    if dueCount > 0 {
                        NavigationLink {
                            DrillView()
                                .navigationTitle("Review")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            actionTile(icon: "rectangle.stack.fill",
                                       count: "\(dueCount)",
                                       label: dueCount == 1 ? "card due" : "cards due",
                                       action: "Review")
                        }
                        .buttonStyle(.plain)
                    }
                    if todayShadowGoal > 0 {
                        NavigationLink {
                            PracticeSessionView(
                                shadowPicks: Array(picks.prefix(todayShadowGoal)),
                                includeCards: false)
                        } label: {
                            actionTile(icon: "waveform.badge.mic",
                                       count: "\(todayShadowGoal)",
                                       label: todayShadowGoal == 1 ? "shadow line" : "shadow lines",
                                       action: "Shadow")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if todayReps > 0 {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Done for today").font(.title3.weight(.semibold))
                        Text("\(todayReps) rep\(todayReps == 1 ? "" : "s") today · \(nextDueText)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if totalCards > 0 {
                        NavigationLink {
                            DrillView(source: .ahead(10))
                                .navigationTitle("Practice ahead")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("Practice ahead", systemImage: "forward.end")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let pick = picks.first {
                        Button {
                            shadowPick = pick
                        } label: {
                            Label("One more line", systemImage: "waveform.badge.mic")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing queued yet").font(.title3.weight(.semibold))
                        Text("Have a conversation — its corrections and lines become today's practice.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var todayShadowGoal: Int { min(2, picks.count) }

    private var todayShadowReps: Int {
        PracticeLog.shared.day(Date())?.shadowReps ?? 0
    }

    /// One tappable tile per practice mode: big count, what it is, and the
    /// verb it launches. Both tiles share the row; each goes its own way.
    private func actionTile(icon: String, count: String, label: String, action: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(count)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Text(action)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
        .contentShape(Rectangle())
    }

    private var nextDueText: String {
        guard let next = nextDueAt else { return "new cards come from conversations" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "next review \(fmt.localizedString(for: next, relativeTo: Date()))"
    }

    // MARK: - Activity

    private var activityCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.title3.weight(.semibold))
                Spacer()
                if let delta = shadowTrend?.delta {
                    Label(delta >= 0 ? "shadow +\(delta)" : "shadow \(delta)",
                          systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? Color.green : Color.orange)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                // Oldest on the left, today on the right.
                ForEach((0..<14).reversed(), id: \.self) { offset in
                    Capsule()
                        .fill(repsByOffset[offset] > 0 ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(height: barHeight(repsByOffset[offset]))
                        .frame(maxWidth: .infinity, maxHeight: 44, alignment: .bottom)
                }
            }
            .frame(height: 44, alignment: .bottom)
            HStack {
                Text("2 weeks ago")
                Spacer()
                Text("today")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Divider()
            HStack(spacing: 16) {
                stat(value: "\(weekReps)", label: weekReps == 1 ? "rep this week" : "reps this week")
                stat(value: "\(daysActiveThisWeek)", label: daysActiveThisWeek == 1 ? "day active" : "days active")
                if avgShadowScore > 0 {
                    stat(value: "\(avgShadowScore)", label: "avg shadow score")
                }
            }
        }
    }

    private func barHeight(_ reps: Int) -> CGFloat {
        guard reps > 0 else { return 6 }
        let maxReps = max(8, repsByOffset.max() ?? 8)
        return max(10, CGFloat(Double(reps) / Double(maxReps)) * 44)
    }

    private func stat(value: String, label: String) -> some View {
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

    // MARK: - Library

    private var libraryCard: some View {
        card {
            Text("Library").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                NavigationLink {
                    VocabularyView()
                } label: {
                    libraryRow(icon: "character.book.closed.fill", title: "Vocabulary",
                               detail: "\(vocab.knownCount) of \(vocab.total) words used or known")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 40)
                NavigationLink {
                    ExpressionsView()
                        .navigationTitle("Expressions")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    libraryRow(icon: "quote.bubble.fill", title: "Expressions",
                               detail: expressionCount == 0
                                   ? "Phrases you use in talks collect here"
                                   : "\(expressionCount) from your talks")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 40)
                NavigationLink {
                    ShadowBrowserView()
                        .navigationTitle("Shadowing")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    libraryRow(icon: "waveform.badge.mic", title: "Shadowing",
                               detail: appState.savedLines.isEmpty
                                   ? "Shadow any line your fluent self has said"
                                   : "Shadow any line · \(appState.savedLines.count) saved")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var expressionCount: Int { vocab.expressionEntries().count }

    private func libraryRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(.tertiarySystemFill)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - Sessions

    private var sessionsCard: some View {
        card {
            Text("From your conversations").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                ForEach(recentSessions) { row in
                    NavigationLink {
                        ConversationDetailView(session: row.session)
                    } label: {
                        sessionRowView(row)
                    }
                    .buttonStyle(.plain)
                    if row.id != recentSessions.last?.id || moreSessionsExist {
                        Divider()
                    }
                }
                if moreSessionsExist {
                    NavigationLink {
                        DrillsBySessionView()
                            .navigationTitle("All sessions")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Text("All sessions")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tint)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRowView(_ row: SessionRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(row.session.endedAt ?? row.session.startedAt, style: .relative)
                    Text("·")
                    Text(row.cardCount == 1 ? "1 card" : "\(row.cardCount) cards")
                    if row.dueCount > 0 {
                        Text("·")
                        Text("\(row.dueCount) due").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - Card shell (same as Home/Progress panels)

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Data

    private func reload() {
        vocab.backfillFromSessions()
        let now = Date()
        let cards = DrillStore.shared.load()
        totalCards = cards.count
        dueCount = cards.filter { $0.nextReviewAt <= now }.count
        nextDueAt = cards.map(\.nextReviewAt).filter { $0 > now }.min()

        let sessions = SessionStore.shared.load()
        picks = PracticeStats.shadowPicks(
            sessions: sessions,
            attempts: appState.shadowAttempts,
            level: appState.proficiency
        )

        // Effort: PracticeLog going forward; shadow-attempt history and card
        // review dates backfill the days before the log existed.
        let cal = Calendar.current
        todayReps = PracticeLog.shared.day(now)?.total ?? 0
        var reps: [Int] = []
        for offset in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: now) else {
                reps.append(0); continue
            }
            let logged = PracticeLog.shared.day(d)?.total ?? 0
            let shadowed = appState.shadowAttempts.filter { cal.isDate($0.createdAt, inSameDayAs: d) }.count
            let reviewed = cards.filter { c in
                c.lastReviewedAt.map { cal.isDate($0, inSameDayAs: d) } ?? false
            }.count
            reps.append(max(logged, shadowed + reviewed))
        }
        repsByOffset = reps
        weekReps = reps.prefix(7).reduce(0, +)
        daysActiveThisWeek = reps.prefix(7).filter { $0 > 0 }.count
        shadowTrend = PracticeStats.shadowTrend(attempts: appState.shadowAttempts, now: now)
        let recentScores = appState.shadowAttempts
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10).map(\.matchScore)
        avgShadowScore = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / recentScores.count

        var cardsBySession: [UUID: [DrillCard]] = [:]
        for card in cards {
            guard let sid = card.sourceSessionId else { continue }
            cardsBySession[sid, default: []].append(card)
        }
        let withCards = sessions
            .filter { cardsBySession[$0.id] != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        recentSessions = withCards.prefix(Self.recentSessionLimit).map { s in
            let own = cardsBySession[s.id] ?? []
            return SessionRow(
                session: s,
                cardCount: own.count,
                dueCount: own.filter { $0.nextReviewAt <= now }.count
            )
        }
        moreSessionsExist = withCards.count > Self.recentSessionLimit
    }
}

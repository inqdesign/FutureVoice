import SwiftUI

/// Practice home, organized around ONE question — "what should I practice
/// right now?" — instead of the old mechanism-based segments (Due / Sessions
/// / Shadow, which all showed the same data sliced differently).
///
///   1. Review due — the SRS deck, the single primary action.
///   2. Shadow picks — a curated handful (fresh lines from the latest
///      conversation + low-score retries), not the full archive.
///   3. From your conversations — per-session post-mortem entry points.
///
/// The full archives still exist one push away (Browse all lines / All
/// sessions) for users who want to dig.
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

    struct SessionRow: Identifiable {
        let session: Session
        let cardCount: Int
        let dueCount: Int
        var id: UUID { session.id }
    }

    private static let recentSessionLimit = 3

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Practice")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onAppear(perform: reload)
            .sheet(item: $shadowPick, onDismiss: reload) { pick in
                ShadowDrillView(turn: pick.turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Sections

    private var content: some View {
        List {
            reviewSection
            vocabularySection
            shadowSection
            sessionsSection
        }
        .listStyle(.insetGrouped)
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                VocabularyView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vocabulary")
                            .font(.headline)
                        Text("\(vocab.knownCount) of \(vocab.total) words used or known")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            // Expressions are the same "things you actually said" pool as
            // vocabulary — they belong in the practice hub, not buried in
            // the Progress tab.
            NavigationLink {
                ExpressionsView()
                    .navigationTitle("Expressions")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expressions")
                            .font(.headline)
                        Text(expressionCount == 0
                             ? "Phrases you use in talks collect here"
                             : (expressionCount == 1
                                ? "1 expression from your talks"
                                : "\(expressionCount) expressions from your talks"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Your words")
        } footer: {
            Text("Words and expressions collected from what you actually say — explore, bookmark, and hear your fluent self say them.")
        }
    }

    private var expressionCount: Int { vocab.expressionEntries().count }

    @ViewBuilder
    private var reviewSection: some View {
        Section {
            if dueCount > 0 {
                NavigationLink {
                    DrillView()
                        .navigationTitle("Review")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Review due")
                                .font(.headline)
                            Text(dueCount == 1 ? "1 card waiting" : "\(dueCount) cards waiting")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All caught up")
                            .font(.headline)
                        Text(nextDueText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if totalCards > 0 {
                    NavigationLink {
                        DrillView(source: .ahead(10))
                            .navigationTitle("Practice ahead")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Practice ahead anyway", systemImage: "forward.end")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var nextDueText: String {
        guard let next = nextDueAt else { return "New cards appear after conversations." }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "Next review \(fmt.localizedString(for: next, relativeTo: Date()))."
    }

    @ViewBuilder
    private var shadowSection: some View {
        if !picks.isEmpty || !appState.savedLines.isEmpty {
            Section {
                ForEach(picks) { pick in
                    Button {
                        shadowPick = pick
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pick.turn.transcript)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(pick.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // One archive entry instead of two ("Saved lines" + "Browse
                // all") — saved lines are a filter inside the browser now.
                NavigationLink {
                    ShadowBrowserView()
                        .navigationTitle("All lines")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text("All lines")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                        Spacer()
                        if !appState.savedLines.isEmpty {
                            Label("\(appState.savedLines.count)", systemImage: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Shadow picks")
            } footer: {
                Text("Sized to your \(appState.proficiency.rawValue.uppercased()) level — fresh lines from your latest conversations, plus ones worth another try.")
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !recentSessions.isEmpty {
            Section {
                ForEach(recentSessions) { row in
                    // Full session post-mortem (transcript + per-line shadow +
                    // corrections + Review toolbar), not just the card deck —
                    // one destination that holds everything the talk taught.
                    NavigationLink {
                        ConversationDetailView(session: row.session)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.session.displayTitle)
                                .font(.body)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(row.session.endedAt ?? row.session.startedAt, style: .relative)
                                Text("·")
                                Text(row.cardCount == 1 ? "1 card" : "\(row.cardCount) cards")
                                if row.dueCount > 0 {
                                    Text("·")
                                    Text("\(row.dueCount) due")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                if moreSessionsExist {
                    NavigationLink {
                        DrillsBySessionView()
                            .navigationTitle("All sessions")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Text("All sessions")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                }
            } header: {
                Text("From your conversations")
            } footer: {
                Text("Walk back through what one conversation taught you.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to practice yet", systemImage: "lightbulb")
        } description: {
            Text("Have a conversation in Talk first — its corrections become review cards, and every line your fluent self says becomes shadow material.")
        }
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

import SwiftUI

/// The Expressions challenge session — the same deck as `DailyWordsView`
/// (card stack, tap to flip the meaning, drag into Later / Keep / I know),
/// dealt from the expression pool instead of the word sources. A rep is a
/// resolved card; Later requeues within today's hand.
struct DailyExpressionsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var picks: [String] = []
    @State private var dealt = false

    var body: some View {
        NavigationStack {
            Group {
                if dealt && picks.isEmpty {
                    emptyState
                } else if dealt {
                    StudyDeckView(title: "Expressions",
                                  items: picks.map(StudyDeckItem.expression),
                                  onResolve: resolve)
                }
            }
            .navigationTitle("Expressions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !dealt else { return }
            picks = Self.pick(goal: max(GoalStore.shared.expressionsPerDay, 1),
                              appState: appState)
            dealt = true
        }
    }

    /// Mirrors `DailyWordsView.resolve`: a delay bin bookmarks the phrase and
    /// schedules its return; "Got it" marks it known and clears the schedule.
    /// Exactly one rep per drop. (`setKnownExpression(_, true)` always logs.)
    private func resolve(_ item: StudyDeckItem, _ bin: DrillBin) {
        let phrase = item.text
        let store = VocabStore.shared
        if let manual = bin.manual {
            if store.isStudyingExpression(phrase) {
                PracticeLog.shared.record(.expression)
            } else {
                store.setStudyingExpression(phrase, true)
            }
            ReviewQueue.snooze(.expression, phrase, for: manual.delay)
        } else {
            store.setKnownExpression(phrase, true)
            ReviewQueue.retire(.expression, phrase)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(explain("Expressions from your calls — yours and your fluent self's — will collect here."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The day's hand

    /// Deal today's expressions, most personal material first:
    ///   1. bookmarked (studying) expressions not yet known — rotated by day,
    ///      same as the words session's notebook rotation
    ///   2. unmastered expressions from active Watch books
    ///   3. expressions the fluent self used in a call and they haven't said
    ///   4. expressions they said themselves, newest first, not yet known
    /// 3 before 4 on purpose: a deck exists to teach what you can't say yet,
    /// and the phrases you already produced are already yours.
    /// No core-list top-up exists for phrases, so the hand can run short —
    /// the empty state explains where they come from.
    static func pick(goal: Int, appState: AppState,
                     now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let store = VocabStore.shared
        var seen = Set<String>()
        var out: [String] = []
        func add(_ p: String) {
            let k = p.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !k.isEmpty, !seen.contains(k) else { return }
            seen.insert(k)
            out.append(p)
        }

        // Bookmarked phrases, honoring the deck's schedule — same rule as the
        // words session: snoozed-and-not-due stays out, overdue comes first.
        let schedule = StudyScheduleStore.shared
        let studying = store.studyingExpressions
            .filter { !store.isKnownExpression($0) && schedule.isDue(.expression, $0, now: now) }
        let scheduled = studying
            .compactMap { p in schedule.nextReview(.expression, p).map { (p, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        for p in scheduled { add(p) }
        let unscheduled = studying.filter { schedule.nextReview(.expression, $0) == nil }
        if !unscheduled.isEmpty {
            let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
            let offset = day % unscheduled.count
            let ordered = Array(unscheduled.reversed())   // oldest bookmark first
            for p in ordered[offset...] + ordered[..<offset] { add(p) }
        }

        if out.count < goal {
            // Skip phrases the collection already marks known — a book that
            // hasn't refreshed its mastery yet can still list them unmastered.
            for sc in appState.scenarios where !sc.isArchived {
                for item in sc.curriculum?.expressions ?? []
                where item.masteredAt == nil && !store.isKnownExpression(item.text) {
                    add(item.text)
                }
            }
        }

        if out.count < goal {
            for item in ExpressionCatalog.all(scenarios: appState.scenarios, store: store)
            where !store.isKnownExpression(item.text) {
                // Heard-in-a-call first, then the ones they said — `all` is
                // already newest-first within each group.
                if case .heard = item.origin { add(item.text) }
            }
        }

        if out.count < goal {
            for e in store.expressionEntries() where !store.isKnownExpression(e.text) {
                add(e.text)
            }
        }

        return Array(out.prefix(goal))
    }
}

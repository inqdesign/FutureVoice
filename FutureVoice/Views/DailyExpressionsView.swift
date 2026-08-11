import SwiftUI

/// The Expressions challenge session — today's recommended expressions, one
/// card at a time. The exact same shape as `DailyWordsView`: a hand dealt on
/// appear, fixed for the session, each card the full `ExpressionCard` so a
/// judgment here is a real collection judgment (the store logs the rep), and
/// a card you read and move past counts too — one rep per phrase, never two.
struct DailyExpressionsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var picks: [String] = []
    @State private var current: String?
    /// Lowercased phrases already counted toward today's goal this session.
    @State private var counted: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let first = picks.first {
                    // Same identity trick as ExpressionSheet: the card view is
                    // never torn down, its content just swaps as `current` moves.
                    ExpressionCard(phrase: current ?? first,
                                   currentPhrase: Binding(
                                       get: { current ?? first },
                                       set: { if let p = $0 { current = p } }
                                   ),
                                   navigationPhrases: picks,
                                   titleByPosition: true,
                                   onJudged: { counted.insert(key($0)) })
                } else {
                    emptyState
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard picks.isEmpty else { return }
            picks = Self.pick(goal: max(GoalStore.shared.expressionsPerDay, 1),
                              appState: appState)
            current = picks.first
        }
        .onChange(of: current) { old, _ in countIfViewed(old) }
        .onDisappear { countIfViewed(current ?? picks.first) }
    }

    private func key(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func countIfViewed(_ phrase: String?) {
        guard let phrase else { return }
        let k = key(phrase)
        guard !counted.contains(k) else { return }
        counted.insert(k)
        PracticeLog.shared.record(.expression)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(explain("Expressions you use in your talks will collect here."))
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
    ///   3. expressions collected from talks, newest first, not yet known
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

        let studying = store.studyingExpressions.filter { !store.isKnownExpression($0) }
        if !studying.isEmpty {
            let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
            let offset = day % studying.count
            let ordered = Array(studying.reversed())   // oldest bookmark first
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
            for e in store.expressionEntries() where !store.isKnownExpression(e.text) {
                add(e.text)
            }
        }

        return Array(out.prefix(goal))
    }
}

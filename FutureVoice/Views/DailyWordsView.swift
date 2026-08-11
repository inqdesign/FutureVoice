import SwiftUI

/// The Words challenge session — today's recommended words, one card at a
/// time, drill-style. The Today card's Words row lands HERE, not in the
/// explore cloud: a challenge needs a bounded hand dealt for you, the way the
/// sentence deck deals its 20.
///
/// The hand is picked once on appear and stays fixed for the session (judging
/// a word can't reshuffle the deck under your thumb). Each card is the full
/// `WordCard` — meaning, examples, your own sentences, Keep / I know — so a
/// judgment here IS a notebook judgment, and the store logs the rep. A word
/// you just read and move past counts too: in a dealt hand of recommendations,
/// working through a card is the rep, same as flipping a drill card.
struct DailyWordsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var picks: [String] = []
    @State private var currentWord: String?
    /// Lowercased words already counted toward today's goal — via the card's
    /// buttons (the store logged that rep) or by being viewed and moved past
    /// (we log it here). One rep per word per session, never two.
    @State private var counted: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let w = currentWord {
                    WordCard(word: w, currentWord: $currentWord, isExpanded: true,
                             navigationWords: picks,
                             onJudged: { counted.insert($0.lowercased()) })
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
            picks = Self.pick(goal: max(GoalStore.shared.wordsPerDay, 1), appState: appState)
            currentWord = picks.first
        }
        .onChange(of: currentWord) { old, _ in countIfViewed(old) }
        .onDisappear { countIfViewed(currentWord) }
    }

    private func countIfViewed(_ word: String?) {
        guard let word else { return }
        let key = word.lowercased()
        guard !counted.contains(key) else { return }
        counted.insert(key)
        PracticeLog.shared.record(.word)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(explain("Nothing to study yet — have a talk or watch a scene first; the words it surfaces get dealt here."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The day's hand

    /// Deal today's words, most personal material first:
    ///   1. notebook `studying` words — rotated by day so a 30-word backlog
    ///      doesn't deal the same 10 forever
    ///   2. unmastered words from active Watch books
    ///   3. pickup words from the two most recent talks (fluent-self lines,
    ///      at the learner's level and up)
    ///   4. core-list top-up at the learner's level and up, so the hand is
    ///      never short even on day one
    /// Deterministic within a day; dedup is case-insensitive.
    static func pick(goal: Int, appState: AppState,
                     now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let store = VocabStore.shared
        var seen = Set<String>()
        var out: [String] = []
        func add(_ w: String) {
            let k = w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !k.isEmpty, !seen.contains(k) else { return }
            seen.insert(k)
            out.append(w)
        }

        let studying = store.studying
        if !studying.isEmpty {
            let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
            let offset = day % studying.count
            // Oldest-first (the list is newest-first), then rotate by the day.
            let ordered = Array(studying.reversed())
            for w in ordered[offset...] + ordered[..<offset] { add(w) }
        }

        if out.count < goal {
            // Skip words the store already counts as known/used — a book that
            // hasn't refreshed its mastery yet can still list them unmastered.
            // Same three-form check as AppState.refreshScenarioMastery.
            func known(_ w: String) -> Bool {
                [w, w.lowercased(), VocabStore.lookupKey(for: w)]
                    .contains { store.records[$0] != nil }
            }
            for sc in appState.scenarios where !sc.isArchived {
                for item in sc.curriculum?.words ?? []
                where item.masteredAt == nil && !known(item.text) {
                    add(item.text)
                }
            }
        }

        if out.count < goal {
            let fluentTexts = SessionStore.shared.load()
                .filter { $0.endedAt != nil }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(2)
                .flatMap { $0.turns.filter { $0.role == .fluentSelf }.map(\.transcript) }
            for w in store.pickupWords(fromFluentTexts: Array(fluentTexts),
                                       atOrAbove: appState.proficiency) {
                add(w)
            }
        }

        if out.count < goal {
            let minRank = CoreVocabulary.levelRank(appState.proficiency)
            for e in CoreVocabulary.entries
            where CoreVocabulary.levelRank(e.level) >= minRank {
                guard store.records[e.word] == nil else { continue }
                add(e.word)
                if out.count >= goal { break }
            }
        }

        return Array(out.prefix(goal))
    }
}

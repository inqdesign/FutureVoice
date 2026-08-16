import SwiftUI

/// The Words challenge session — today's recommended words as a DECK, the
/// same card-stack-and-bins grammar as the sentence drill: front of the card
/// is the word alone (recall first), tap flips the meaning, then drag it into
/// Later (back of today's deck) / Keep (study notebook) / I know.
///
/// The hand is picked once on appear and stays fixed for the session. A rep
/// is a RESOLVED card — Keep or I know — so "Later" costs nothing until the
/// card comes around again and gets a real judgment.
struct DailyWordsView: View {
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
                    StudyDeckView(title: "Words", items: picks.map(StudyDeckItem.word),
                                  onResolve: resolve)
                }
            }
            .navigationTitle("Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !dealt else { return }
            picks = Self.pick(goal: max(GoalStore.shared.wordsPerDay, 1), appState: appState)
            dealt = true
        }
    }

    /// Exactly one rep per dropped card, same as the drill deck logs every
    /// grade. A delay bin means "still learning": the word joins the notebook
    /// (if it wasn't there) and its return is written into the schedule the
    /// daily pick reads. "Got it" files it as known and clears the schedule.
    /// The store logs the rep on a state change (addStudying / markKnown);
    /// re-snoozing an already-kept word is a review, logged directly.
    private func resolve(_ item: StudyDeckItem, _ bin: DrillBin) {
        let word = item.text
        if let manual = bin.manual {
            if VocabStore.shared.isStudying(word) {
                PracticeLog.shared.record(.word)
            } else {
                VocabStore.shared.addStudying(word)
            }
            ReviewQueue.snooze(.word, word, for: manual.delay)
        } else {
            VocabStore.shared.markKnown(word)
            ReviewQueue.retire(.word, word)
        }
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

        // Notebook words, honoring the deck's own schedule: a word snoozed to
        // "3 days" stays out of the hand until it's due again. Overdue
        // scheduled words come first (earliest return first); never-scheduled
        // ones follow, oldest-first and rotated by the day so a big notebook
        // doesn't deal the same hand forever.
        let schedule = StudyScheduleStore.shared
        let studying = store.studying.filter { schedule.isDue(.word, $0, now: now) }
        let scheduled = studying
            .compactMap { w in schedule.nextReview(.word, w).map { (w, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        for w in scheduled { add(w) }
        let unscheduled = studying.filter { schedule.nextReview(.word, $0) == nil }
        if !unscheduled.isEmpty {
            let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
            let offset = day % unscheduled.count
            let ordered = Array(unscheduled.reversed())
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

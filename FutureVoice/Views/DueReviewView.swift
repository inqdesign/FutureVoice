import SwiftUI

/// What a review reminder OPENS: exactly the words and expressions whose
/// return time has arrived, in one deck, longest-waiting first.
///
/// This is the other half of the "10 min · Tomorrow · 3 days" promise. The
/// deck sessions write the promise; this keeps it. Deliberately NOT a fresh
/// daily hand — dealing new material here would make the notification a lie
/// ("3 items are back" → 10 unrelated words). If nothing is due the empty
/// state says so rather than inventing work.
///
/// Sentences aren't mixed in: those are `DrillCard`s with their own deck and
/// their own Leitner ladder. The reminder counts them and the Practice tab's
/// Sentences row opens them; only word/expression items are dealt here.
struct DueReviewView: View {
    /// When set, the deck holds exactly this one card — a per-item callback
    /// was tapped, and it named this word/phrase. Opening the whole queue
    /// there would bury the thing the learner came for.
    var focus: StudyDeckItem? = nil
    /// A book chapter's own deck (the Review tab's chapter buttons): these
    /// items, under this title, instead of the due queue.
    var hand: [StudyDeckItem]? = nil
    var title: LocalizedStringKey = "Back from earlier"
    /// What an empty deck says — the routine's Review deck is not the
    /// put-off pile, and must not call itself that.
    var emptyTitle: LocalizedStringKey = "Nothing put off"
    var emptyMessage: LocalizedStringKey = "Words, expressions and sentences you put off in a deck all show up here, in the order they come back."

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [StudyDeckItem] = []
    @State private var dealt = false

    var body: some View {
        NavigationStack {
            Group {
                if dealt && items.isEmpty {
                    emptyState
                } else if dealt {
                    StudyDeckView(title: title, items: items, onResolve: resolve)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !dealt else { return }
            items = focus.map { [$0] } ?? hand ?? Self.putOffDeck()
            dealt = true
        }
    }

    /// Everything back from its snooze, oldest promise first — the SAME
    /// queue the reminder counted (see `ReviewQueue`).
    /// The routine's Review block (2026-10-03): ONE deck of every kind —
    /// what came back from a snooze, sentence cards due, then today's new
    /// words and expressions — up to the block's count. Shadow lines count
    /// toward the same number but are spoken, not dealt, so they live in
    /// their own screen.
    @MainActor
    static func routineDeck(goal: Int, appState: AppState, now: Date = Date()) -> [StudyDeckItem] {
        var out: [StudyDeckItem] = []
        var seen = Set<String>()
        func add(_ items: [StudyDeckItem]) {
            for i in items where out.count < goal && seen.insert(i.id).inserted { out.append(i) }
        }
        add(ReviewQueue.dueItems(now: now))
        add(DrillStore.shared.due(now: now).map(StudyDeckItem.sentence))
        let left = max(0, goal - out.count)
        guard left > 0 else { return out }
        // Fresh words and expressions, in the daily decks' own proportion.
        let words = DailyWordsView.pick(goal: max(1, left * 3 / 4), appState: appState, now: now)
        let exprs = DailyExpressionsView.pick(goal: max(1, left - left * 3 / 4), appState: appState, now: now)
        add(words.map(StudyDeckItem.word))
        add(exprs.map(StudyDeckItem.expression))
        return out
    }

    static func dueDeck(now: Date = Date()) -> [StudyDeckItem] {
        ReviewQueue.dueItems(now: now)
    }

    /// EVERYTHING the learner put off — words, expressions and sentence
    /// cards, due or not — in the order it comes back (2026-10-03, user
    /// decision: "what I put off, show me all of it", and "1 of N" counts
    /// all of it). A put-off item is still a promise the learner made; one
    /// whose time hasn't come is not hidden for that.
    static func putOffDeck(now: Date = Date()) -> [StudyDeckItem] {
        ReviewQueue.pruneRetired()
        let store = StudyScheduleStore.shared
        let scheduled = (store.dueItems(now: now) + store.upcoming(now: now))
            .map { (StudyDeckItem(kind: $0.kind, text: $0.text), $0.at) }
        let sentences = DrillStore.putOffCards().map { (StudyDeckItem.sentence($0), $0.nextReviewAt) }
        return (scheduled + sentences).sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Same rules as the daily sessions: a delay re-snoozes and counts a rep,
    /// "Got it" marks it known and retires its schedule entry.
    private func resolve(_ item: StudyDeckItem, _ bin: DrillBin) {
        if let id = item.cardId {
            // The sentence deck's own verdicts (`DrillView.apply`).
            guard let card = DrillStore.shared.load().first(where: { $0.id == id }) else { return }
            if let manual = bin.manual {
                let at = Date().addingTimeInterval(manual.delay)
                DrillStore.shared.snooze(card, box: manual.box, until: at)
                Task { await ItemReminder.schedule(.sentence(card.id), text: card.targetPhrase, at: at) }
            } else {
                DrillStore.shared.markKnown(card)
                ItemReminder.cancel(.sentence(card.id))
            }
            PracticeLog.shared.record(.drill, finished: bin.manual == nil)
            return
        }
        let store = VocabStore.shared
        switch (item.kind, bin.manual) {
        case (.word, .some(let manual)):
            if store.isStudying(item.text) {
                PracticeLog.shared.record(.word)
            } else {
                store.addStudying(item.text)
            }
            ReviewQueue.snooze(.word, item.text, for: manual.delay)
        case (.word, .none):
            store.markKnown(item.text)
            ReviewQueue.retire(.word, item.text)
        case (.expression, .some(let manual)):
            if store.isStudyingExpression(item.text) {
                PracticeLog.shared.record(.expression)
            } else {
                store.setStudyingExpression(item.text, true)
            }
            ReviewQueue.snooze(.expression, item.text, for: manual.delay)
        case (.expression, .none):
            store.setKnownExpression(item.text, true)
            ReviewQueue.retire(.expression, item.text)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

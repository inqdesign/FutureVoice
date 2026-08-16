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
                    StudyDeckView(title: "Review", items: items, onResolve: resolve)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !dealt else { return }
            items = focus.map { [$0] } ?? Self.dueDeck()
            dealt = true
        }
    }

    /// Everything back from its snooze, oldest promise first — the SAME
    /// queue the reminder counted (see `ReviewQueue`).
    static func dueDeck(now: Date = Date()) -> [StudyDeckItem] {
        ReviewQueue.dueItems(now: now)
    }

    /// Same rules as the daily sessions: a delay re-snoozes and counts a rep,
    /// "Got it" marks it known and retires its schedule entry.
    private func resolve(_ item: StudyDeckItem, _ bin: DrillBin) {
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
            Text("Nothing due right now")
                .font(.headline)
            Text(explain("Everything you set aside is still waiting for its turn. Today's goals are on the Practice tab."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

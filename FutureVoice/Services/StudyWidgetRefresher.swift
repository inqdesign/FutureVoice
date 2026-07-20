import Foundation
import WidgetKit

/// Publishes two home-screen widgets from the app's stores: a Vocabulary
/// widget (notebook words) and an Expressions widget (phrases from talks).
/// Each gets its own snapshot in the App Group container, rewritten whenever
/// the underlying store changes and at scene-phase edges as a catch-all.
///
/// App target only — the widget extension just reads `StudyWidgetSnapshotStore`.
enum StudyWidgetRefresher {

    /// Widgets window through a slice of the collection; anything past this
    /// never renders, so don't bloat the snapshot with the whole pool.
    private static let maxItems = 24

    @MainActor
    static func refresh() {
        refreshWords()
        refreshExpressions()
    }

    /// Fire-and-forget hook for nonisolated call sites (store writes may not
    /// be on the main actor).
    nonisolated static func schedule() {
        Task { @MainActor in refresh() }
    }

    // MARK: - Vocabulary widget

    @MainActor
    private static func refreshWords() {
        let vocab = VocabStore.shared
        // The words the user deliberately collected to study, newest first;
        // top up with recently-used words so the widget isn't empty for
        // someone who hasn't saved any to the notebook yet.
        var words = vocab.studying
        for w in vocab.usedWords() where !words.contains(w) {
            words.append(w)
        }
        let items = words.prefix(maxItems).map {
            StudyWidgetItem(text: $0, note: VocabStore.coreLevelLabel(for: $0))
        }
        StudyWidgetSnapshotStore.save(
            StudyWidgetSnapshot(updatedAt: Date(), total: words.count, items: Array(items)),
            for: .words)
        WidgetCenter.shared.reloadTimelines(ofKind: StudyWidgetSection.words.widgetKind)
    }

    // MARK: - Expressions widget

    @MainActor
    private static func refreshExpressions() {
        // Expressions the user has picked up in talks, newest first. Same
        // source as the Expressions library page, so the widget's tap-through
        // lands on a list that matches what it was showing.
        let entries = VocabStore.shared.expressionEntries()
        let items = entries.prefix(maxItems).map {
            StudyWidgetItem(text: $0.text, note: $0.count > 1 ? "×\($0.count)" : "")
        }
        StudyWidgetSnapshotStore.save(
            StudyWidgetSnapshot(updatedAt: Date(), total: entries.count, items: Array(items)),
            for: .expressions)
        WidgetCenter.shared.reloadTimelines(ofKind: StudyWidgetSection.expressions.widgetKind)
    }
}

private extension VocabStore {
    /// Compact CEFR tag for a notebook word ("B1"), empty when the word isn't
    /// in the core list (proper nouns, tapped transcript words). Rendered as
    /// the trailing caption of a widget list row.
    nonisolated static func coreLevelLabel(for word: String) -> String {
        CoreVocabulary.level(of: lookupKey(for: word)).map { $0.rawValue.uppercased() } ?? ""
    }
}

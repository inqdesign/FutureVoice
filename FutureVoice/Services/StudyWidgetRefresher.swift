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
        // Mirror the app's Futureself palette so the widget's pixel surface
        // wears the same theme the user picked in-app.
        StudyWidgetSnapshotStore.themeIndex = UserDefaults.standard.integer(forKey: "futureselfTheme")
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
        // ONLY the words the user deliberately collected to study (the
        // notebook), newest first — the widget mirrors what they're actively
        // studying, not every word they've ever used.
        let words = vocab.studying
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
        // ONLY the expressions the user bookmarked to study, newest first —
        // mirrors the Words widget (notebook words) at the phrase level.
        let vocab = VocabStore.shared
        let countByKey = Dictionary(vocab.expressionEntries().map { ($0.text, $0.count) },
                                    uniquingKeysWith: { a, _ in a })
        let keys = vocab.studyingExpressions
        let items = keys.prefix(maxItems).map { key -> StudyWidgetItem in
            let count = countByKey[key] ?? 0
            return StudyWidgetItem(text: Self.capitalizedFirst(key),
                                   note: count > 1 ? "×\(count)" : "")
        }
        StudyWidgetSnapshotStore.save(
            StudyWidgetSnapshot(updatedAt: Date(), total: keys.count, items: Array(items)),
            for: .expressions)
        WidgetCenter.shared.reloadTimelines(ofKind: StudyWidgetSection.expressions.widgetKind)
    }

    /// Stored expression keys are lowercased; show with a capital first letter.
    private static func capitalizedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
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

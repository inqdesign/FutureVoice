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
        // …and the language it wears. The extension can't read the app's
        // defaults, so the chrome language rides along with the theme.
        StudyWidgetSnapshotStore.chromeLanguage = UILanguage.chromeLanguage
        refreshWords()
        refreshExpressions()
        refreshProgress()
        refreshBook()
        // The Free Talk widget has no data snapshot, but it wears the theme too
        // — reload it so a theme change repaints it like the others.
        WidgetCenter.shared.reloadTimelines(ofKind: freeTalkWidgetKind)
    }

    /// Fire-and-forget hook for nonisolated call sites (store writes may not
    /// be on the main actor).
    nonisolated static func schedule() {
        Task { @MainActor in refresh() }
    }

    /// Language code stamped into the study snapshots — only when the user is
    /// enrolled in more than one language, so a single-language install never
    /// shows a redundant chip.
    private static var widgetLanguage: String? {
        LanguageScope.enrolled.count > 1 ? LanguageScope.active : nil
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
            StudyWidgetSnapshot(updatedAt: Date(), total: words.count, items: Array(items),
                                language: widgetLanguage),
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
            StudyWidgetSnapshot(updatedAt: Date(), total: keys.count, items: Array(items),
                                language: widgetLanguage),
            for: .expressions)
        WidgetCenter.shared.reloadTimelines(ofKind: StudyWidgetSection.expressions.widgetKind)
    }

    // MARK: - Progress widget

    /// Today's goal + streak + review/study counts — the same deterministic
    /// numbers the home dashboard shows, mirrored to the App Group so the
    /// progress widget can render them without touching the stores directly.
    @MainActor
    private static func refreshProgress() {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }
        // Same definition as the home ring — see PracticeStats.todayTalkSeconds.
        let todaySeconds = PracticeStats.todayTalkSeconds(sessions: sessions)
        let goal = UserDefaults.standard.integer(forKey: "futurevoice.dailyGoalMinutes")
        let vocab = VocabStore.shared
        let snapshot = StudyProgressSnapshot(
            updatedAt: Date(),
            todaySeconds: todaySeconds,
            goalMinutes: goal > 0 ? goal : 10,
            streakDays: PracticeStats.snapshot().streakDays,
            dueCount: DrillStore.shared.dueCount(),
            studyingWords: vocab.studying.count,
            studyingExpressions: vocab.studyingExpressions.count)
        StudyWidgetSnapshotStore.saveProgress(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: progressWidgetKind)
        // The streak widget reads the same snapshot.
        WidgetCenter.shared.reloadTimelines(ofKind: streakWidgetKind)
    }

    // MARK: - Continue widget (one in-progress book → its detail page)

    /// The single most-recently-studied book that's started but not mastered,
    /// across Talk and Watch. Mirrors PracticeTab's "Studying" grid logic so
    /// the widget points at the same book the app would. Progress is derived
    /// deterministically (no LLM) — TalkCurriculum for talks, the scenario's
    /// own curriculum for watch books.
    @MainActor
    private static func refreshBook() {
        struct Candidate { var date: Date; var snapshot: StudyBookSnapshot }
        var candidates: [Candidate] = []

        // Talk books — started, not yet fully mastered.
        let proficiency = CEFRLevel(rawValue:
            UserDefaults.standard.string(forKey: "futurevoice.proficiency") ?? "") ?? .b1
        let shadowAttempts = ShadowAttemptStore.shared.load()
        let talks = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil }
        for session in talks {
            let cur = TalkCurriculum.build(session: session,
                                           proficiency: proficiency,
                                           shadowAttempts: shadowAttempts)
            guard cur.masteredCount > 0, !cur.isMastered else { continue }
            let date = cur.lastStudiedAt ?? session.endedAt ?? session.startedAt
            candidates.append(Candidate(date: date, snapshot: StudyBookSnapshot(
                updatedAt: Date(), hasBook: true, kind: "talk",
                id: session.id.uuidString, title: session.displayTitle,
                // Subtitles are DATA by the time the widget sees them, so they
                // have to be resolved here — the extension can only draw them.
                subtitle: chrome("Talk"), mastered: cur.masteredCount, total: cur.totalCount)))
        }

        // Watch books — scenarios with progress that aren't archived/mastered.
        for sc in ScenarioStore.shared.load() where !sc.isArchived && !sc.isMastered {
            guard let cur = sc.curriculum, cur.masteredCount > 0 else { continue }
            let masteryDate = (cur.words + cur.expressions + cur.shadowLines)
                .compactMap(\.masteredAt).max()
            let date = masteryDate ?? sc.lastUsedAt ?? sc.createdAt
            let subtitle = sc.role.isEmpty
                ? (sc.isTopic == true ? chrome("News topic") : chrome("Situation"))
                : String(format: chrome("with %@"), sc.role)
            candidates.append(Candidate(date: date, snapshot: StudyBookSnapshot(
                updatedAt: Date(), hasBook: true, kind: "watch",
                id: sc.id.uuidString, title: sc.cardTitle,
                subtitle: subtitle, mastered: cur.masteredCount, total: cur.totalCount)))
        }

        let best = candidates.max { $0.date < $1.date }?.snapshot ?? .empty
        StudyWidgetSnapshotStore.saveBook(best)
        WidgetCenter.shared.reloadTimelines(ofKind: bookWidgetKind)
    }

    /// Stored expression keys are lowercased; show with a capital first letter.
    private static func capitalizedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}

extension VocabStore {
    /// Compact CEFR tag for a notebook word ("B1"), empty when the word isn't
    /// in the core list (proper nouns, tapped transcript words). Rendered as
    /// the trailing caption of a widget list row.
    nonisolated static func coreLevelLabel(for word: String) -> String {
        CoreVocabulary.level(of: lookupKey(for: word)).map { $0.rawValue.uppercased() } ?? ""
    }
}

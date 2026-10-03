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
        refreshCheapParts()
        refreshBook()
        // The Free Talk widget has no data snapshot, but it wears the theme too
        // — reload it so a theme change repaints it like the others.
        WidgetCenter.shared.reloadTimelines(ofKind: freeTalkWidgetKind)
    }

    /// The same refresh, handing the main thread back between books. The
    /// book pass rebuilds every talk book, and a cold one (first tagger use
    /// of the launch) is ~17 ms a book in the simulator — held in one piece
    /// it was the stutter under the Talk ring on launch and under the first
    /// tab switch (2026-09-28). Only the background edge needs the snapshot
    /// written before it returns; everything else comes through here.
    @MainActor
    private static func refreshYielding() async {
        refreshCheapParts()
        await Task.yield()
        guard let best = await bestBookYielding() else { return }
        StudyWidgetSnapshotStore.saveBook(best)
        WidgetCenter.shared.reloadTimelines(ofKind: bookWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: freeTalkWidgetKind)
    }

    @MainActor
    private static func refreshCheapParts() {
        // Today's promise entry first: the widget's streak reads it.
        PromiseJudge.refresh()
        // Mirror the app's Futureself palette so the widget's pixel surface
        // wears the same theme the user picked in-app.
        StudyWidgetSnapshotStore.themeIndex = UserDefaults.standard.integer(forKey: "futureselfTheme")
        // …and the language it wears. The extension can't read the app's
        // defaults, so the chrome language rides along with the theme.
        StudyWidgetSnapshotStore.chromeLanguage = UILanguage.chromeLanguage
        refreshWords()
        refreshExpressions()
        refreshProgress()
    }

    /// Fire-and-forget hook for nonisolated call sites (store writes may not
    /// be on the main actor).
    ///
    /// COALESCED, and never in the same run-loop turn as the write. A single
    /// "I know" on a word card writes three files, and each write asked for
    /// a refresh that rebuilt every talk book on the main thread — 30 books
    /// ≈ 515 ms in the simulator (2026-09-23), more on a phone — before the
    /// button could repaint, which the learner reported as the tap
    /// stuttering. One refresh per burst of writes, after the burst; the
    /// scene-phase edges still call `refresh()` directly, so a background
    /// exit never loses the snapshot.
    nonisolated static func schedule() {
        Task { @MainActor in
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(coalesceSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                pending = nil
                await refreshYielding()
            }
        }
    }

    @MainActor private static var pending: Task<Void, Never>?
    private static let coalesceSeconds = 0.4

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
        let todaySeconds = PracticeStats.todayTalkSeconds()
        let goal = UserDefaults.standard.integer(forKey: "futurevoice.dailyGoalMinutes")
        let vocab = VocabStore.shared
        let snapshot = StudyProgressSnapshot(
            updatedAt: Date(),
            todaySeconds: todaySeconds,
            goalMinutes: goal > 0 ? goal : 10,
            streakDays: PracticeStats.snapshot().streakDays,
            dueCount: DrillStore.shared.dueCount(),
            studyingWords: vocab.studying.count,
            studyingExpressions: vocab.studyingExpressions.count,
            // The streak's rule, not the ring's — see StudyProgressSnapshot.
            metToday: PracticeStats.studied())
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
        let inputs = BookInputs()
        var best = BookPick()
        for session in inputs.talks { best.consider(talkBook(session, inputs)) }
        best.considerScenarios()
        StudyWidgetSnapshotStore.saveBook(best.snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: bookWidgetKind)
    }

    /// `refreshBook`, one talk book per turn of the main thread. nil when a
    /// newer pass cancelled this one — it then writes nothing.
    @MainActor
    private static func bestBookYielding() async -> StudyBookSnapshot? {
        let inputs = BookInputs()
        var best = BookPick()
        for session in inputs.talks {
            best.consider(talkBook(session, inputs))
            await Task.yield()
            if Task.isCancelled { return nil }
        }
        best.considerScenarios()
        return best.snapshot
    }

    @MainActor
    private struct BookInputs {
        let proficiency = CEFRLevel(rawValue:
            UserDefaults.standard.string(forKey: "futurevoice.proficiency") ?? "") ?? .b1
        let shadowAttempts = ShadowAttemptStore.shared.load()
        let drillCards = DrillStore.shared.load()
        // Talk books — started, not yet fully mastered.
        let talks = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil }
    }

    /// The most recently studied book wins.
    @MainActor
    private struct BookPick {
        private var bestDate: Date?
        private(set) var snapshot = StudyBookSnapshot.empty

        mutating func consider(_ candidate: (date: Date, snapshot: StudyBookSnapshot)?) {
            guard let candidate else { return }
            if let bestDate, candidate.date <= bestDate { return }
            bestDate = candidate.date
            snapshot = candidate.snapshot
        }

        /// Watch books — scenarios with progress that aren't archived/mastered.
        mutating func considerScenarios() {
            for sc in ScenarioStore.shared.load() where !sc.isArchived && !sc.isMastered {
                guard let cur = sc.curriculum, cur.masteredCount > 0 else { continue }
                let masteryDate = (cur.words + cur.expressions + cur.shadowLines)
                    .compactMap(\.masteredAt).max()
                let date = masteryDate ?? sc.lastUsedAt ?? sc.createdAt
                let subtitle = sc.role.isEmpty
                    ? (sc.isTopic == true ? chrome("News topic") : chrome("Situation"))
                    : String(format: chrome("with %@"), sc.role)
                consider((date, StudyBookSnapshot(
                    updatedAt: Date(), hasBook: true, kind: "watch",
                    id: sc.id.uuidString, title: sc.cardTitle,
                    subtitle: subtitle, mastered: cur.masteredCount, total: cur.totalCount)))
            }
        }
    }

    @MainActor
    private static func talkBook(_ session: Session,
                                 _ inputs: BookInputs) -> (date: Date, snapshot: StudyBookSnapshot)? {
        let cur = TalkCurriculum.build(session: session,
                                       proficiency: inputs.proficiency,
                                       shadowAttempts: inputs.shadowAttempts,
                                       drillCards: inputs.drillCards)
        guard cur.masteredCount > 0, !cur.isMastered else { return nil }
        let date = cur.lastStudiedAt ?? session.endedAt ?? session.startedAt
        return (date, StudyBookSnapshot(
            updatedAt: Date(), hasBook: true, kind: "talk",
            id: session.id.uuidString, title: session.displayTitle,
            // Subtitles are DATA by the time the widget sees them, so they
            // have to be resolved here — the extension can only draw them.
            subtitle: chrome("Talk"), mastered: cur.masteredCount, total: cur.totalCount))
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

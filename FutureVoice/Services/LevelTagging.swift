import Foundation

/// Runs `LevelTagger` in the background and files the result in
/// `LearnerStateStore` (docs/personal-report-plan.md, step 3).
///
/// Two doors: every talk right after its summary is saved (`afterSummary`),
/// and once per launch a backfill of the learner's recent talks that were
/// never tagged (`backfillSoon`). Never on a critical path: nothing waits on
/// it, the wrap-up board doesn't know it exists, and a failure is one
/// `level_tag_failed` event and otherwise silent — the next summary or
/// launch tries again, up to `LearnerState.maxFailures` per talk.
///
/// ONE call at a time: each job waits for the one before it, so a backfill
/// of fifteen talks is fifteen calls in a row, never a burst.
@MainActor
final class LevelTagging {
    static let shared = LevelTagging()

    /// How many recent talks the launch backfill looks at.
    static let backfillCount = 15
    /// After launch, so the first frames (the Talk ring, the widget refresh)
    /// never share the main thread or the network with it.
    static let backfillDelay: Duration = .seconds(20)

    private var tail: Task<Void, Never>?
    private var queued = Set<UUID>()
    private var didBackfill = false
    private let store: LearnerStateStore

    init(store: LearnerStateStore = .shared) { self.store = store }

    /// A talk worth tagging: its language has a map and the learner said at
    /// least one line that counts (not a practice call).
    static func isTaggable(_ session: Session) -> Bool {
        LevelMap.load(session.targetLanguage) != nil && session.isLevelEvidence
    }

    /// Right after `SessionSummarizer` saved the talk with its summary.
    func afterSummary(_ session: Session) {
        enqueue(session, source: "summary")
    }

    /// Tags the learner's recent untagged talks in the active language, once
    /// per launch. Already-tagged talks cost nothing (the store says so before
    /// any call), so "once" across launches falls out of the store.
    func backfillSoon() {
        guard !didBackfill, !Self.isQuietRun else { return }
        didBackfill = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.backfillDelay)
            self?.backfill()
        }
    }

    private func backfill() {
        let language = LanguageScope.active
        guard let map = LevelMap.load(language) else { return }
        let all = SessionStore.shared.load().filter {
            LanguageCatalog.sameLanguage($0.targetLanguage, language)
        }
        // A deleted talk's verdicts go with it.
        store.forgetSessions(notIn: Set(all.map(\.id)), language: language)
        let recent = all
            .filter { $0.endedAt != nil && $0.summary != nil && Self.isTaggable($0) }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .prefix(Self.backfillCount)
        for session in recent where store.needsTagging(
            sessionId: session.id, fingerprint: LevelTagger.fingerprint(session.turns),
            mapVersion: map.version, language: language) {
            enqueue(session, source: "backfill")
        }
    }

    private func enqueue(_ session: Session, source: String) {
        guard Self.isTaggable(session), !Self.isQuietRun, !queued.contains(session.id),
              let map = LevelMap.load(session.targetLanguage) else { return }
        let language = session.targetLanguage
        guard store.needsTagging(sessionId: session.id,
                                 fingerprint: LevelTagger.fingerprint(session.turns),
                                 mapVersion: map.version, language: language) else { return }
        queued.insert(session.id)
        let previous = tail
        let store = self.store
        tail = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            await Self.run(session, source: source, store: store)
            await MainActor.run { _ = self?.queued.remove(session.id) }
        }
    }

    nonisolated private static func run(_ session: Session, source: String,
                                        store: LearnerStateStore) async {
        let started = Date()
        do {
            guard let outcome = try await LevelTagger.tag(session) else { return }
            store.record(outcome.tag, sessionId: session.id, language: session.targetLanguage)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            await MainActor.run {
                Analytics.capture("level_tagged", [
                    "source": source,
                    "items": outcome.tag.items.count,
                    "dropped": outcome.dropped,
                    "ms": ms,
                ])
            }
        } catch {
            store.recordFailure(sessionId: session.id, language: session.targetLanguage)
            let kind = String(describing: error).prefix(120)
            await MainActor.run {
                Analytics.capture("level_tag_failed", ["source": source, "error": String(kind)])
            }
        }
    }

    /// Capture runs and unit tests launch the app too; neither should spend
    /// a call or write a learner file.
    private static var isQuietRun: Bool {
        UserDefaults.standard.string(forKey: "capture") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

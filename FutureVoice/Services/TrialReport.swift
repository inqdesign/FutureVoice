import Foundation

/// The free twenty minutes, read back as a report (2026-10-19, founder: "when
/// the free time runs out, don't just put the paywall up — give them a report
/// of what those minutes showed, a test, their level, and a routine to keep
/// going with").
///
/// It is the weekly deck (`WeekRecapSheet`, `.trial` mode) over the window
/// from the first talk to now, then three cards the week doesn't have: a test
/// the learner must take (built from the same window, `WeeklyTestEngine.Scope`),
/// the level — the FIRST formal assessment, run early (`assessTrialLevel`)
/// because twenty minutes of call time is rarely fifteen of the learner's own
/// speech, which is the normal gate — and the routine, whose button is the
/// way to the plans. The plans are the last card, never the first thing.
///
/// Who sees it: a free account that has NEVER had a subscription
/// (`subscriptionStatus == "inactive"`; a lapsed subscriber's empty pool is
/// not a trial ending) with the pool spent and at least one talk spoken in.
/// It is offered at the end of the call that spent the pool, and again on a
/// later launch if it was closed before the routine card — at most
/// `maxOffers` times, then it lives on only as a door from nowhere: the deck
/// is a moment, not a page.
struct TrialReport: Codable {
    var recap: WeekRecap
    var targetLanguage: String
    /// The trial test, once built. Read back from `WeeklyTestStore` by id.
    var testId: UUID?
    /// True once the test could not be built from the window — too little
    /// material — so the deck moves on instead of asking for the impossible.
    var testThin: Bool = false
    var level: String?
    var levelRationale: String?
    var builtAt: Date
}

@MainActor
enum TrialReportStore {
    static let maxOffers = 2
    /// Fewer than the weekly paper's five: twenty minutes is a small window,
    /// and a required test of two questions is still a test of the learner's
    /// own lines. Below this the test card says so and lets them past.
    static let minTestItems = 3

    private static let offersKey = "futurevoice.trialReport.offers"
    private static let finishedKey = "futurevoice.trialReport.finished"

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trial_report.json")
    }

    static var finished: Bool {
        get { UserDefaults.standard.bool(forKey: finishedKey) }
        set { UserDefaults.standard.set(newValue, forKey: finishedKey) }
    }

    static var offers: Int {
        get { UserDefaults.standard.integer(forKey: offersKey) }
        set { UserDefaults.standard.set(newValue, forKey: offersKey) }
    }

    /// Sessions the learner spoke in — the only ones a report can read.
    private static func spokenSessions() -> [Session] {
        SessionStore.shared.loadAcrossLanguages()
            .filter { $0.endedAt != nil && $0.turns.contains { $0.role == .user } }
    }

    /// The account side of the gate. The device side (`offers`, `finished`,
    /// a spoken talk on file) is checked here too, so one call answers it.
    static func shouldOffer(_ account: AccountStatus) -> Bool {
        !finished && offers < maxOffers && canOpen(account)
    }

    /// Whether the report has anything to say to this account at all — the
    /// gate a tapped link (`futurevoice://trialreport`, the push to those who
    /// left at the wall) answers, since a tap is asking even after two offers.
    static func canOpen(_ account: AccountStatus) -> Bool {
        guard account.subscriptionStatus == "inactive",
              !account.unlimited, account.needsSubscription else { return false }
        return !spokenSessions().isEmpty
    }

    static func load() -> TrialReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(TrialReport.self, from: data)
    }

    static func save(_ report: TrialReport) {
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// The saved report, or a fresh one from the first talk to now. Built
    /// once: the free minutes are over, so the window cannot grow, and a
    /// second build would rewrite a coach the learner already read.
    static func current(targetLanguage: String, now: Date = Date()) -> TrialReport {
        if let kept = load(), kept.targetLanguage == targetLanguage { return kept }
        let first = spokenSessions().compactMap { $0.turns.first?.timestamp ?? $0.startedAt }.min() ?? now
        var recap = WeekRecapBuilder.build(start: Calendar.current.startOfDay(for: first),
                                           end: now.addingTimeInterval(1))
        // No week before a trial; the talk card's comparison line stays quiet.
        recap.previousTalkSeconds = 0
        recap.previousShadowAverage = nil
        // The meter's log is pruned at 45 days; a pool spent before that
        // still has its talks, so their own lengths stand in.
        if recap.talkSeconds == 0 {
            recap.talkSeconds = recap.talks.reduce(0) { $0 + $1.minutes * 60 }
        }
        var report = TrialReport(recap: recap, targetLanguage: targetLanguage, builtAt: now)
        #if DEBUG
        // `-trialthin 1`: skip the test, to see the level and routine cards.
        report.testThin = UserDefaults.standard.bool(forKey: "trialthin")
        #endif
        save(report)
        return report
    }

    /// Developer: start over.
    static func reset() {
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.removeObject(forKey: offersKey)
        UserDefaults.standard.removeObject(forKey: finishedKey)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension AppState {
    /// The level for the trial report. An assessment already on file wins.
    /// Otherwise the first one is run NOW, past the 15-minute speech gate
    /// (founder's call, 2026-10-19): it is saved like any report, so Progress
    /// shows the same level, and the next one waits on the ordinary cadence.
    /// No level-up sheet — the report's own card is the announcement. When
    /// the talks can't carry an assessment, the median of their per-talk
    /// reads stands in; nil only when there is nothing at all to read.
    func assessTrialLevel() async -> (level: CEFRLevel, rationale: String?)? {
        if let report = weeklyReports.sorted(by: { $0.generatedAt > $1.generatedAt }).first,
           let level = report.cefrLevel.flatMap(CEFRLevel.init(rawValue:)) {
            return (level, report.levelRationale)
        }
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil && !$0.isPractice }
        if !sessions.isEmpty {
            do {
                let report = try await WeeklyReportEngine.generate(
                    endedSessions: sessions, lastReport: nil,
                    targetLanguage: targetLanguage, nativeLanguage: nativeLanguage)
                WeeklyReportStore.shared.save(report)
                weeklyReports = WeeklyReportStore.shared.load()
                if let level = report.cefrLevel.flatMap(CEFRLevel.init(rawValue:)) {
                    Analytics.capture("level_assessed", [
                        "from": proficiency.rawValue, "to": level.rawValue,
                        "reason": "trial_report", "talks": report.sessionCount, "first": true
                    ])
                    proficiency = level
                    return (level, report.levelRationale)
                }
            } catch {
                Analytics.capture("level_assess_failed", [
                    "reason": "trial_report",
                    "error": String(describing: error).prefix(200).description
                ])
            }
        }
        let reads = sessions.compactMap { $0.summary?.scorecard?.cefrLevel?.lowercased() }
            .compactMap(CEFRLevel.init(rawValue:))
            .sorted { CoreVocabulary.levelRank($0) < CoreVocabulary.levelRank($1) }
        guard !reads.isEmpty else { return nil }
        return (reads[reads.count / 2], nil)
    }
}

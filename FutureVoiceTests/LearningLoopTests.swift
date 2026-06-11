import XCTest
@testable import FutureVoice

// MARK: - LearnerProfile.absorb (the session → next-session loop)

final class LearnerProfileAbsorbTests: XCTestCase {

    private func emptyProfile() -> LearnerProfile {
        LearnerProfile(
            id: UUID(), userId: UUID(), targetLanguage: "en",
            proficiencyLevel: .b1, recurringMistakes: [], weakVocabAreas: [],
            strongPatterns: [], totalSessions: 0, totalSpeakingSeconds: 0,
            lastSessionAt: nil, summaryEmbedding: nil
        )
    }

    private func pattern(_ mistake: String, _ correction: String,
                         frequency: Int = 1) -> LearnerPattern {
        LearnerPattern(mistake: mistake, correction: correction,
                       context: "test", frequency: frequency, lastSeenAt: .distantPast)
    }

    private func summary(_ patterns: [LearnerPattern]) -> SessionSummary {
        SessionSummary(phrasesUsed: [], newPatternsDetected: patterns,
                       suggestedDrills: [], overallNote: "", scorecard: nil)
    }

    func testNewPatternsAppendAndCountersUpdate() {
        var p = emptyProfile()
        let now = Date()
        p.absorb(summary: summary([pattern("I go yesterday", "I went yesterday")]),
                 speakingSeconds: 90, now: now)

        XCTAssertEqual(p.recurringMistakes.count, 1)
        XCTAssertEqual(p.totalSessions, 1)
        XCTAssertEqual(p.totalSpeakingSeconds, 90)
        XCTAssertEqual(p.lastSessionAt, now)
        XCTAssertEqual(p.recurringMistakes[0].lastSeenAt, now)
    }

    func testRepeatMistakeBumpsFrequencyInsteadOfDuplicating() {
        var p = emptyProfile()
        p.absorb(summary: summary([pattern("it's depend", "it depends", frequency: 2)]),
                 speakingSeconds: 10)
        // Same pattern again, different casing — must merge, not duplicate.
        p.absorb(summary: summary([pattern("It's Depend", "It Depends", frequency: 1)]),
                 speakingSeconds: 10)

        XCTAssertEqual(p.recurringMistakes.count, 1)
        XCTAssertEqual(p.recurringMistakes[0].frequency, 3)
        XCTAssertEqual(p.totalSessions, 2)
    }

    func testCapsAtTopTenByFrequency() {
        var p = emptyProfile()
        let many = (1...12).map { i in
            pattern("mistake \(i)", "correction \(i)", frequency: i)
        }
        p.absorb(summary: summary(many), speakingSeconds: 10)

        XCTAssertEqual(p.recurringMistakes.count, LearnerProfile.maxRecurringMistakes)
        // Highest-frequency patterns survive; lowest two (1, 2) are dropped.
        XCTAssertEqual(p.recurringMistakes.first?.frequency, 12)
        XCTAssertFalse(p.recurringMistakes.contains { $0.frequency <= 2 })
    }
}

// MARK: - DrillStore (Leitner scheduling + ingest hygiene)

final class DrillStoreTests: XCTestCase {

    private var store: DrillStore!
    private var filename: String!

    override func setUp() {
        super.setUp()
        filename = "test-drills-\(UUID().uuidString).json"
        store = DrillStore(filename: filename)
    }

    override func tearDown() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func summary(phrases: [PhraseFeedback] = [],
                         drills: [String] = []) -> SessionSummary {
        SessionSummary(phrasesUsed: phrases, newPatternsDetected: [],
                       suggestedDrills: drills, overallNote: "", scorecard: nil)
    }

    func testIngestCreatesCardsAndDedupes() {
        let phrase = PhraseFeedback(userSaid: "I go bank",
                                    fluentAlternative: "I went to the bank",
                                    reason: "past tense")
        // Same target twice (phrase + drill) → one card.
        let count = store.ingest(
            summary: summary(phrases: [phrase], drills: ["I went to the bank"]),
            turns: [], sessionId: UUID()
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load().count, 1)
    }

    func testIngestFiltersMetaRules() {
        let count = store.ingest(
            summary: summary(drills: ["using articles correctly", "Could you pass the salt?"]),
            turns: [], sessionId: UUID()
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load().first?.targetPhrase, "Could you pass the salt?")
    }

    func testIngestPicksUpTurnSuggestions() {
        let turn = Turn(id: UUID(), role: .user, audioURL: nil,
                        transcript: "how I can say this",
                        durationMs: 1000, timestamp: Date(),
                        suggestion: TurnSuggestion(alternative: "How can I say this?",
                                                   reason: "word order"))
        let count = store.ingest(summary: summary(), turns: [turn], sessionId: UUID())
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load().first?.sourcePhrase, "how I can say this")
    }

    func testLeitnerPromoteAndDemote() {
        let now = Date()
        store.ingest(summary: summary(drills: ["Could you say that again?"]),
                     turns: [], sessionId: UUID(), now: now)
        var card = store.due(now: now).first!
        XCTAssertEqual(card.box, 0)

        // Correct → box 1, due in ~1 day (not due now).
        store.markCorrect(card, at: now)
        XCTAssertTrue(store.due(now: now).isEmpty)
        card = store.load().first!
        XCTAssertEqual(card.box, 1)
        XCTAssertEqual(card.timesCorrect, 1)
        let oneDay: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(card.nextReviewAt.timeIntervalSince(now), oneDay, accuracy: 1)

        // Incorrect → back to box 0, due immediately.
        store.markIncorrect(card, at: now)
        card = store.load().first!
        XCTAssertEqual(card.box, 0)
        XCTAssertEqual(card.timesSeen, 2)
        XCTAssertFalse(store.due(now: now).isEmpty)
    }
}

// MARK: - DrillReminder fire-time policy

@MainActor
final class DrillReminderFireDateTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testDueNowDefersToTomorrowMorning() {
        let now = date(hour: 14)
        let fire = DrillReminder.fireDate(now: now, nextDue: nil, hasDueNow: true)
        XCTAssertNotNil(fire)
        XCTAssertEqual(calendar.component(.hour, from: fire!), 9)
        XCTAssertTrue(calendar.isDate(fire!, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!))
    }

    func testDaytimeDueFiresOnTime() {
        let now = date(hour: 10)
        let due = date(hour: 15, minute: 30)
        let fire = DrillReminder.fireDate(now: now, nextDue: due, hasDueNow: false)
        XCTAssertEqual(fire, due)
    }

    func testEarlyMorningDueClampsToNine() {
        let due = calendar.date(bySettingHour: 3, minute: 0, second: 0,
                                of: calendar.date(byAdding: .day, value: 1, to: Date())!)!
        let fire = DrillReminder.fireDate(now: Date(), nextDue: due, hasDueNow: false)
        XCTAssertEqual(calendar.component(.hour, from: fire!), 9)
        XCTAssertTrue(calendar.isDate(fire!, inSameDayAs: due))
    }

    func testLateNightDueRollsToNextMorning() {
        let due = date(hour: 22, minute: 30)
        let fire = DrillReminder.fireDate(now: date(hour: 10), nextDue: due, hasDueNow: false)
        XCTAssertEqual(calendar.component(.hour, from: fire!), 9)
        XCTAssertTrue(calendar.isDate(fire!, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: due)!))
    }

    func testNothingToScheduleReturnsNil() {
        XCTAssertNil(DrillReminder.fireDate(now: Date(), nextDue: nil, hasDueNow: false))
    }
}

// MARK: - WeeklyReportEngine unlock rules

final class WeeklyReportUnlockTests: XCTestCase {

    private func session(userSeconds: Double, endedAt: Date) -> Session {
        let turn = Turn(id: UUID(), role: .user, audioURL: nil, transcript: "hi",
                        durationMs: Int(userSeconds * 1000), timestamp: endedAt,
                        suggestion: nil)
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                       mode: .conversation, topic: nil,
                       startedAt: endedAt.addingTimeInterval(-60),
                       endedAt: endedAt, turns: [turn], summary: nil)
    }

    func testFirstReportLockedUntilFifteenMinutes() {
        let now = Date()
        let sessions = [session(userSeconds: 10 * 60, endedAt: now)]
        let state = WeeklyReportEngine.unlockState(endedSessions: sessions,
                                                   lastReport: nil, now: now)
        guard case .lockedFirst(let acc, let req) = state else {
            return XCTFail("expected lockedFirst, got \(state)")
        }
        XCTAssertEqual(acc, 600, accuracy: 0.1)
        XCTAssertEqual(req, 900, accuracy: 0.1)
    }

    func testFirstReportReadyAtFifteenMinutes() {
        let now = Date()
        let sessions = [
            session(userSeconds: 8 * 60, endedAt: now.addingTimeInterval(-3600)),
            session(userSeconds: 7 * 60, endedAt: now),
        ]
        let state = WeeklyReportEngine.unlockState(endedSessions: sessions,
                                                   lastReport: nil, now: now)
        guard case .ready = state else {
            return XCTFail("expected ready, got \(state)")
        }
    }

    func testNextReportWaitsForBothCadenceAndMaterial() {
        let now = Date()
        let report = WeeklyReport(
            id: UUID(),
            periodStart: now.addingTimeInterval(-14 * 86400),
            periodEnd: now.addingTimeInterval(-2 * 86400),   // 2 days ago
            sessionCount: 5, targetLanguage: "en",
            newExpressions: [], repeatedMistakes: [], suggestedExpressions: [],
            summary: "", generatedAt: now.addingTimeInterval(-2 * 86400)
        )
        // Plenty of new speaking time, but only 2 days since last report.
        let sessions = [session(userSeconds: 30 * 60, endedAt: now.addingTimeInterval(-3600))]
        let state = WeeklyReportEngine.unlockState(endedSessions: sessions,
                                                   lastReport: report, now: now)
        guard case .lockedNext(let days, let secs) = state else {
            return XCTFail("expected lockedNext, got \(state)")
        }
        XCTAssertEqual(days, 5)
        XCTAssertEqual(secs, 0, accuracy: 0.1)
    }
}

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

    func testGotItGraduatesInOneDrop() {
        let now = Date()
        store.ingest(summary: summary(drills: ["Could you say that again?"]),
                     turns: [], sessionId: UUID(), now: now)
        var card = store.due(now: now).first!
        XCTAssertEqual(card.box, 0)

        // "Got it" GRADUATES — the learner said they know it, so the card goes
        // to the top rung in one drop (it used to climb one box at a time,
        // which meant five Got-its before anything left the to-study pile).
        // Back in ~30 days, the top rung's own interval.
        store.markKnown(card, at: now)
        XCTAssertTrue(store.due(now: now).isEmpty)
        card = store.load().first!
        XCTAssertEqual(card.box, DrillStore.maxBox)
        XCTAssertEqual(card.timesCorrect, 1)
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        XCTAssertEqual(card.nextReviewAt.timeIntervalSince(now), thirtyDays, accuracy: 1)
    }

    func testIncorrectDropsARungAndComesBackNow() {
        let now = Date()
        store.ingest(summary: summary(drills: ["Could you say that again?"]),
                     turns: [], sessionId: UUID(), now: now)
        let fresh = store.due(now: now).first!
        // Start from a rung above the floor, the way a card that has been
        // reviewed once sits.
        store.snooze(fresh, box: 1, until: now.addingTimeInterval(24 * 60 * 60), at: now)

        store.markIncorrect(store.load().first!, at: now)
        let card = store.load().first!
        XCTAssertEqual(card.box, 0)
        XCTAssertEqual(card.timesSeen, 2)
        XCTAssertFalse(store.due(now: now).isEmpty)
    }

    /// The delay bins are the "not yet" answers — they must NOT graduate, or
    /// the ladder stops meaning anything and every drop empties the pile.
    func testSnoozeKeepsTheCardBelowTheTopRung() {
        let now = Date()
        store.ingest(summary: summary(drills: ["Could you say that again?"]),
                     turns: [], sessionId: UUID(), now: now)
        let card = store.due(now: now).first!
        store.snooze(card, box: 1, until: now.addingTimeInterval(24 * 60 * 60), at: now)

        let updated = store.load().first!
        XCTAssertLessThan(updated.box, DrillStore.maxBox)
    }
}

// MARK: - PracticeStats.shadowPicks curation

final class ShadowPicksTests: XCTestCase {

    private func turn(_ text: String, role: TurnRole = .fluentSelf,
                      id: UUID = UUID()) -> Turn {
        Turn(id: id, role: role, audioURL: nil, transcript: text,
             durationMs: 0, timestamp: Date(), suggestion: nil)
    }

    private func session(_ turns: [Turn], topic: String = "Coffee chat",
                         endedAt: Date = Date()) -> Session {
        Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                mode: .conversation, topic: topic,
                startedAt: endedAt.addingTimeInterval(-300),
                endedAt: endedAt, turns: turns, summary: nil)
    }

    private func attempt(turnId: UUID, score: Int, target: String = "x",
                         at date: Date = Date()) -> ShadowAttempt {
        ShadowAttempt(turnId: turnId, targetText: target, learnerTranscript: "",
                      recordingFilename: nil, matchScore: score,
                      pronunciation: "", pacing: "", fix: "", createdAt: date)
    }

    func testFreshLinesComeFromSessionsAndSkipShortOnes() {
        let s = session([
            turn("Really?"),                                  // too short
            turn("Honestly the weather has been rough lately."),
            turn("I should say this", role: .user),           // wrong role
        ])
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: [], level: .b1)
        XCTAssertEqual(picks.count, 1)
        XCTAssertTrue(picks[0].reason.hasPrefix("From: Coffee chat"))
    }

    func testAttemptedLinesAreNotFreshButLowScoresRetry() {
        let goodId = UUID(), badId = UUID()
        let s = session([
            turn("This line was already shadowed well.", id: goodId),
            turn("This line went badly and deserves a retry.", id: badId),
        ])
        let attempts = [
            attempt(turnId: goodId, score: 92),
            attempt(turnId: badId, score: 60),
        ]
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: attempts, level: .b1)
        XCTAssertEqual(picks.count, 1)
        XCTAssertTrue(picks[0].reason.contains("Retry — last score 60"))
        XCTAssertEqual(picks[0].turn.id, badId)
    }

    func testLevelBandPrefersLinesSizedToLearner() {
        // A1 band = 4...8 words: the 16-word line must lose to the 6-word one.
        let s = session([
            turn("This particular sentence keeps going on and on with far more words than any beginner needs."),
            turn("Shall we grab a coffee soon?"),
        ])
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: [], level: .a1)
        XCTAssertEqual(picks.count, 1)
        XCTAssertEqual(picks[0].turn.transcript, "Shall we grab a coffee soon?")
    }

    func testLevelBandFallsBackWhenNothingFits() {
        // Only an out-of-band line exists — better to suggest it than nothing.
        let long = "This particular sentence keeps going on and on with far more words than any beginner needs."
        let picks = PracticeStats.shadowPicks(sessions: [session([turn(long)])],
                                              attempts: [], level: .a1)
        XCTAssertEqual(picks.count, 1)
        XCTAssertEqual(picks[0].turn.transcript, long)
    }

    func testNewerGoodAttemptSupersedesOldBadOne() {
        let id = UUID()
        let s = session([turn("Practice makes the line much better.", id: id)])
        let attempts = [
            attempt(turnId: id, score: 50, at: Date().addingTimeInterval(-3600)),
            attempt(turnId: id, score: 88, at: Date()),
        ]
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: attempts, level: .b1)
        XCTAssertTrue(picks.isEmpty)
    }

    func testOpenerIsSkippedWhenOtherLinesQualify() {
        // The session's first fluent-self line is the scripted ice-breaker —
        // it must NOT be the suggested shadow line when substance exists.
        let s = session([
            turn("Hey good to catch up again today!"),          // opener, in-band
            turn("Honestly the negotiation dragged on forever."),
        ])
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: [], level: .b1)
        XCTAssertEqual(picks.count, 1)
        XCTAssertEqual(picks[0].turn.transcript, "Honestly the negotiation dragged on forever.")
    }

    func testOpenerIsLastResortWhenAlone() {
        // A session where the opener is the ONLY line — better it than nothing.
        let s = session([turn("Hey good to catch up again today!")])
        let picks = PracticeStats.shadowPicks(sessions: [s], attempts: [], level: .b1)
        XCTAssertEqual(picks.count, 1)
    }

    func testLimitAndFreshFirstMix() {
        let badId = UUID()
        let s = session([
            turn("First fresh line with enough words here."),
            turn("Second fresh line with enough words too."),
            turn("Third fresh line that also qualifies fine."),
            turn("The one that scored low last time around.", id: badId),
        ])
        let picks = PracticeStats.shadowPicks(
            sessions: [s],
            attempts: [attempt(turnId: badId, score: 40)],
            level: .b1,
            limit: 3
        )
        XCTAssertEqual(picks.count, 3)
        XCTAssertEqual(picks.filter { $0.reason.hasPrefix("From:") }.count, 2)
        XCTAssertEqual(picks.filter { $0.reason.hasPrefix("Retry") }.count, 1)
    }
}

// MARK: - Session.displayTitle fallbacks

final class DisplayTitleTests: XCTestCase {

    private func session(topic: String?, firstUserLine: String?) -> Session {
        var turns: [Turn] = [
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "Hey, how's it going?", durationMs: 0,
                 timestamp: Date(), suggestion: nil),
        ]
        if let line = firstUserLine {
            turns.append(Turn(id: UUID(), role: .user, audioURL: nil,
                              transcript: line, durationMs: 0,
                              timestamp: Date(), suggestion: nil))
        }
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                       mode: .conversation, topic: topic,
                       startedAt: Date(), endedAt: Date(), turns: turns, summary: nil)
    }

    func testTopicWins() {
        XCTAssertEqual(session(topic: "Kita pickup", firstUserLine: "hello there").displayTitle,
                       "Kita pickup")
    }

    func testLegacySessionUsesFirstUserWords() {
        let s = session(topic: nil,
                        firstUserLine: "I wanted to talk about my trip to Lisbon last month")
        XCTAssertEqual(s.displayTitle, "\u{201C}I wanted to talk about my…\u{201D}")
    }

    func testNoUserTurnsFallsBackToGeneric() {
        XCTAssertEqual(session(topic: "  ", firstUserLine: nil).displayTitle, "Conversation")
    }

    func testWatchDialoguePrefersOwnTitle() {
        var d = WatchDialogue(counterpartId: UUID(), scenarioTitle: "Catch-up call",
                              scenarioBlurb: "", title: "Boram's moving news", turns: [])
        XCTAssertEqual(d.displayTitle, "Boram's moving news")
        d.title = nil
        XCTAssertEqual(d.displayTitle, "Catch-up call")
    }
}

// MARK: - NewsTopicEngine category interleave

final class NewsInterleaveTests: XCTestCase {

    private func item(_ cat: String, _ title: String) -> NewsTopicEngine.ServerTopic {
        NewsTopicEngine.ServerTopic(category: cat, title: title, blurb: "", facts: nil)
    }

    func testRoundRobinAcrossCategories() {
        let mixed = NewsTopicEngine.interleaved([
            item("ai", "a1"), item("ai", "a2"), item("ai", "a3"),
            item("music", "m1"), item("music", "m2"),
            item("travel", "t1"),
        ], cap: 4)
        XCTAssertEqual(mixed.map(\.title), ["a1", "m1", "t1", "a2"])
    }

    func testCapAndExhaustion() {
        let mixed = NewsTopicEngine.interleaved([item("ai", "a1"), item("ai", "a2")], cap: 6)
        XCTAssertEqual(mixed.count, 2)
        XCTAssertTrue(NewsTopicEngine.interleaved([], cap: 6).isEmpty)
    }
}

// MARK: - NewsTopicStore daily cache

final class NewsTopicStoreTests: XCTestCase {

    private var store: NewsTopicStore!
    private var filename: String!

    override func setUp() {
        super.setUp()
        filename = "test-news-\(UUID().uuidString).json"
        store = NewsTopicStore(filename: filename)
    }

    override func tearDown() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private let topics = [SuggestedTopic(title: "Did you see the launch?", blurb: "A rocket launched.")]

    func testFreshCacheHitsForSameInterests() {
        store.save(topics, interests: ["AI", "music"])
        let cached = store.valid(for: ["AI", "music"])
        XCTAssertEqual(cached?.first?.title, "Did you see the launch?")
    }

    func testInterestOrderAndCaseDoNotInvalidate() {
        store.save(topics, interests: ["AI", "Music"])
        XCTAssertNotNil(store.valid(for: ["music", "ai"]))
    }

    func testChangedInterestsInvalidate() {
        store.save(topics, interests: ["AI"])
        XCTAssertNil(store.valid(for: ["cooking"]))
    }

    func testStaleCacheInvalidates() {
        let yesterday = Date().addingTimeInterval(-NewsTopicStore.maxAge - 60)
        store.save(topics, interests: ["AI"], now: yesterday)
        XCTAssertNil(store.valid(for: ["AI"]))
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
        // Fixed `now` (10:00) so tomorrow-3am stays OUTSIDE the 12-hour
        // fire-exactly window at any time of day the suite runs — this test
        // exercises the waking-hours clamp, not that bypass.
        let now = date(hour: 10)
        let due = calendar.date(bySettingHour: 3, minute: 0, second: 0,
                                of: calendar.date(byAdding: .day, value: 1, to: now)!)!
        let fire = DrillReminder.fireDate(now: now, nextDue: due, hasDueNow: false)
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

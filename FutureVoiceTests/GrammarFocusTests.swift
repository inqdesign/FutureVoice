import XCTest
@testable import FutureVoice

/// Pins which recurring mistake a call focuses on, and when one retires.
final class GrammarFocusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func pattern(_ m: String, freq: Int, daysAgo: Double) -> LearnerPattern {
        LearnerPattern(mistake: m, correction: m + "!", context: "ctx", frequency: freq,
                       lastSeenAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    private func profile(_ ps: [LearnerPattern]) -> LearnerProfile {
        LearnerProfile(id: UUID(), userId: UUID(), targetLanguage: "en", proficiencyLevel: .b1,
                       recurringMistakes: ps, weakVocabAreas: [], strongPatterns: [],
                       totalSessions: 0, totalSpeakingSeconds: 0, lastSessionAt: nil,
                       summaryEmbedding: nil)
    }

    private func focusedSession(_ p: LearnerPattern, repeats: Int, daysAgo: Double) -> Session {
        var s = Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                        topic: nil, startedAt: now.addingTimeInterval(-daysAgo * 86_400),
                        endedAt: now.addingTimeInterval(-daysAgo * 86_400 + 600),
                        turns: [], summary: nil)
        s.grammarFocus = GrammarFocusRecord(patternKey: LearnerProfile.patternKey(p), label: "L",
                                            mistake: p.mistake, correction: p.correction,
                                            repeats: repeats)
        return s
    }

    func testPicksMostFrequentFreshPattern() {
        let once = pattern("once", freq: 1, daysAgo: 1)
        let often = pattern("often", freq: 5, daysAgo: 3)
        let some = pattern("some", freq: 2, daysAgo: 1)
        let stale = pattern("stale", freq: 9, daysAgo: 60)
        let picked = GrammarFocus.pick(from: profile([once, often, some, stale]), sessions: [], now: now)
        XCTAssertEqual(picked?.mistake, "often")
    }

    func testNothingWhenNoPatternRepeats() {
        XCTAssertNil(GrammarFocus.pick(from: profile([pattern("once", freq: 1, daysAgo: 1)]),
                                       sessions: [], now: now))
    }

    func testTwoCleanCallsRetireAndARedetectionBringsItBack() {
        let often = pattern("often", freq: 5, daysAgo: 10)
        let some = pattern("some", freq: 2, daysAgo: 1)
        let clean = [focusedSession(often, repeats: 0, daysAgo: 5),
                     focusedSession(often, repeats: 0, daysAgo: 2)]
        XCTAssertEqual(GrammarFocus.pick(from: profile([often, some]), sessions: clean, now: now)?.mistake,
                       "some")
        // One of the two still had the slip — not retired.
        let mixed = [focusedSession(often, repeats: 0, daysAgo: 5),
                     focusedSession(often, repeats: 2, daysAgo: 2)]
        XCTAssertEqual(GrammarFocus.pick(from: profile([often, some]), sessions: mixed, now: now)?.mistake,
                       "often")
        // Seen again by a summary after those clean calls → back in focus.
        let back = pattern("often", freq: 6, daysAgo: 1)
        XCTAssertEqual(GrammarFocus.pick(from: profile([back, some]), sessions: clean, now: now)?.mistake,
                       "often")
    }
}

/// The strip shows only what changed, with a word of context.
final class GrammarFocusPairTests: XCTestCase {
    func testCompactKeepsTheChangeAndOneWord() {
        let (a, b) = GrammarFocusPair.compact("Yesterday I go to the office", "Yesterday I went to the office")
        XCTAssertEqual(a, "…I go to…")
        XCTAssertEqual(b, "…I went to…")
        let (c, d) = GrammarFocusPair.compact("I have a meeting in Monday.", "I have a meeting on Monday.")
        XCTAssertEqual(c, "…meeting in Monday.")
        XCTAssertEqual(d, "…meeting on Monday.")
    }

    func testUnspacedComparesCharacters() {
        let (a, b) = GrammarFocusPair.compact("昨日学校に行く。", "昨日学校に行った。")
        XCTAssertEqual(a, "…に行く。")
        XCTAssertEqual(b, "…に行った。")
    }

    func testNothingSharedKeepsBoth() {
        let (a, b) = GrammarFocusPair.compact("goed", "went")
        XCTAssertEqual(a, "goed"); XCTAssertEqual(b, "went")
    }
}

/// Coach mode defaults on for beginners until the learner flips it.
final class CoachModeDefaultTests: XCTestCase {
    func testLevelDecidesUntilTheLearnerChooses() {
        XCTAssertTrue(CoachMode.resolve(choice: nil, levelRaw: "a1"))
        XCTAssertTrue(CoachMode.resolve(choice: nil, levelRaw: "a2"))
        XCTAssertFalse(CoachMode.resolve(choice: nil, levelRaw: "b1"))
        XCTAssertFalse(CoachMode.resolve(choice: nil, levelRaw: ""))
        XCTAssertFalse(CoachMode.resolve(choice: false, levelRaw: "a1"))
        XCTAssertTrue(CoachMode.resolve(choice: true, levelRaw: "c1"))
    }
}

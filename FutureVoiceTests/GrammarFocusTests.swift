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
        // A call where the slip came back has the learner saying it.
        if repeats > 0 {
            s.turns = [Turn(id: UUID(), role: .user, audioURL: nil, transcript: p.mistake, durationMs: 3_000,
                            timestamp: s.startedAt, suggestion: nil)]
        }
        s.grammarFocus = GrammarFocusRecord(patternKey: LearnerProfile.patternKey(p), label: "L",
                                            mistake: p.mistake, correction: p.correction,
                                            repeats: repeats)
        return s
    }

    /// A talk in which the learner said `line`.
    private func talk(saying line: String, daysAgo: Double) -> Session {
        let at = now.addingTimeInterval(-daysAgo * 86_400)
        let turn = Turn(id: UUID(), role: .user, audioURL: nil, transcript: line, durationMs: 3_000,
                        timestamp: at, suggestion: nil)
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: nil, startedAt: at, endedAt: at.addingTimeInterval(600),
                       turns: [turn], summary: nil)
    }

    private func picked(_ ps: [LearnerPattern], _ sessions: [Session]) -> String? {
        GrammarFocus.candidates(from: profile(ps), sessions: sessions, now: now).first?.pattern.mistake
    }

    /// The evidence is the transcripts, not the stored frequency: a pattern
    /// at frequency 9 that no talk contains is never a focus (2026-10-08 —
    /// summaries had been copying the profile's patterns back, so the
    /// count rose with nothing said), and one said in two talks is.
    func testFocusNeedsTheSlipInTwoTalks() {
        let inflated = pattern("I go to the office yesterday", freq: 9, daysAgo: 1)
        let real = pattern("explain him the", freq: 2, daysAgo: 3)
        let talks = [talk(saying: "so I will explain him the situation tomorrow", daysAgo: 5),
                     talk(saying: "I had to explain him the plan", daysAgo: 2),
                     talk(saying: "nothing related here", daysAgo: 1)]
        XCTAssertEqual(picked([inflated, real], talks), "explain him the")
        XCTAssertEqual(GrammarFocus.evidence(real, sessions: talks, now: now), 2)
        XCTAssertEqual(GrammarFocus.evidence(inflated, sessions: talks, now: now), 0)
        // One talk is not a pattern.
        XCTAssertNil(picked([real], Array(talks.suffix(2))))
        // A talk older than `freshDays` doesn't count.
        let old = [talk(saying: "explain him the plan", daysAgo: 50), talks[1]]
        XCTAssertNil(picked([real], old))
    }

    func testMostTalksFirst() {
        let a = pattern("a slip", freq: 9, daysAgo: 1)
        let b = pattern("b slip", freq: 2, daysAgo: 1)
        let talks = [talk(saying: "a slip one", daysAgo: 1), talk(saying: "a slip two", daysAgo: 2),
                     talk(saying: "b slip one", daysAgo: 1), talk(saying: "b slip two", daysAgo: 2),
                     talk(saying: "b slip three", daysAgo: 3)]
        XCTAssertEqual(picked([a, b], talks), "b slip")
    }

    func testTwoCleanCallsRetireAndARedetectionBringsItBack() {
        let often = pattern("often slip", freq: 5, daysAgo: 10)
        let some = pattern("some slip", freq: 2, daysAgo: 1)
        let said = [talk(saying: "often slip", daysAgo: 20), talk(saying: "often slip", daysAgo: 15),
                    talk(saying: "some slip", daysAgo: 12), talk(saying: "some slip", daysAgo: 11)]
        let clean = said + [focusedSession(often, repeats: 0, daysAgo: 5),
                            focusedSession(often, repeats: 0, daysAgo: 2)]
        XCTAssertEqual(picked([often, some], clean), "some slip")
        // One of the two still had the slip — not retired.
        let mixed = said + [focusedSession(often, repeats: 0, daysAgo: 5),
                            focusedSession(often, repeats: 2, daysAgo: 2)]
        XCTAssertEqual(picked([often, some], mixed), "often slip")
        // Said again after those clean calls (a summary re-detects it) →
        // back in focus.
        let back = pattern("often slip", freq: 6, daysAgo: 1)
        XCTAssertEqual(picked([back, some], clean + [talk(saying: "often slip", daysAgo: 1)]), "often slip")
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
